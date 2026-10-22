unit Dext.Testing.Design.Server;

interface

uses
  System.SysUtils,
  System.Classes,
  System.SyncObjs,
  System.Generics.Collections,
  Winapi.Windows,
  Winapi.WinSock2;

type
  TTestResultEvent = procedure(const AJSONData: string) of object;
  TGetSelectedTestsEvent = function: string of object;

  { Lightweight Winsock TCP Server running in background to receive test results }
  TTestRunnerServerThread = class(TThread)
  private
    FPort: Word;
    FSocket: TSocket;
    FOnTestResult: TTestResultEvent;
    FOnGetSelectedTests: TGetSelectedTestsEvent;
    FClientSockets: TList<TSocket>;
    FLock: TCriticalSection;
    FFinished: Boolean;
    FPendingJson: TStringList;
    FFlushQueued: Boolean;
    procedure TriggerTestResult(const AData: string);
    procedure QueueResult(const AJSON: string);
    procedure DrainPendingToUi;
  protected
    procedure Execute; override;
  public
    constructor Create(APort: Word; AOnTestResult: TTestResultEvent; AOnGetSelectedTests: TGetSelectedTestsEvent);
    destructor Destroy; override;
    procedure CloseAllClientSockets;
    property Finished: Boolean read FFinished;
  end;

  TTestRunnerServer = class
  private
    FThread: TTestRunnerServerThread;
    FPort: Word;
    FOnTestResult: TTestResultEvent;
    FSelectedTestsJSON: string;
    function HandleGetSelectedTests: string;
    function GetPort: Word;
  public
    constructor Create(APort: Word = 8102);
    destructor Destroy; override;
    procedure Start(AOnTestResult: TTestResultEvent);
    procedure Stop;
    property Port: Word read GetPort;
    property SelectedTestsJSON: string read FSelectedTestsJSON write FSelectedTestsJSON;
  end;

/// <summary>
///   Call before unloading the Design package / freeing the Explorer form.
///   Sets a flag so queued UI callbacks exit without touching freed code.
///   Does not call RemoveQueuedEvents(nil) — that can hard-kill the IDE mid-build.
/// </summary>
procedure BeginTestingDesignShutdown;
function IsTestingDesignShuttingDown: Boolean;

{ Master switch — when False, Expert must not touch IDE open/save/compile/notifiers. }
type
  TDextEnabledChangedProc = procedure(AEnabled: Boolean);

function IsDextTestExplorerEnabled: Boolean;
procedure SetDextTestExplorerEnabled(AValue: Boolean);
procedure LoadDextTestExplorerEnabledFromIni;
procedure SetDextEnabledChangedHook(AHook: TDextEnabledChangedProc);

implementation

uses
  System.IOUtils,
  System.IniFiles;

var
  LServerLogLock: TObject = nil;
  GTestingDesignShuttingDown: Boolean = False;
  GDextTestExplorerEnabled: Boolean = True;
  GDextEnabledChangedHook: TDextEnabledChangedProc = nil;

procedure BeginTestingDesignShutdown;
begin
  // Flag only. Do NOT call TThread.RemoveQueuedEvents(nil): that clears the IDE's
  // entire main-thread queue and can hard-kill bds.exe mid-build with no dialog.
  // Queued Dext callbacks must bail via IsTestingDesignShuttingDown / FormDextTestRunner checks.
  GTestingDesignShuttingDown := True;
end;

function IsTestingDesignShuttingDown: Boolean;
begin
  Result := GTestingDesignShuttingDown;
end;

function IsDextTestExplorerEnabled: Boolean;
begin
  Result := GDextTestExplorerEnabled and not GTestingDesignShuttingDown;
end;

procedure SetDextEnabledChangedHook(AHook: TDextEnabledChangedProc);
begin
  GDextEnabledChangedHook := AHook;
end;

procedure SetDextTestExplorerEnabled(AValue: Boolean);
begin
  if GDextTestExplorerEnabled = AValue then
    Exit;
  GDextTestExplorerEnabled := AValue;
  if Assigned(GDextEnabledChangedHook) then
  try
    GDextEnabledChangedHook(AValue);
  except
  end;
end;

procedure LoadDextTestExplorerEnabledFromIni;
var
  Ini: TMemIniFile;
  Path: string;
begin
  GDextTestExplorerEnabled := True;
  try
    Path := TPath.Combine(TPath.GetHomePath, 'DextTestExplorer.ini');
    if not TFile.Exists(Path) then
      Exit;
    Ini := TMemIniFile.Create(Path);
    try
      GDextTestExplorerEnabled := Ini.ReadBool('General', 'Enabled', True);
    finally
      Ini.Free;
    end;
  except
    GDextTestExplorerEnabled := True;
  end;
