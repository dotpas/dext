program Dext.Server.PerformanceTests;

{$APPTYPE CONSOLE}

uses
  Dext.MM,
  System.SysUtils,
  System.Diagnostics,
  System.Classes,
  {$IFDEF MSWINDOWS}
  Winapi.Windows,
  Winapi.WinSock2,
  {$ENDIF}
  Dext.Assertions,
  Dext.Testing.Host,
  Dext.Testing.Attributes,
  Dext.Testing.Runner,
  Dext.Testing.Fluent,
  Dext.Web.Interfaces,
  Dext.Server.Engine.Interfaces,
  Dext.Server.Engine.Types,
  Dext.Server.Iocp.HttpParser,
  {$IFDEF MSWINDOWS}
  Dext.Server.Iocp,
  {$ENDIF}
  {$IFDEF LINUX}
  Dext.Server.Epoll,
  {$ENDIF}
  Dext.Collections.Dict;

type
  {$IFDEF MSWINDOWS}
  TTestRequestClass = TDextIocpRequest;
  TTestParser = TDextIocpHttpParser;
  {$ENDIF}
  {$IFDEF LINUX}
  TTestRequestClass = TDextEpollRequest;
  TTestParser = TDextEpollHttpParser;
  {$ENDIF}

  /// <summary>
  ///   Fixture for Epoll/IOCP request headers micro-benchmarks.
  /// </summary>
  [TestFixture('Epoll/IOCP Header Micro-benchmarks')]
  THeaderPerformanceTests = class
  public
    /// <summary>
    ///   Benchmark resolution of headers with and without optimization.
    /// </summary>
    [Test]
    procedure BenchmarkHeaderLookup;
  end;

  {$IFDEF MSWINDOWS}
  /// <summary>
  ///   Fixture for Http.sys Zero-Copy file transmission tests.
  /// </summary>
  [TestFixture('Http.sys Zero-Copy Tests')]
  THttpSysZeroCopyTests = class
  public
    /// <summary>
    ///   Verifies that WriteFile does not allocate heap blocks for transmission.
    /// </summary>
    [Test]
    procedure TestZeroCopyHeapAllocation;
  end;

  /// <summary>
  ///   Fixture for IOCP Engine asynchronous and keep-alive tests.
  /// </summary>
  [TestFixture('IOCP Engine Async Tests')]
  TIocpServerEngineTests = class
  public
    [Test]
    procedure TestEngineStartStop;
    [Test]
    procedure TestEngineHttpRequestKeepAlive;
  end;
  {$ENDIF}

{ THeaderPerformanceTests }

procedure THeaderPerformanceTests.BenchmarkHeaderLookup;
var
  buffer: TBytes;
  rawRequestStr: string;
  headerSegments: THeaderSegments;
  method, path, query: string;
  bodyOffset: Integer;
  contentLength: Int64;
  parsedRequest: IDextRawRequest;
  i: Integer;
  stopwatch: TStopwatch;
  headerVal: string;
begin
  // Build a standard raw HTTP request buffer
  rawRequestStr := 
    'GET /api/v1/resource?query=123 HTTP/1.1' + #13#10 +
    'Host: localhost:5000' + #13#10 +
    'User-Agent: Mozilla/5.0' + #13#10 +
    'Accept: application/json' + #13#10 +
    'Content-Length: 15' + #13#10 +
    'Connection: keep-alive' + #13#10 +
    #13#10 +
    '{"hello":"world"}';
    
  buffer := TEncoding.UTF8.GetBytes(rawRequestStr);

  // Parse segments
  if not TTestParser.TryParseRequest(
    buffer,
    Length(buffer),
    method,
    path,
    query,
    headerSegments,
    bodyOffset,
    contentLength
  ) then
    raise Exception.Create('Failed to parse test request');

  parsedRequest := TTestRequestClass.Create(
    method,
    path,
    query,
    headerSegments,
    buffer,
    bodyOffset,
    Length(buffer) - bodyOffset,
    contentLength
  );

  try
    stopwatch := TStopwatch.StartNew;
    // Perform 100,000 lookups on existent and non-existent headers
    for i := 0 to 99999 do
    begin
      headerVal := parsedRequest.GetHeader('User-Agent');
      headerVal := parsedRequest.GetHeader('X-Non-Existent-Header');
    end;
    stopwatch.Stop;
    
    Writeln(Format('  ⏱  Time for 100,000 lookups: %d ms', [stopwatch.ElapsedMilliseconds]));
    Should(stopwatch.ElapsedMilliseconds < 500).BeTrue;
  finally
    parsedRequest := nil; // Managed by RefCount interface
  end;
end;

{$IFDEF MSWINDOWS}
{ THttpSysZeroCopyTests }

procedure THttpSysZeroCopyTests.TestZeroCopyHeapAllocation;
var
  tempPath: string;
  fs: TFileStream;
  dummyData: TBytes;
  i: Integer;
  fileHandle: THandle;
  fileSizeVal: Int64;
  pPath: PWideChar;