end;

procedure LogServerDebug(const AMsg: string);
var
  LPath: string;
  LWriter: TStreamWriter;
begin
  Winapi.Windows.OutputDebugString(PChar('[Dext.Server] ' + AMsg));
  if LServerLogLock = nil then Exit;
  System.TMonitor.Enter(LServerLogLock);
  try
    try
      LPath := TPath.Combine(TPath.GetTempPath, 'DextExpert.log');
      LWriter := TFile.AppendText(LPath);
      try
        LWriter.WriteLine(Format('[%s] [Server] %s', [FormatDateTime('yyyy-MM-dd hh:nn:ss.zzz', Now), AMsg]));
      finally
        LWriter.Free;
      end;
    except
    end;
  finally
    System.TMonitor.Exit(LServerLogLock);
  end;
end;

{ TTestRunnerServerThread }

constructor TTestRunnerServerThread.Create(APort: Word; AOnTestResult: TTestResultEvent; AOnGetSelectedTests: TGetSelectedTestsEvent);
begin
  inherited Create(True);
  FPort := APort;
  FOnTestResult := AOnTestResult;
  FOnGetSelectedTests := AOnGetSelectedTests;
  FSocket := INVALID_SOCKET;
  FClientSockets := TList<TSocket>.Create;
  FLock := TCriticalSection.Create;
  FPendingJson := TStringList.Create;
  FFlushQueued := False;
  FFinished := False;
  FreeOnTerminate := False;
end;

destructor TTestRunnerServerThread.Destroy;
begin
  CloseAllClientSockets;
  if FSocket <> INVALID_SOCKET then
  begin
    closesocket(FSocket);
  end;
  FClientSockets.Free;
  FPendingJson.Free;
  FLock.Free;
  inherited;
end;

procedure TTestRunnerServerThread.CloseAllClientSockets;
var
  LSock: TSocket;
begin
  FLock.Enter;
  try
    for LSock in FClientSockets do
    begin
      closesocket(LSock);
    end;
    FClientSockets.Clear;
  finally
    FLock.Leave;
  end;
end;

procedure TTestRunnerServerThread.TriggerTestResult(const AData: string);
begin
  if IsTestingDesignShuttingDown or Terminated then
    Exit;
  if Assigned(FOnTestResult) then
    FOnTestResult(AData);
end;

procedure TTestRunnerServerThread.DrainPendingToUi;
var
  Batch: TStringList;
  i: Integer;
begin
  if IsTestingDesignShuttingDown or Terminated then
  begin
    FLock.Enter;
    try
      FPendingJson.Clear;
      FFlushQueued := False;
    finally
      FLock.Leave;
    end;
    Exit;
  end;

  Batch := TStringList.Create;
  try
    FLock.Enter;
    try
      Batch.Assign(FPendingJson);
      FPendingJson.Clear;
      FFlushQueued := False;
    finally
      FLock.Leave;
    end;
    // One UI turn delivers the whole burst; the form time-slices painting.
    for i := 0 to Batch.Count - 1 do
      TriggerTestResult(Batch[i]);
  finally
    Batch.Free;
  end;
end;

procedure TTestRunnerServerThread.QueueResult(const AJSON: string);
var
  ShouldQueue: Boolean;
begin
  if IsTestingDesignShuttingDown or Terminated then
    Exit;

  // Coalesce: avoid posting one TThread.Queue message per test (starves the IDE).
  FLock.Enter;
  try
    FPendingJson.Add(AJSON);
    ShouldQueue := not FFlushQueued;
    if ShouldQueue then
      FFlushQueued := True;
  finally
    FLock.Leave;
  end;
  if ShouldQueue then
    TThread.Queue(nil, TThreadProcedure(procedure
      begin
        if not IsTestingDesignShuttingDown then
          DrainPendingToUi;
      end));
end;

procedure TTestRunnerServerThread.Execute;
var
  WSAData: TWSAData;
  Addr: TSockAddrIn;
  ClientSock: TSocket;
  Buffer: array[0..8191] of AnsiChar;
  BytesReceived: Integer;
  RequestStr: string;
  ContentLength: Integer;
  BodyPos: Integer;
  JSONBody: string;
  HeaderPos: Integer;
  LenStr: string;
  ResponseStr: string;
  AddrLen: Integer;
  CountPos: Integer;
  CountStr: string;
  idx: Integer;
  Count: Integer;