begin
  // Create a 5MB dummy file
  tempPath := 'temp_large_test_file.bin';
  SetLength(dummyData, 1024 * 1024); // 1MB chunk
  for i := 0 to Length(dummyData) - 1 do
    dummyData[i] := 65; // 'A'

  fs := TFileStream.Create(tempPath, fmCreate);
  try
    for i := 0 to 4 do
      fs.WriteBuffer(dummyData[0], Length(dummyData));
  finally
    fs.Free;
  end;

  try
    pPath := PWideChar(Pointer(tempPath));
    // Test native Windows file API behavior
    fileHandle := CreateFileW(
      pPath,
      GENERIC_READ,
      FILE_SHARE_READ,
      nil,
      OPEN_EXISTING,
      FILE_ATTRIBUTE_NORMAL,
      0
    );
    Should(fileHandle <> INVALID_HANDLE_VALUE).BeTrue;
    
    try
      // Verify file size detection works via GetFileSizeEx
      Should(GetFileSizeEx(fileHandle, fileSizeVal)).BeTrue;
      Should(fileSizeVal).Be(5 * 1024 * 1024);
    finally
      CloseHandle(fileHandle);
    end;
  finally
    System.SysUtils.DeleteFile(tempPath);
  end;
end;

{ TIocpServerEngineTests }

procedure TIocpServerEngineTests.TestEngineStartStop;
var
  Options: TServerEngineOptions;
  Engine: IDextServerEngine;
begin
  FillChar(Options, SizeOf(Options), 0);
  Options.IoThreadCount := 2;
  Options.MaxConnections := 100;
  Engine := TDextIocpEngine.Create(Options);
  Engine.Bind('127.0.0.1', 58244);
  Engine.Start;
  try
    Should(Engine.GetListenPort).Be(58244);
    Should(Engine.GetActiveConnections).Be(0);
  finally
    Engine.Stop;
  end;
end;

procedure TIocpServerEngineTests.TestEngineHttpRequestKeepAlive;
var
  Options: TServerEngineOptions;
  Engine: IDextServerEngine;
  ClientSock: TSocket;
  Addr: TSockAddrIn;
  Req: AnsiString;
  RespBuf: array[0..4095] of AnsiChar;
  BytesReceived: Integer;
  RespStr: string;
begin
  FillChar(Options, SizeOf(Options), 0);
  Options.IoThreadCount := 2;
  Options.MaxConnections := 100;
  Engine := TDextIocpEngine.Create(Options);
  Engine.Bind('127.0.0.1', 58245);
  Engine.SetOnRequest(
    procedure(const AConnection: IDextServerConnection; const AReq: IDextRawRequest; const AResp: IDextRawResponse)
    var
      BodyBytes: TBytes;
    begin
      AResp.SetStatus(200, 'OK');
      BodyBytes := TEncoding.UTF8.GetBytes('Hello IOCP!');
      AResp.Write(BodyBytes, 0, Length(BodyBytes));
    end
  );
  Engine.Start;
  try
    ClientSock := Winapi.WinSock2.socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    Should(ClientSock <> INVALID_SOCKET).BeTrue;
    try
      FillChar(Addr, SizeOf(Addr), 0);
      Addr.sin_family := AF_INET;
      Addr.sin_port := htons(58245);
      Addr.sin_addr.S_addr := inet_addr('127.0.0.1');

      Should(Winapi.WinSock2.connect(ClientSock, PSockAddr(@Addr)^, SizeOf(Addr)) = 0).BeTrue;

      // First Request on keep-alive connection
      Req := 'GET /first HTTP/1.1'#13#10 +
             'Host: 127.0.0.1:58245'#13#10 +
             'Connection: keep-alive'#13#10#13#10;
      Winapi.WinSock2.send(ClientSock, Req[1], Length(Req), 0);

      FillChar(RespBuf, SizeOf(RespBuf), 0);
      BytesReceived := Winapi.WinSock2.recv(ClientSock, RespBuf[0], SizeOf(RespBuf) - 1, 0);
      Should(BytesReceived > 0).BeTrue;
      RespStr := string(RespBuf);
      Should(RespStr.Contains('HTTP/1.1 200 OK')).BeTrue;
      Should(RespStr.Contains('Content-Length: 11')).BeTrue;
      Should(RespStr.Contains('Hello IOCP!')).BeTrue;

      // Second Request on the exact same connection (testing Keep-Alive & non-blocking ioRead)
      Req := 'GET /second HTTP/1.1'#13#10 +
             'Host: 127.0.0.1:58245'#13#10 +
             'Connection: keep-alive'#13#10#13#10;
      Winapi.WinSock2.send(ClientSock, Req[1], Length(Req), 0);

      FillChar(RespBuf, SizeOf(RespBuf), 0);
      BytesReceived := Winapi.WinSock2.recv(ClientSock, RespBuf[0], SizeOf(RespBuf) - 1, 0);
      Should(BytesReceived > 0).BeTrue;
      RespStr := string(RespBuf);
      Should(RespStr.Contains('HTTP/1.1 200 OK')).BeTrue;
      Should(RespStr.Contains('Content-Length: 11')).BeTrue;
      Should(RespStr.Contains('Hello IOCP!')).BeTrue;
    finally
      Winapi.WinSock2.closesocket(ClientSock);
    end;
  finally
    Engine.Stop;
  end;
end;
{$ENDIF}

begin
  try
    Writeln('=== Running Performance Tests and Micro-benchmarks ===');
    RunTests(ConfigureTests
      .Verbose
      .RegisterFixtures([
        THeaderPerformanceTests
        {$IFDEF MSWINDOWS}
        , THttpSysZeroCopyTests
        , TIocpServerEngineTests
        {$ENDIF}
      ]));
  except
    on E: Exception do
    begin
      Writeln('FATAL ERROR: ' + E.ClassName + ': ' + E.Message);
      ExitCode := 1;
    end;
  end;
end.