begin
  LogServerDebug('Execute started. Port: ' + FPort.ToString);
  if WSAStartup(MakeWord(2, 2), WSAData) <> 0 then
  begin
    LogServerDebug('WSAStartup failed');
    Exit;
  end;

  try
    FSocket := socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    if FSocket = INVALID_SOCKET then
    begin
      LogServerDebug('Socket creation failed');
      Exit;
    end;

    Addr.sin_family := AF_INET;
    Addr.sin_port := htons(FPort);
    Addr.sin_addr.S_addr := INADDR_ANY;

    if bind(FSocket, PSockAddr(@Addr)^, SizeOf(Addr)) = SOCKET_ERROR then
    begin
      LogServerDebug('Bind failed on port ' + FPort.ToString + '. Error: ' + WSAGetLastError.ToString + '. Trying port 0 (dynamic)...');
      Addr.sin_port := htons(0);
      if bind(FSocket, PSockAddr(@Addr)^, SizeOf(Addr)) = SOCKET_ERROR then
      begin
        LogServerDebug('Bind failed on port 0. Error: ' + WSAGetLastError.ToString);
        Exit;
      end;
    end;

    // Retrieve the actual bound port
    AddrLen := SizeOf(Addr);
    if getsockname(FSocket, PSockAddr(@Addr)^, AddrLen) = 0 then
    begin
      FPort := ntohs(Addr.sin_port);
      LogServerDebug('Successfully bound to port: ' + FPort.ToString);
    end
    else
    begin
      LogServerDebug('getsockname failed. Error: ' + WSAGetLastError.ToString);
    end;

    if listen(FSocket, SOMAXCONN) = SOCKET_ERROR then
    begin
      LogServerDebug('Listen failed. Error: ' + WSAGetLastError.ToString);
      Exit;
    end;

    LogServerDebug('Server successfully listening on port ' + FPort.ToString);

    while not Terminated do
    begin
      ClientSock := accept(FSocket, nil, nil);
      if ClientSock = INVALID_SOCKET then
      begin
        if Terminated then Break;
        LogServerDebug('Accept failed or socket closed');
        Continue;
      end;

      FLock.Enter;
      try
        if not Terminated then
          FClientSockets.Add(ClientSock)
        else
        begin
          closesocket(ClientSock);
          Continue;
        end;
      finally
        FLock.Leave;
      end;

      LogServerDebug('Connection accepted');

      // Read HTTP Request
      RequestStr := '';
      repeat
        BytesReceived := recv(ClientSock, Buffer[0], SizeOf(Buffer) - 1, 0);
        if BytesReceived <= 0 then Break;
        Buffer[BytesReceived] := #0;
        RequestStr := RequestStr + string(AnsiString(Buffer));
      until (BytesReceived < SizeOf(Buffer) - 1) or (Pos(#13#10#13#10, RequestStr) > 0);

      LogServerDebug('Request header read. Bytes: ' + Length(RequestStr).ToString);

      // Simple HTTP POST and GET parser
      if RequestStr.StartsWith('POST') then
      begin
        BodyPos := Pos(#13#10#13#10, RequestStr);
        if BodyPos > 0 then
        begin
          ContentLength := 0;
          HeaderPos := Pos('content-length:', LowerCase(RequestStr));
          if HeaderPos > 0 then
          begin
            LenStr := Copy(RequestStr, HeaderPos + 15, 20);
            HeaderPos := Pos(#13#10, LenStr);
            if HeaderPos > 0 then
              LenStr := Copy(LenStr, 1, HeaderPos - 1);
            ContentLength := StrToIntDef(Trim(LenStr), 0);
          end;

          JSONBody := Copy(RequestStr, BodyPos + 4, Length(RequestStr));
          LogServerDebug('POST detected. BodyPos: ' + BodyPos.ToString + ', parsed Content-Length: ' + ContentLength.ToString + ', current JSONBody length: ' + Length(JSONBody).ToString);
          
          // If we haven't read the full body yet, read the remaining
          while (Length(JSONBody) < ContentLength) and not Terminated do
          begin
            BytesReceived := recv(ClientSock, Buffer[0], SizeOf(Buffer) - 1, 0);
            if BytesReceived <= 0 then Break;
            Buffer[BytesReceived] := #0;
            JSONBody := JSONBody + string(AnsiString(Buffer));
          end;

          LogServerDebug('JSONBody complete: ' + JSONBody);
 
          if JSONBody = '' then
          begin
            if (Pos('/startrun', RequestStr) > 0) or (Pos('/start', RequestStr) > 0) then
            begin
              CountPos := Pos('count=', RequestStr);
              if CountPos > 0 then
              begin
                CountStr := '';
                idx := CountPos + 6;
                while (idx <= Length(RequestStr)) and CharInSet(RequestStr[idx], ['0'..'9']) do
                begin
                  CountStr := CountStr + RequestStr[idx];
                  Inc(idx);
                end;
                Count := StrToIntDef(CountStr, 0);
                if Count > 0 then
                  JSONBody := '{"event":"RunStart","totalTests":' + Count.ToString + '}';
              end;
            end
            else if (Pos('/finishedrun', RequestStr) > 0) or (Pos('/finished', RequestStr) > 0) then
            begin
              JSONBody := '{"event":"RunComplete","passed":0,"failed":0,"ignored":0}';
            end;
          end;

          // Dispatch result to Main UI Thread
          if JSONBody <> '' then
          begin
            LogServerDebug('Queueing TriggerTestResult to main thread');
            QueueResult(JSONBody);
          end;
        end;

        // Send 200 OK Response
        ResponseStr := 'HTTP/1.1 200 OK'#13#10 +
                       'Content-Type: application/json'#13#10 +
                       'Content-Length: 15'#13#10 +
                       'Connection: close'#13#10#13#10 +
                       '{"status":"ok"}';
        send(ClientSock, PAnsiChar(AnsiString(ResponseStr))[0], Length(ResponseStr), 0);
      end
      else if RequestStr.StartsWith('GET') then
      begin
        LogServerDebug('GET detected: ' + RequestStr);
        if Pos('/options', RequestStr) > 0 then
        begin
          ResponseStr := 'HTTP/1.1 200 OK'#13#10 +
                        'Content-Type: application/json'#13#10 +
                        'Connection: close'#13#10#13#10 +
                        '{"ExecuteTests":true,"ShowProgress":true}';
          send(ClientSock, PAnsiChar(AnsiString(ResponseStr))[0], Length(ResponseStr), 0);
        end
        else if Pos('/tests', RequestStr) > 0 then
        begin
          JSONBody := '[]';
          if Assigned(FOnGetSelectedTests) then
            JSONBody := FOnGetSelectedTests();

          JSONBody := '{"SelectedTests":' + JSONBody + '}';

          ResponseStr := 'HTTP/1.1 200 OK'#13#10 +
                        'Content-Type: application/json'#13#10 +
                        'Connection: close'#13#10#13#10 +
                        JSONBody;
          send(ClientSock, PAnsiChar(AnsiString(ResponseStr))[0], Length(ResponseStr), 0);
        end
        else
        begin
          ResponseStr := 'HTTP/1.1 404 Not Found'#13#10 +
                        'Content-Length: 0'#13#10 +
                        'Connection: close'#13#10#13#10;
          send(ClientSock, PAnsiChar(AnsiString(ResponseStr))[0], Length(ResponseStr), 0);
        end;
      end;

      closesocket(ClientSock);
      FLock.Enter;
      try
        FClientSockets.Remove(ClientSock);
      finally
        FLock.Leave;
      end;
    end;

  finally
    LogServerDebug('Execute finished. Closing listening socket.');
    if FSocket <> INVALID_SOCKET then
      closesocket(FSocket);
    WSACleanup;
    FFinished := True;
  end;
end;

{ TTestRunnerServer }

constructor TTestRunnerServer.Create(APort: Word);
begin
  FPort := APort;
  FThread := nil;
  FSelectedTestsJSON := '[]';
end;

destructor TTestRunnerServer.Destroy;
begin
  Stop;
  inherited;
end;

function TTestRunnerServer.HandleGetSelectedTests: string;
begin
  Result := FSelectedTestsJSON;
end;

function TTestRunnerServer.GetPort: Word;
begin
  if Assigned(FThread) then
    Result := FThread.FPort
  else
    Result := FPort;
end;

procedure TTestRunnerServer.Start(AOnTestResult: TTestResultEvent);
begin
  Stop;
  FOnTestResult := AOnTestResult;
  FThread := TTestRunnerServerThread.Create(FPort, FOnTestResult, HandleGetSelectedTests);
  FThread.Start;
end;

procedure TTestRunnerServer.Stop;
var
  LStart: DWORD;
begin
  FOnTestResult := nil;
  if Assigned(FThread) then
  begin
    FThread.FOnTestResult := nil;
    FThread.FOnGetSelectedTests := nil;
    FThread.Terminate;
    FThread.CloseAllClientSockets;
    // Close listening socket to unblock accept()
    if FThread.FSocket <> INVALID_SOCKET then
      closesocket(FThread.FSocket);

    // Prefer a clean exit: a live server thread after BPL unload = hard IDE death.
    LStart := GetTickCount;
    while not FThread.Finished and (GetTickCount - LStart < 2000) do
      Sleep(20);

    if not FThread.Finished then
      TerminateThread(FThread.Handle, 0);

    FreeAndNil(FThread);
  end;
end;

initialization
  LServerLogLock := TObject.Create;

finalization
  FreeAndNil(LServerLogLock);

end.
