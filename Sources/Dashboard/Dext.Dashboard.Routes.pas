unit Dext.Dashboard.Routes;

interface

uses
  System.SysUtils,
  Dext.Collections,
  Dext.Collections.Dict,
  System.Classes,
  System.IOUtils,
  System.DateUtils,
  Dext.Json,
  Dext.Json.Types,
  System.Types,
  Dext.DI.Interfaces,
  Dext.Dashboard.TestScanner,
  Dext.Dashboard.TestRunner,
  Dext.Dashboard.Security,
{$IFDEF MSWINDOWS}
  Winapi.Windows,
{$ENDIF}
  Dext.DI.Core,
  Dext.Web.Interfaces,
  Dext.Web.Routing,
  Dext.Web.Results,
  Dext.Web.StaticFiles,
  Dext.Web.Hubs.Interfaces,
  Dext.Web.Hubs.Extensions,
  // Note: These dependencies suggest the dashboard logic is tightly coupled with CLI infrastructure for now.
  // Ideally these should be moved to a shared Dext.Dashboard namespace in the future.
  Dext.Hosting.CLI.Hubs.Dashboard,
  Dext.Hosting.CLI.Registry,
  Dext.Hosting.CLI.Config,
  Dext.Hosting.CLI.Tools.CodeCoverage,
  Dext.Http.Parser,
  Dext.Http.Executor,
  Dext.Http.Request;

type
  /// <summary>
  ///   Background thread that periodically flushes telemetry/metrics to disk.
  ///   Runs every 30 seconds so file I/O never blocks HTTP handler threads.
  /// </summary>
  TDashboardSaveTimer = class(TThread)
  private
    FIntervalMs: Integer;
  protected
    procedure Execute; override;
  public
    constructor Create(IntervalMs: Integer = 30000);
  end;

type
  /// <summary>
  ///   Configures routes and endpoints for the Dext Dashboard.
  /// </summary>
  TDashboardRoutes = class
  public
    class procedure Configure(App: IApplicationBuilder);
    class procedure BroadcastSSE(const EventName, Data: string);
    class procedure StopServer;
  end;

  /// <summary>
  ///   Represents a recorded item in the HTTP client execution history.
  /// </summary>
  THttpHistoryItem = class
  public
    Id: string;
    Method: string;
    Url: string;
    StatusCode: Integer;
    DurationMs: Int64;
    Timestamp: TDateTime;
    Content: string; // The .http content used
  end;

var
  FHttpHistory: IList<THttpHistoryItem>;

implementation

uses
  System.Rtti,
  IdContext,     // Access to TIdContext
  IdGlobal,      // Access to ToBytes/IndyTextEncoding_UTF8
  Dext.Sidecar.TestCompat,
  Dext.Utils,
  Dext.Web.Indy; // Access to TDextIndyHttpContext

var
  FSSEClients: IList<IHttpContext>;
  FLock: TObject;
  FTraceHistory: IList<string>;
  FMetricsHistory: IList<string>;
  FSaveTimer: TDashboardSaveTimer;
  FServerStopping: Boolean;

procedure BroadcastSSE(const EventName, Data: string); forward;
procedure LoadTelemetryHistory; forward;
procedure SaveTelemetryHistory; forward;
procedure LoadMetricsHistory; forward;
procedure SaveMetricsHistory; forward;

{$R 'Dext.Dashboard.res'}

{ TDashboardSaveTimer }

constructor TDashboardSaveTimer.Create(IntervalMs: Integer);
begin
  inherited Create(False); // Start immediately
  FIntervalMs := IntervalMs;
  FreeOnTerminate := False;
end;

procedure TDashboardSaveTimer.Execute;
var
  Elapsed: Integer;
begin
  while not Terminated do
  begin
    // Wait in small chunks so Terminate is checked quickly
    Elapsed := 0;
    while not Terminated and (Elapsed < FIntervalMs) do
    begin
      Sleep(500);
      Inc(Elapsed, 500);
    end;
    if not Terminated then
    begin
      SaveTelemetryHistory;
      SaveMetricsHistory;
    end;
  end;
end;

{ TDashboardRoutes }

class procedure TDashboardRoutes.BroadcastSSE(const EventName, Data: string);
begin
  Dext.Dashboard.Routes.BroadcastSSE(EventName, Data);
end;

class procedure TDashboardRoutes.StopServer;
begin
  FServerStopping := True;
end;

class procedure TDashboardRoutes.Configure(App: IApplicationBuilder);
begin
  // First: Host, JSON body and token checks (Dext.Dashboard.Security). The
  // API can read and list files and start executables, so only the dashboard
  // page may call it, not another page open in the browser.
  UseDashboardSecurity(App);

  // Map SignalR/WebSocket Hub
  THubExtensions.MapHub(App, '/hubs/dashboard', TDashboardHub);

  // Serve embedded dashboard HTML/CSS/JS
  App.Use(procedure(Ctx: IHttpContext; Next: TRequestDelegate)
    var
      Path, ResName, CT: string;
      RS: TResourceStream;
    begin
      Path := Ctx.Request.Path;
      ResName := '';
      CT := '';

      if (Path = '/') or (Path = '/index.html') then
      begin
        ResName := 'MAIN_HTML';
        CT := 'text/html; charset=utf-8';
      end
      else if Path = '/main.css' then
      begin
        ResName := 'MAIN_CSS';
        CT := 'text/css; charset=utf-8';
      end
      else if Path = '/main.js' then
      begin
        ResName := 'MAIN_JS';
        CT := 'text/javascript; charset=utf-8';
      end
      else if Path = '/i18n.js' then
      begin
        ResName := 'I18N_JS';
        CT := 'text/javascript; charset=utf-8';
      end;

      if ResName <> '' then
      begin
        Ctx.Response.SetContentType(CT);
        // The page gets the token that its API calls carry back.
        if ResName = 'MAIN_HTML' then
          SetDashboardCookie(Ctx.Response);
        RS := TResourceStream.Create(HInstance, ResName, RT_RCDATA);
        try
          Ctx.Response.SetContentLength(RS.Size);
          Ctx.Response.Write(RS);
        finally
          RS.Free;
        end;
        Exit;
      end;
      
      Next(Ctx);
    end);

  // Serve Test Reports
  App.Use(procedure(Ctx: IHttpContext; Next: TRequestDelegate)
    var
      Path, ReportPath, FilePath, CT: string;
      CP: TContentTypeProvider;
      FS: TFileStream;
    begin
      Path := Ctx.Request.Path;
      if Path.StartsWith('/reports/', True) or (Path = '/reports') then
      begin
         if Path = '/reports' then 
         begin
           Ctx.Response.StatusCode := 302;
           Ctx.Response.AddHeader('Location', '/reports/CodeCoverage_Summary.html');
           Exit;
         end;
         
         ReportPath := TPath.GetFullPath('TestOutput\report');
         if TDirectory.Exists(ReportPath) then
         begin
             // Resolved and kept inside the report folder: '..' in the URL
             // must not reach other files.
             FilePath := TPath.GetFullPath(TPath.Combine(ReportPath, Path.Substring(9)));

             if FilePath.StartsWith(IncludeTrailingPathDelimiter(ReportPath), True) and
                FileExists(FilePath) then
             begin
                 CP := TContentTypeProvider.Create;
                 try
                    if not CP.TryGetContentType(FilePath, CT) then CT := 'application/octet-stream';
                 finally
                    CP.Free;
                 end;
                 
                 Ctx.Response.SetContentType(CT);
                 FS := TFileStream.Create(FilePath, fmOpenRead or fmShareDenyWrite);
                 try
                    Ctx.Response.SetContentLength(FS.Size);
                    Ctx.Response.Write(FS);
                 finally
                    FS.Free;
                 end;
                 Exit;
             end;
         end;
      end;
      
      Next(Ctx);
    end);

  // API: Health Check for Discovery
  App.MapGet('/health',
    procedure(Ctx: IHttpContext)
    begin
      Results.Ok('{"status":"Healthy"}').Execute(Ctx);
    end);

  // API: Force flush telemetry to disk (for testing / on-demand persistence)
  App.MapPost('/api/telemetry/flush',
    procedure(Ctx: IHttpContext)
    begin
      // User-initiated flush: acceptable to block briefly here
      SaveTelemetryHistory;
      SaveMetricsHistory;
      Results.Ok('{"status":"flushed"}').Execute(Ctx);
    end);

  // API: Test Summary
  App.MapGet('/api/test/summary',
    procedure(Ctx: IHttpContext)
    var
      ReportDir, SummaryFile: string;
      Res: IResult;
      Content: string;
      P1, P2: Integer;
      Coverage: string;
    begin
       ReportDir := TPath.GetFullPath('TestOutput\report');
       SummaryFile := TPath.Combine(ReportDir, 'CodeCoverage_Summary.xml');
       
       if FileExists(SummaryFile) then
       begin
          Content := TFile.ReadAllText(SummaryFile);
          P1 := Content.IndexOf('percent="');
          if P1 > 0 then
          begin
             Inc(P1, 9);
             P2 := Content.IndexOf('"', P1);
             if P2 > P1 then
             begin
                Coverage := Content.Substring(P1, P2 - P1);
                Res := Results.Ok('{"available": true, "coverage": ' + Coverage.Replace(',', '.') + '}');
                Res.Execute(Ctx);
                Exit;
             end;
          end;
       end;
       
       Res := Results.Ok('{"available": false}');
       Res.Execute(Ctx);
    end);

  // API: Detailed Code Coverage XML/HTML Lines Parser
  App.MapGet('/api/tests/coverage-detail',
    procedure(Ctx: IHttpContext)
    var
      ReportDir, SummaryFile: string;
      XMLContent: string;
      JObj: IDextJsonObject;
    begin
       ReportDir := TPath.GetFullPath('TestOutput\report');
       SummaryFile := TPath.Combine(ReportDir, 'CodeCoverage_Summary.xml');
       
       if FileExists(SummaryFile) then
       begin
          XMLContent := TFile.ReadAllText(SummaryFile, TEncoding.UTF8);
          // Return raw summary to allow javascript parser to extract lines and units
          JObj := TDextJson.Provider.CreateObject;
          JObj.SetString('available', 'true');
          JObj.SetString('xml', XMLContent);
          Results.Json(JObj.ToJson).Execute(Ctx);
          Exit;
       end;
       
       Results.Ok('{"available": false}').Execute(Ctx);
    end);
    
  // API: HTTP Client - History
  App.MapGet('/api/http/history',
    procedure(Ctx: IHttpContext)
    var
      Res: IResult;
      Arr: IDextJsonArray;
      Item: THttpHistoryItem;
      Obj: IDextJsonObject;
    begin
      if FHttpHistory = nil then
      begin
        Res := Results.Ok('[]');
        Res.Execute(Ctx);
        Exit;
      end;

      Arr := TDextJson.Provider.CreateArray;
      TMonitor.Enter(TObject(FHttpHistory));
      try
        for Item in FHttpHistory do
        begin
          Obj := TDextJson.Provider.CreateObject;
          Obj.SetString('id', Item.Id);
          Obj.SetString('method', Item.Method);
          Obj.SetString('url', Item.Url);
          Obj.SetInteger('statusCode', Item.StatusCode);
          Obj.SetInt64('durationMs', Item.DurationMs);
          Obj.SetString('timestamp', DateToISO8601(Item.Timestamp, False));
          // Don't send full content to list to save bandwidth, maybe logic to fetch detail later?
          // For now send it, text is small.
          Obj.SetString('content', Item.Content);
          Arr.Add(Obj);
        end;
      finally
        TMonitor.Exit(TObject(FHttpHistory));
      end;
      
      Res := Results.Json(Arr.ToJson);
      Res.Execute(Ctx);
    end);
    
  // API: Projects
  App.MapGet('/api/projects', 
    procedure(Ctx: IHttpContext)
    var
      Registry: TProjectRegistry;
      Projects: TArray<TProjectInfo>;
      SB: TStringBuilder;
      I: Integer;
      EscapedPath, EscapedName: string;
      Res: IResult;
    begin
       Registry := Ctx.Services.GetRequiredService(TProjectRegistry) as TProjectRegistry;
       Projects := Registry.GetAllProjects;
       
       SB := TStringBuilder.Create;
       try
         SB.Append('[');
         for I := 0 to High(Projects) do
         begin
           if I > 0 then SB.Append(',');
           EscapedPath := Projects[I].Path.Replace('\', '\\').Replace('"', '\"');
           EscapedName := Projects[I].Name.Replace('\', '\\').Replace('"', '\"');
           
           SB.Append('{');
           SB.Append('"path":"').Append(EscapedPath).Append('",');
           SB.Append('"name":"').Append(EscapedName).Append('",');
           SB.Append('"lastAccess":"').Append(DateToISO8601(Projects[I].LastAccess, False)).Append('"');
           SB.Append('}');
         end;

         SB.Append(']');
         Res := Results.Text(SB.ToString, 200);
         Res.Execute(Ctx);
       finally
         SB.Free;
       end;
    end);

  // API: File System List
  App.MapGet('/api/fs/list',
    procedure(Ctx: IHttpContext)
    var
      ScanPath: string;
      Entries: TArray<string>;
      Entry: string;
      Arr: IDextJsonArray;
      Obj: IDextJsonObject;
      Res: IResult;
    begin
      if not Ctx.Request.Query.TryGetValue('path', ScanPath) then 
        ScanPath := '';
      if ScanPath = '' then ScanPath := 'C:\'; 
      
      if (Length(ScanPath) > 3) and ScanPath.EndsWith('\') then 
        ScanPath := ScanPath.Substring(0, Length(ScanPath)-1);
      
      try
        Arr := TDextJson.Provider.CreateArray;
        if TDirectory.Exists(ScanPath) then
        begin
          Entries := TDirectory.GetDirectories(ScanPath);
          for Entry in Entries do
          begin
            Obj := TDextJson.Provider.CreateObject;
            Obj.SetString('name', TPath.GetFileName(Entry));
            Obj.SetString('type', 'dir');
            Arr.Add(Obj);
          end;
          
          Entries := TDirectory.GetFiles(ScanPath);
          for Entry in Entries do
          begin
            Obj := TDextJson.Provider.CreateObject;
            Obj.SetString('name', TPath.GetFileName(Entry));
            Obj.SetString('type', 'file');
            Arr.Add(Obj);
          end;
        end;
        
        Res := Results.Json(Arr.ToJson);
        Res.Execute(Ctx);
      except
        on E: Exception do Results.BadRequest(E.Message).Execute(Ctx);
      end;
    end);

  // API: File System Read
  App.MapGet('/api/fs/read',
    procedure(Ctx: IHttpContext)
    var
      FilePath: string;
      Content: string;
    begin
      if not Ctx.Request.Query.TryGetValue('path', FilePath) then
        FilePath := '';
      if (FilePath = '') or not FileExists(FilePath) then
      begin
        Results.BadRequest('Valid file path required').Execute(Ctx);
        Exit;
      end;

      try
        Content := TFile.ReadAllText(FilePath, TEncoding.UTF8);
        Results.Text(Content, 200).Execute(Ctx);
      except
        on E: Exception do Results.InternalServerError(E.Message).Execute(Ctx);
      end;
    end);

  // API: Workspace Scan
  App.MapGet('/api/workspace/scan',
    procedure(Ctx: IHttpContext)
    var
      ScanPath: string;
      Projects, Tests, HttpFiles, Docs: IDextJsonArray;
      Files: TArray<string>;
      F: string;
      FinalObj: IDextJsonObject;
      Res: IResult;
      TestFiles: TArray<string>;
      Name: string;
      Found: Boolean;
      I: Integer;
      TestObj: IDextJsonObject;
    begin
       if not Ctx.Request.Query.TryGetValue('path', ScanPath) then
         ScanPath := '';
       if ScanPath = '' then 
       begin
          Results.BadRequest('Path required').Execute(Ctx);
          Exit;
       end;
       
       Projects := TDextJson.Provider.CreateArray;
       Tests := TDextJson.Provider.CreateArray;
       HttpFiles := TDextJson.Provider.CreateArray;
       Docs := TDextJson.Provider.CreateArray;
       
       try
          if TDirectory.Exists(ScanPath) then
          begin
              Files := TDirectory.GetFiles(ScanPath, '*.dproj', TSearchOption.soAllDirectories);
              for F in Files do Projects.Add(TPath.GetFileNameWithoutExtension(F));

              // Also scan for .dpr (console apps/tests that are not in dproj)
              Files := TDirectory.GetFiles(ScanPath, '*.dpr', TSearchOption.soAllDirectories);
              for F in Files do 
              begin
                 Name := TPath.GetFileNameWithoutExtension(F);
                 // Avoid duplicates if dproj already found
                 Found := False;
                 for I := 0 to Projects.GetCount - 1 do
                   if Projects.GetString(I).Equals(Name) then
                   begin
                     Found := True;
                     Break;
                   end;
                 
                 if not Found then Projects.Add(Name);
              end;
              
              Files := TDirectory.GetFiles(ScanPath, '*.http', TSearchOption.soAllDirectories);
              for F in Files do HttpFiles.Add(TPath.GetFileName(F));
              
              // Scan for Test Projects (.dproj or .dpr) containing "test" case-insensitive
              TestFiles := TDirectory.GetFiles(ScanPath, '*test*.dproj', TSearchOption.soAllDirectories);
              TestFiles := TestFiles + TDirectory.GetFiles(ScanPath, '*test*.dpr', TSearchOption.soAllDirectories);
              
              for F in TestFiles do 
              begin
                 Name := TPath.GetFileNameWithoutExtension(F);
                 // Avoid duplicates
                 Found := False;
                 for I := 0 to Tests.GetCount - 1 do
                   if (Tests.GetNode(I).GetNodeType = jntObject) and Tests.GetObject(I).GetString('name').Equals(Name) then
                   begin
                     Found := True;
                     Break;
                   end;
                 
                 if not Found then 
                 begin
                   TestObj := TDextJson.Provider.CreateObject;
                   TestObj.SetString('name', Name);
                   TestObj.SetString('path', F);
                   Tests.Add(TestObj);
                 end;
              end;
          end;
          
          FinalObj := TDextJson.Provider.CreateObject;
          FinalObj.SetArray('projects', Projects);
          FinalObj.SetArray('tests', Tests);
          FinalObj.SetArray('httpFiles', HttpFiles);
          FinalObj.SetArray('docs', Docs);
          
          Res := Results.Json(FinalObj.ToJson);
          Res.Execute(Ctx);
       finally
       end;
    end);


  // API: Discover Tests in Project
  App.MapGet('/api/tests/discover',
    procedure(Ctx: IHttpContext)
    var
       ProjectPath: string;
       ProjectInfo: TTestProjectInfo;
       Fixture: TTestFixtureInfo;
       Method: TTestMethodInfo;
       
       ResJson, FixtureObj, MethodObj: IDextJsonObject;
       FixturesArr, MethodsArr: IDextJsonArray;
       Res: IResult;
    begin
       if not Ctx.Request.Query.TryGetValue('project', ProjectPath) then
         ProjectPath := '';
       
       if (ProjectPath = '') or not FileExists(ProjectPath) then
       begin
          Results.BadRequest('Valid project path required').Execute(Ctx);
          Exit;
       end;
       
       try
         ProjectInfo := TTestScanner.ScanProject(ProjectPath);
         try
            ResJson := TDextJson.Provider.CreateObject;
            ResJson.SetString('project', TPath.GetFileNameWithoutExtension(ProjectPath));
            ResJson.SetString('path', ProjectPath);
            
            FixturesArr := TDextJson.Provider.CreateArray;
            for Fixture in ProjectInfo.Fixtures do
            begin
                FixtureObj := TDextJson.Provider.CreateObject;
                FixtureObj.SetString('name', Fixture.Name);
                FixtureObj.SetString('unit', Fixture.UnitName);
                FixtureObj.SetInteger('line', Fixture.LineNumber);
                
                MethodsArr := TDextJson.Provider.CreateArray;
                for Method in Fixture.Methods do
                begin
                    MethodObj := TDextJson.Provider.CreateObject;
                    MethodObj.SetString('name', Method.Name);
                    MethodObj.SetInteger('line', Method.LineNumber);
                    MethodsArr.Add(MethodObj);
                end;
                FixtureObj.SetArray('tests', MethodsArr);
                
                FixturesArr.Add(FixtureObj);
            end;
            ResJson.SetArray('fixtures', FixturesArr);
            
            Res := Results.Json(ResJson.ToJson);
            Res.Execute(Ctx);
         finally
            ProjectInfo.Free;
         end;
        except
          on E: Exception do Results.StatusCode(500, E.Message).Execute(Ctx);
        end;
     end);

  // API: Sync Projects from IDE Expert
  App.MapPost('/api/ide/projects',
    procedure(Ctx: IHttpContext)
    var
      SR: TStreamReader;
      Body: string;
      Node: IDextJsonNode;
      JArr: IDextJsonArray;
      I: Integer;
      Path: string;
      ProjObj, TestsObj: IDextJsonArray;
      TestObj: IDextJsonObject;
      ResJson: IDextJsonObject;
      BaseDirs: TStringList;
      Name: string;
      SeenPaths: TStringList;
      Dir: string;
      TestsDir: string;
      FoundFiles: TArray<string>;
      TestProjPath: string;
      ProjName: string;
    begin
      SR := TStreamReader.Create(Ctx.Request.Body);
      try
        Body := SR.ReadToEnd;
        if Body.IsEmpty then
        begin
          Results.BadRequest('Payload required').Execute(Ctx);
          Exit;
        end;

        try
          Node := TDextJson.Provider.Parse(Body);
          if (Node <> nil) and (Node.GetNodeType = jntArray) then
          begin
            JArr := Node as IDextJsonArray;
            ProjObj := TDextJson.Provider.CreateArray;
            TestsObj := TDextJson.Provider.CreateArray;

            // Collect base dirs from the received project paths to auto-discover siblings Tests/
            BaseDirs := TStringList.Create;
            BaseDirs.Duplicates := dupIgnore;
            BaseDirs.Sorted := True;

            for I := 0 to JArr.GetCount - 1 do
            begin
              Path := JArr.GetString(I);
              if FileExists(Path) then
              begin
                ProjObj.Add(TPath.GetFileNameWithoutExtension(Path));
                BaseDirs.Add(TPath.GetDirectoryName(Path));

                // If the project name itself contains 'Test', treat it as a test project
                Name := TPath.GetFileNameWithoutExtension(Path);
                if Name.Contains('Test') then
                begin
                  TestObj := TDextJson.Provider.CreateObject;
                  TestObj.SetString('name', Name);
                  TestObj.SetString('path', Path);
                  TestsObj.Add(TestObj);
                end;
              end;
            end;

            // Auto-discover test projects: look for a Tests/ directory sibling to the group base dirs
            try
              SeenPaths := TStringList.Create;
              SeenPaths.Duplicates := dupIgnore;
              SeenPaths.Sorted := True;
              try
                for Dir in BaseDirs do
                begin
                  TestsDir := TPath.Combine(TPath.GetDirectoryName(Dir), 'Tests');
                  if TDirectory.Exists(TestsDir) then
                  begin
                    // Search recursively for *.dproj files containing 'Test' in name
                    FoundFiles := TDirectory.GetFiles(TestsDir, '*.dproj', TSearchOption.soAllDirectories);
                    for TestProjPath in FoundFiles do
                    begin
                      ProjName := TPath.GetFileNameWithoutExtension(TestProjPath);
                      if ProjName.Contains('Test') and (SeenPaths.IndexOf(TestProjPath) < 0) then
                      begin
                        SeenPaths.Add(TestProjPath);
                        TestObj := TDextJson.Provider.CreateObject;
                        TestObj.SetString('name', ProjName);
                        TestObj.SetString('path', TestProjPath);
                        TestsObj.Add(TestObj);
                      end;
                    end;
                  end;
                end;
              finally
                SeenPaths.Free;
              end;
            except
              // Swallow auto-discovery errors - not critical
            end;
            BaseDirs.Free;

            ResJson := TDextJson.Provider.CreateObject;
            ResJson.SetArray('projects', ProjObj);
            ResJson.SetArray('tests', TestsObj);
            ResJson.SetArray('httpFiles', TDextJson.Provider.CreateArray);
            ResJson.SetArray('docs', TDextJson.Provider.CreateArray);

            // Broadcast workspace update via SSE so Dashboard refreshes instantly!
            TDashboardRoutes.BroadcastSSE('workspace_sync', ResJson.ToJson);

            Results.Ok('{"status":"synced"}').Execute(Ctx);
          end
          else
            Results.BadRequest('Expected JSON Array').Execute(Ctx);
        except
          on E: Exception do Results.BadRequest(E.Message).Execute(Ctx);
        end;
      finally
        SR.Free;
      end;
    end);

  // API: Run Tests in Projects (Multi-Project)
  App.MapPost('/api/tests/run',
    procedure(Ctx: IHttpContext)
    var
      SR: TStreamReader;
      Body: string;
      Node: IDextJsonNode;
      Json, ResJson: IDextJsonObject;
      ProjArr, TestsArr: IDextJsonArray;
      I: Integer;
      ProjectPath: string;
      SelectedTests: TArray<string>;
      SelectedTestsList: TStringList;
      RunnerResult: IDextJsonObject;
      CombinedResult: IDextJsonArray;
      SuccessCount, FailCount: Integer;
      UseCoverage: Boolean;
    begin
      SR := TStreamReader.Create(Ctx.Request.Body);
      try
        Body := SR.ReadToEnd;
        if Body.IsEmpty then
        begin
          Results.BadRequest('Payload required').Execute(Ctx);
          Exit;
        end;

        try
          Node := TDextJson.Provider.Parse(Body);
          if (Node <> nil) and (Node.GetNodeType = jntObject) then
          begin
            Json := Node as IDextJsonObject;
            
            // 1. Gather selected tests
            SelectedTestsList := TStringList.Create;
            try
              if Json.Contains('tests') then
              begin
                TestsArr := Json.GetArray('tests');
                for I := 0 to TestsArr.GetCount - 1 do
                  SelectedTestsList.Add(TestsArr.GetString(I));
              end;
              SelectedTests := SelectedTestsList.ToStringArray;
            finally
              SelectedTestsList.Free;
            end;
            
            // Set global active selection for external test server compatibility
            TTestCompatServer.SetSelectedTests(SelectedTests);
            
            CombinedResult := TDextJson.Provider.CreateArray;
            SuccessCount := 0;
            FailCount := 0;
            
            UseCoverage := False;
            if Json.Contains('coverage') then
              UseCoverage := Json.GetBoolean('coverage');

            // 2. Iterate and execute projects (array "projects" or singular "project")
            if Json.Contains('projects') then
            begin
              ProjArr := Json.GetArray('projects');
              for I := 0 to ProjArr.GetCount - 1 do
              begin
                ProjectPath := ProjArr.GetString(I);
                if FileExists(ProjectPath) then
                begin
                  RunnerResult := TTestRunner.RunProject(ProjectPath, UseCoverage);
                  CombinedResult.Add(RunnerResult);
                  if RunnerResult.Contains('error') then
                    Inc(FailCount)
                  else
                    Inc(SuccessCount);
                end;
              end;
            end
            else if Json.Contains('project') then
            begin
              ProjectPath := Json.GetString('project');
              if FileExists(ProjectPath) then
              begin
                RunnerResult := TTestRunner.RunProject(ProjectPath, UseCoverage);
                CombinedResult.Add(RunnerResult);
                if RunnerResult.Contains('error') then
                  Inc(FailCount)
                else
                  Inc(SuccessCount);
              end
              else
              begin
                Results.BadRequest('Project file not found: ' + ProjectPath).Execute(Ctx);
                Exit;
              end;
            end
            else
            begin
              Results.BadRequest('Missing "projects" array or "project" field').Execute(Ctx);
              Exit;
            end;

            ResJson := TDextJson.Provider.CreateObject;
            ResJson.SetArray('results', CombinedResult);
            ResJson.SetInteger('successCount', SuccessCount);
            ResJson.SetInteger('failCount', FailCount);

            Results.Json(ResJson.ToJson).Execute(Ctx);
          end
          else
            Results.BadRequest('Invalid JSON object').Execute(Ctx);
        except
          on E: Exception do Results.BadRequest('Invalid JSON: ' + E.Message).Execute(Ctx);
        end;
      finally
        SR.Free;
      end;
    end);
     
  // API: Get Config
  App.MapGet('/api/config',
    procedure(Ctx: IHttpContext)
    var
      Config: TDextGlobalConfig;
      Json, EnvObj: IDextJsonObject;
      Arr, PlatArr: IDextJsonArray;
      Res: IResult;
      Env: TDextEnvironment;
      P: string;
      CovPath: string;
    begin
      Config := TDextGlobalConfig.Create;
      try
        Config.Load;
        Json := TDextJson.Provider.CreateObject;
        
        Json.SetString('dextPath', Config.DextPath);
        if Config.DextPath.IsEmpty then Json.SetString('dextPath', ParamStr(0));
        
        CovPath := Config.CoveragePath;
        if (CovPath = '') then
           CovPath := TCodeCoverageTool.FindPath(Config, 'Win32');

        Json.SetString('coveragePath', CovPath);
        Json.SetString('configPath', TPath.Combine(TPath.Combine(TPath.GetHomePath, '.dext'), 'config.yaml'));
        
        Arr := TDextJson.Provider.CreateArray;
        for Env in Config.Environments do
        begin
          EnvObj := TDextJson.Provider.CreateObject;
          EnvObj.SetString('version', Env.Version);
          EnvObj.SetString('name', Env.Name);
          EnvObj.SetString('path', Env.Path);
          EnvObj.SetBoolean('isDefault', Env.IsDefault);
          
          PlatArr := TDextJson.Provider.CreateArray;
          for P in Env.Platforms do
            PlatArr.Add(P);
          EnvObj.SetArray('platforms', PlatArr);
          
          Arr.Add(EnvObj);
        end;
        Json.SetArray('environments', Arr);
        
        Res := Results.Json(Json.ToJson);
        Res.Execute(Ctx);
      finally
        Config.Free;
      end;
    end);

  // API: Save Config 
  App.MapPost('/api/config',
    procedure(Ctx: IHttpContext)
    var
      Body: string;
      Res: IResult;
      SR: TStreamReader;
      Node: IDextJsonNode;
      Json: IDextJsonObject;
      Config: TDextGlobalConfig;
    begin
      SR := TStreamReader.Create(Ctx.Request.Body);
      try
         Body := SR.ReadToEnd;
         try
           Node := TDextJson.Provider.Parse(Body);
           if (Node <> nil) and (Node.GetNodeType = jntObject) then
           begin
              Json := Node as IDextJsonObject;
              Config := TDextGlobalConfig.Create;
              try
                Config.Load;
                if Json.Contains('dextPath') then Config.DextPath := Json.GetString('dextPath');
                if Json.Contains('coveragePath') then Config.CoveragePath := Json.GetString('coveragePath');
                Config.Save;
                
                Res := Results.Ok('{"status":"saved"}');
              finally
                Config.Free;
              end;
           end
           else
             Res := Results.BadRequest('Invalid JSON or not an object');
         except
           on E: Exception do Res := Results.BadRequest('Invalid JSON: ' + E.Message);
         end;
            
         Res.Execute(Ctx);
      finally
         SR.Free;
      end;
    end);
    
  // API: Scan Environments
  App.MapPost('/api/env/scan',
    procedure(Ctx: IHttpContext)
    var
      Scanner: TDextGlobalConfig;
      Res: IResult;
    begin
       Scanner := TDextGlobalConfig.Create;
       try
         Scanner.ScanEnvironments;
         Res := Results.Ok('{"status":"ok"}');
         Res.Execute(Ctx);
       finally
         Scanner.Free;
       end;
    end);

  // API: Install Code Coverage
  App.MapPost('/api/tools/codecoverage/install',
    procedure(Ctx: IHttpContext)
    var
      Path: string;
      Res: IResult;
    begin
       try
         TCodeCoverageTool.InstallLatest(Path);
         Res := Results.Ok('{"status":"ok", "path": "' + Path.Replace('\', '\\') + '"}');
         Res.Execute(Ctx);
       except
         on E: Exception do
         begin
           Res := Results.StatusCode(500, Format('{"error": "%s"}', [E.Message.Replace('"', '\"')]));
           Res.Execute(Ctx);
         end;
       end;
    end);

  // API: Set Default Environment
  App.MapPost('/api/env/default',
    procedure(Ctx: IHttpContext)
    var
      Body, Ver: string;
      Res: IResult;
      SR: TStreamReader;
      Node: IDextJsonNode;
      Json: IDextJsonObject;
      Config: TDextGlobalConfig;
      I: Integer;
      Updated: Boolean;
      E: TDextEnvironment;
      NewState: Boolean;
    begin
      SR := TStreamReader.Create(Ctx.Request.Body);
      try
         Body := SR.ReadToEnd;
         try
           Node := TDextJson.Provider.Parse(Body);
           if (Node <> nil) and (Node.GetNodeType = jntObject) then
           begin
              Json := Node as IDextJsonObject;
              if Json.Contains('version') then
              begin
                Ver := Json.GetString('version');
                Config := TDextGlobalConfig.Create;
                try
                  Config.Load;
                  Updated := False;
                  for I := 0 to Config.Environments.Count - 1 do
                  begin
                     E := Config.Environments[I];
                     NewState := (E.Version = Ver);
                     if E.IsDefault <> NewState then
                     begin
                        E.IsDefault := NewState;
                        Config.Environments[I] := E; 
                        Updated := True;
                     end;
                  end;
                  
                  if Updated then Config.Save;
                  Res := Results.Ok('{"status":"updated"}');
                finally
                  Config.Free;
                end;
              end
              else
                Res := Results.BadRequest('Missing version field');
           end
           else
             Res := Results.BadRequest('Invalid JSON');
         except
           on E: Exception do Res := Results.BadRequest('Invalid JSON: ' + E.Message);
         end;
         Res.Execute(Ctx);
      finally
         SR.Free;
      end;
    end);

  // API: HTTP Client - Parse
  App.MapPost('/api/http/parse',
    procedure(Ctx: IHttpContext)
    var
      Body: string;
      Res: IResult;
      SR: TStreamReader;
      Node: IDextJsonNode;
      Json, ResJson, ReqObj, VarObj: IDextJsonObject;
      Collection: THttpRequestCollection;
      ReqArr, VarArr: IDextJsonArray;
      I: Integer;
    begin
      SR := TStreamReader.Create(Ctx.Request.Body);
      try
        Body := SR.ReadToEnd;
        try
          Node := TDextJson.Provider.Parse(Body);
          if (Node <> nil) and (Node.GetNodeType = jntObject) then
          begin
            Json := Node as IDextJsonObject;
            if Json.Contains('content') then
            begin
              Body := Json.GetString('content');
              Collection := THttpRequestParser.Parse(Body);
              try
                ResJson := TDextJson.Provider.CreateObject;
                ReqArr := TDextJson.Provider.CreateArray;
                for I := 0 to Collection.Requests.Count - 1 do
                begin
                  ReqObj := TDextJson.Provider.CreateObject;
                  ReqObj.SetString('name', Collection.Requests[I].Name);
                  ReqObj.SetString('method', Collection.Requests[I].Method);
                  ReqObj.SetString('url', Collection.Requests[I].Url);
                  ReqObj.SetInteger('lineNumber', Collection.Requests[I].LineNumber);
                  ReqObj.SetString('body', Collection.Requests[I].Body);
                  ReqArr.Add(ReqObj);
                end;
                ResJson.SetArray('requests', ReqArr);
                
                VarArr := TDextJson.Provider.CreateArray;
                for I := 0 to Collection.Variables.Count - 1 do
                begin
                  VarObj := TDextJson.Provider.CreateObject;
                  VarObj.SetString('name', Collection.Variables[I].Name);
                  VarObj.SetString('value', Collection.Variables[I].Value);
                  VarObj.SetBoolean('isEnvVar', Collection.Variables[I].IsEnvVar);
                  VarObj.SetString('envVarName', Collection.Variables[I].EnvVarName);
                  VarArr.Add(VarObj);
                end;
                ResJson.SetArray('variables', VarArr);
                
                Res := Results.Json(ResJson.ToJson);
              finally
                Collection.Free;
              end;
            end
            else
              Res := Results.BadRequest('Missing content field');
          end
          else
            Res := Results.BadRequest('Invalid JSON');
        except
          on E: Exception do Res := Results.BadRequest('Invalid JSON: ' + E.Message);
        end;
        Res.Execute(Ctx);
      finally
        SR.Free;
      end;
    end);

  // API: HTTP Client - Execute
  App.MapPost('/api/http/execute',
    procedure(Ctx: IHttpContext)
    var
      Body: string;
      Collection: THttpRequestCollection;
      ExResult: THttpExecutionResult;
      Node: IDextJsonNode;
      Json, ResJson, HeadersObj: IDextJsonObject;
      RequestIndex: Integer;
      Res: IResult;
      SR: TStreamReader;
      HdrKey: string;
      HistoryItem: THttpHistoryItem;
    begin
      SR := TStreamReader.Create(Ctx.Request.Body);
      try
        Body := SR.ReadToEnd;
        try
          Node := TDextJson.Provider.Parse(Body);
          if (Node <> nil) and (Node.GetNodeType = jntObject) then
          begin
            Json := Node as IDextJsonObject;
            RequestIndex := 0;
            if Json.Contains('requestIndex') then RequestIndex := Json.GetInteger('requestIndex');
            
            if Json.Contains('content') then
            begin
              Body := Json.GetString('content');
              Collection := THttpRequestParser.Parse(Body);
              try
                if (RequestIndex >= 0) and (RequestIndex < Collection.Requests.Count) then
                begin
                  ExResult := THttpExecutor.ExecuteSync(Collection.Requests[RequestIndex], Collection.Variables);
                  
                  ResJson := TDextJson.Provider.CreateObject;
                  ResJson.SetString('requestName', ExResult.RequestName);
                  ResJson.SetString('requestMethod', ExResult.RequestMethod);
                  ResJson.SetString('requestUrl', ExResult.RequestUrl);
                  ResJson.SetInteger('statusCode', ExResult.StatusCode);
                  ResJson.SetString('statusText', ExResult.StatusText);
                  ResJson.SetString('responseBody', ExResult.ResponseBody);
                  ResJson.SetInt64('durationMs', ExResult.DurationMs);
                  ResJson.SetBoolean('success', ExResult.Success);
                  ResJson.SetString('errorMessage', ExResult.ErrorMessage);
                  
                  HeadersObj := TDextJson.Provider.CreateObject;
                  if ExResult.ResponseHeaders <> nil then
                    for HdrKey in ExResult.ResponseHeaders.Keys do
                      HeadersObj.SetString(HdrKey, ExResult.ResponseHeaders[HdrKey]);
                  ResJson.SetObject('responseHeaders', HeadersObj);
                  
                  Res := Results.Json(ResJson.ToJson);
                  Res.Execute(Ctx);
                  
                  // Save to History
                  if FHttpHistory = nil then
                     FHttpHistory := TCollections.CreateList<THttpHistoryItem>(True);
                  
                  TMonitor.Enter(TObject(FHttpHistory));
                  try
                    HistoryItem := THttpHistoryItem.Create;
                    HistoryItem.Id := TGUID.NewGuid.ToString;
                    HistoryItem.Method := Collection.Requests[RequestIndex].Method;
                    HistoryItem.Url := Collection.Requests[RequestIndex].Url;
                    HistoryItem.StatusCode := ExResult.StatusCode;
                    HistoryItem.DurationMs := ExResult.DurationMs;
                    HistoryItem.Timestamp := Now;
                    HistoryItem.Content := Body; 
                    
                    FHttpHistory.Insert(0, HistoryItem);
                    
                    // Limit to 50
                    while FHttpHistory.Count > 50 do
                      FHttpHistory.Delete(FHttpHistory.Count - 1);
                  finally
                    TMonitor.Exit(TObject(FHttpHistory));
                  end;
                end
                else
                  Results.BadRequest('Invalid request index').Execute(Ctx);
              finally
                Collection.Free;
              end;
            end
            else
              Results.BadRequest('Missing content field').Execute(Ctx);
          end
          else
            Results.BadRequest('Invalid JSON').Execute(Ctx);
        except
          on E: Exception do Results.BadRequest('Invalid JSON: ' + E.Message).Execute(Ctx);
        end;
      finally
        SR.Free;
      end;
    end);

  // API: Telemetry Logs Ingestion
  App.MapPost('/api/telemetry/logs',
    procedure(Ctx: IHttpContext)
    var
      Body: string;
      Node: IDextJsonNode;
      JA: IDextJsonArray;
      SR: TStreamReader;
      Streamer: IEventStreamer;
      I: Integer;
      ItemNode: IDextJsonNode;

      procedure ProcessItem(AItem: IDextJsonObject);
      var
        EType, SEvent: string;
      begin
        EType := '';
        if AItem.Contains('event') then EType := AItem.GetString('event');

        SEvent := '';
        if EType = 'RunStart' then SEvent := 'run_start'
        else if EType = 'TestStart' then SEvent := 'test_start'
        else if EType = 'TestComplete' then SEvent := 'test_complete'
        else if EType = 'RunComplete' then SEvent := 'run_complete';

        // If it's a specific dashboard event, broadcast legacy + push to S23
        if SEvent <> '' then
        begin
          if Streamer <> nil then
            Streamer.PushEvent(SEvent, AItem.ToJson);
          
          // Only broadcast high-level events (run_start, etc) to legacy clients
          BroadcastSSE(SEvent, AItem.ToJson);
        end
        else
        begin
          // Assume it's a standard log entry
          if Streamer <> nil then
            Streamer.PushEvent('log', AItem.ToJson);
            
          // Append to in-memory ring buffer - disk save handled by FSaveTimer
          TMonitor.Enter(FLock);
          try
            FTraceHistory.Add('{"event":"log","data":' + AItem.ToJson + '}');
            while FTraceHistory.Count > 1000 do FTraceHistory.RemoveAt(0);
          finally
            TMonitor.Exit(FLock);
          end;
        end;
      end;

    begin
      Streamer := TDextServices.GetService<IEventStreamer>(Ctx.Services);

      // Read logs
      SR := TStreamReader.Create(Ctx.Request.Body);
      try
        Body := SR.ReadToEnd;
        if Body.IsEmpty then
        begin
          Ctx.Response.StatusCode := 204; // No Content
          Exit;
        end;

        // ADAPTER: Telemetry to Dashboard
        try
          Node := TDextJson.Provider.Parse(Body);
          if Node <> nil then
          begin
            if Node.GetNodeType = jntObject then
              ProcessItem(Node as IDextJsonObject)
            else if Node.GetNodeType = jntArray then
            begin
              JA := Node as IDextJsonArray;
              for I := 0 to JA.GetCount - 1 do
              begin
                ItemNode := JA.GetNode(I);
                if (ItemNode <> nil) and (ItemNode.GetNodeType = jntObject) then
                  ProcessItem(ItemNode as IDextJsonObject);
              end;
            end;
          end;
        except
          // Log parsing error but don't fail the request
        end;

        Ctx.Response.StatusCode := 202; // Accepted
      finally
        SR.Free;
      end;
    end);

  // API: Telemetry Events Ingestion (Spans/Traces)
  App.MapPost('/api/telemetry/events',
    procedure(Ctx: IHttpContext)
    var
      Body: string;
      SR: TStreamReader;
      Streamer: IEventStreamer;
    begin
      Streamer := TDextServices.GetService<IEventStreamer>(Ctx.Services);

      SR := TStreamReader.Create(Ctx.Request.Body);
      try
        Body := SR.ReadToEnd;
        if Body.IsEmpty then
        begin
          Ctx.Response.StatusCode := 204;
          Exit;
        end;

        if Streamer <> nil then
          Streamer.PushEvent('span', Body);

        // Append to in-memory ring buffer - disk save handled by FSaveTimer
        TMonitor.Enter(FLock);
        try
          FTraceHistory.Add('{"event":"span","data":' + Body + '}');
          while FTraceHistory.Count > 1000 do FTraceHistory.RemoveAt(0);
        finally
          TMonitor.Exit(FLock);
        end;

        Ctx.Response.StatusCode := 202;
      finally
        SR.Free;
      end;
    end);


  // API: SSE Events Endpoint (Fallback)
  // Note: POST /api/tests/run is registered once above (supports "projects"[] or "project").
  App.MapGet('/events',
    procedure(Ctx: IHttpContext)
    var
      IndyCtx: TIdContext;
    begin
         IndyCtx := nil;
         if Ctx is TDextIndyHttpContext then
            IndyCtx := TDextIndyHttpContext(Ctx).Context;



         if IndyCtx <> nil then
         begin
             // Manually write headers to flush immediately
             IndyCtx.Connection.IOHandler.WriteLn('HTTP/1.1 200 OK');
             IndyCtx.Connection.IOHandler.WriteLn('Content-Type: text/event-stream; charset=utf-8');
             IndyCtx.Connection.IOHandler.WriteLn('Cache-Control: no-cache');
             IndyCtx.Connection.IOHandler.WriteLn('Connection: keep-alive');
             IndyCtx.Connection.IOHandler.WriteLn(''); // End of headers
             
             // Initial Handshake
             IndyCtx.Connection.IOHandler.Write('event: connected'#10'data: {"msg":"welcome"}'#10#10);
         end
         else
         begin
             // Fallback
             Ctx.Response.SetContentType('text/event-stream; charset=utf-8');
             Ctx.Response.AddHeader('Cache-Control', 'no-cache');
             Ctx.Response.AddHeader('Connection', 'keep-alive');
             Ctx.Response.Write('event: connected'#10'data: {"msg":"welcome"}'#10#10);
         end;
         
         // Add to active clients list
         TMonitor.Enter(FLock);
         try
            FSSEClients.Add(Ctx);

         finally
            TMonitor.Exit(FLock);
         end;
         
         // Keep connection open
         try
            while not FServerStopping do
            begin
               if (IndyCtx <> nil) and (not IndyCtx.Connection.Connected) then Break;
               Sleep(500); 
            end;
         finally
            TMonitor.Enter(FLock);
            try
               FSSEClients.Remove(Ctx);
            finally
               TMonitor.Exit(FLock);
            end;
         end;
     end);

  // API: Telemetry History (returns last 200 items)
  App.MapGet('/api/telemetry/history',
    procedure(Ctx: IHttpContext)
    var
      JSON: string;
      I, StartI: Integer;
      Snapshot: TArray<string>;
    begin
      // Copy under lock, then build JSON outside lock
      TMonitor.Enter(FLock);
      try
        // Return last 200 items to avoid overwhelming the browser
        StartI := FTraceHistory.Count - 200;
        if StartI < 0 then StartI := 0;
        SetLength(Snapshot, FTraceHistory.Count - StartI);
        for I := StartI to FTraceHistory.Count - 1 do
          Snapshot[I - StartI] := FTraceHistory[I];
      finally
        TMonitor.Exit(FLock);
      end;

      JSON := '[';
      for I := 0 to High(Snapshot) do
      begin
        if I > 0 then JSON := JSON + ',';
        JSON := JSON + Snapshot[I];
      end;
      JSON := JSON + ']';
      Results.Json(JSON).Execute(Ctx);
    end);

  // API: Telemetry Metrics Ingestion (CPU, Memory, Threads, Custom metrics)
  App.MapPost('/api/telemetry/metrics',
    procedure(Ctx: IHttpContext)
    var
      Body: string;
      SR: TStreamReader;
      Streamer: IEventStreamer;
    begin
      Streamer := TDextServices.GetService<IEventStreamer>(Ctx.Services);

      SR := TStreamReader.Create(Ctx.Request.Body);
      try
        Body := SR.ReadToEnd;
        if Body.IsEmpty then
        begin
          Ctx.Response.StatusCode := 204;
          Exit;
        end;

        if Streamer <> nil then
          Streamer.PushEvent('metrics', Body);

        BroadcastSSE('metrics', Body);

        // Append to in-memory ring buffer - disk save handled by FSaveTimer
        TMonitor.Enter(FLock);
        try
          FMetricsHistory.Add(Body);
          while FMetricsHistory.Count > 120 do FMetricsHistory.RemoveAt(0);
        finally
          TMonitor.Exit(FLock);
        end;

        Ctx.Response.StatusCode := 202;
      finally
        SR.Free;
      end;
    end);

  // API: Telemetry Metrics History
  App.MapGet('/api/telemetry/metrics/history',
    procedure(Ctx: IHttpContext)
    var
      JSON: string;
      I: Integer;
    begin
      TMonitor.Enter(FLock);
      try
        JSON := '[';
        for I := 0 to FMetricsHistory.Count - 1 do
        begin
          if I > 0 then JSON := JSON + ',';
          JSON := JSON + FMetricsHistory[I];
        end;
        JSON := JSON + ']';
      finally
        TMonitor.Exit(FLock);
      end;
      Results.Json(JSON).Execute(Ctx);
    end);

  // ----------------------------------------------------------------------------------
  // S23 Validation: Streamable Sessions + HTMX Fragments
  // ----------------------------------------------------------------------------------

  // POST /sidecar/session
  // Creates a new IStreamableSession and returns its ID.
  // Used by HTMX or any client to establish a bidirectional stream channel.
  App.MapPost('/sidecar/session',
    procedure(Ctx: IHttpContext)
    var
      Manager: IStreamableSessionManager;
      Session: IStreamableSession;
    begin
      Manager := TDextServices.GetService<IStreamableSessionManager>(Ctx.Services);
      if Manager = nil then
      begin
        Results.StatusCode(503, '{"error":"StreamableSession not registered. Call Services.AddStreamableSessions."}').Execute(Ctx);
        Exit;
      end;
      Session := Manager.CreateSession;
      Results.Json(Format('{"sessionId":"%s"}', [Session.Id])).Execute(Ctx);
    end);

  // GET /sidecar/events
  // SSE endpoint that streams events from an IStreamableSession.
  // Requires ?sessionId=<id> query param (or Dext-Session-Id header).
  App.MapGet('/sidecar/events',
    procedure(Ctx: IHttpContext)
    var
      Manager: IStreamableSessionManager;
      Session: IStreamableSession;
      SessionId, EventName, Data: string;
      IndyCtx: TIdContext;
      Msg: string;
      HeartbeatTick: Integer;
    begin
      if not Ctx.Request.Query.TryGetValue('sessionId', SessionId) then
        SessionId := Ctx.Request.GetHeader('Dext-Session-Id');

      if SessionId.IsEmpty then
      begin
        Results.BadRequest('{"error":"sessionId required"}').Execute(Ctx);
        Exit;
      end;

      Manager := TDextServices.GetService<IStreamableSessionManager>(Ctx.Services);
      if Manager = nil then
      begin
        Results.StatusCode(503, '{"error":"StreamableSession not registered."}').Execute(Ctx);
        Exit;
      end;

      Session := Manager.GetSession(SessionId);
      if Session = nil then
      begin
        Results.NotFound('{"error":"Session not found or expired."}').Execute(Ctx);
        Exit;
      end;

      IndyCtx := nil;
      if Ctx is TDextIndyHttpContext then
        IndyCtx := TDextIndyHttpContext(Ctx).Context;

      if IndyCtx <> nil then
      begin
        IndyCtx.Connection.IOHandler.WriteLn('HTTP/1.1 200 OK');
        IndyCtx.Connection.IOHandler.WriteLn('Content-Type: text/event-stream; charset=utf-8');
        IndyCtx.Connection.IOHandler.WriteLn('Cache-Control: no-cache');
        IndyCtx.Connection.IOHandler.WriteLn('');
        IndyCtx.Connection.IOHandler.Write('event: connected'#10'data: {"sessionId":"' + SessionId + '"}'#10#10);
        HeartbeatTick := 0;
        while IndyCtx.Connection.Connected and (not FServerStopping) do
        begin
          if Session.TryDequeueEvent(EventName, Data) then
          begin
            Msg := Format('event: %s'#10'data: %s'#10#10, [EventName, Data]);
            IndyCtx.Connection.IOHandler.Write(ToBytes(Msg, IndyTextEncoding_UTF8));
            HeartbeatTick := 0;
          end
          else
          begin
            Inc(HeartbeatTick);
            // Send heartbeat comment every ~15s (75 * 200ms) to keep alive through proxies
            if HeartbeatTick >= 75 then
            begin
              IndyCtx.Connection.IOHandler.Write(ToBytes(':heartbeat'#10#10, IndyTextEncoding_UTF8));
              HeartbeatTick := 0;
            end;
            Sleep(200);
          end;
        end;
      end
      else
      begin
        // Fallback for non-Indy hosts
        Ctx.Response.SetContentType('text/event-stream; charset=utf-8');
        Ctx.Response.AddHeader('Cache-Control', 'no-cache');
        Ctx.Response.Write('event: connected'#10'data: {"sessionId":"' + SessionId + '"}'#10#10);
      end;

      Manager.DestroySession(SessionId);
    end);

  // GET /sidecar/fragments/metrics
  // HTMX-compatible HTML fragment with real-time Windows system metrics.
  // Designed for: hx-get="/sidecar/fragments/metrics" hx-trigger="every 3s" hx-swap="innerHTML"
  App.MapGet('/sidecar/fragments/metrics',
    procedure(Ctx: IHttpContext)
    var
      MemStatus: TMemoryStatusEx;
      TotalMB, AvailMB, UsedMB: Int64;
      UsedPct: Double;
      Html: string;
    begin
      MemStatus.dwLength := SizeOf(MemStatus);
      GlobalMemoryStatusEx(MemStatus);

      TotalMB := MemStatus.ullTotalPhys div (1024 * 1024);
      AvailMB := MemStatus.ullAvailPhys div (1024 * 1024);
      UsedMB  := TotalMB - AvailMB;
      UsedPct := MemStatus.dwMemoryLoad;

    Html :=
        '<div class="s23-metrics">' +
        '  <div class="s23-metric">' +
        '    <span class="s23-metric-label">Memory Used</span>' +
        '    <span class="s23-metric-value">' + IntToStr(UsedMB) + ' MB</span>' +
        '    <span class="s23-metric-sub">' + IntToStr(TotalMB) + ' MB total &mdash; ' +
               FormatFloat('0.0', UsedPct) + '% used</span>' +
        '    <div class="s23-bar-bg"><div class="s23-bar-fill" style="width:' +
               FormatFloat('0.0', UsedPct) + '%"></div></div>' +
        '  </div>' +
        '  <div class="s23-metric">' +
        '    <span class="s23-metric-label">Sidecar</span>' +
        '    <span class="s23-metric-value" style="color:#2ecc71">&#x25CF; Online</span>' +
        '    <span class="s23-metric-sub">S24 Observability Suite &mdash; ' +
               FormatDateTime('hh:nn:ss', Now) + '</span>' +
        '  </div>' +
        '</div>';

      // Results.Html sets Content-Type: text/html - required for HTMX fragment swap
      Results.Html(Html, 200).Execute(Ctx);
    end);

end;

procedure BroadcastSSE(const EventName, Data: string);
var
  Ctx: IHttpContext;
  Msg: string;
  IndyCtx: TIdContext;
  HubCtx: IHubContext;
begin
  // Prefer SignalR/WebSocket fan-out when hubs are live (http.sys path).
  try
    HubCtx := THubExtensions.GetHubContext;
    if HubCtx <> nil then
      HubCtx.Clients.All.SendAsync('DashboardEvent',
        TArray<TValue>.Create(TValue.From<string>(EventName), TValue.From<string>(Data)));
  except
    // Hubs not initialized or no clients — fall through to SSE list.
  end;

  if (FSSEClients = nil) then Exit;

  TMonitor.Enter(FLock);
  try
    if FSSEClients.Count = 0 then Exit;

    Msg := Format('event: %s'#10'data: %s'#10#10, [EventName, Data]);

    for Ctx in FSSEClients do
    begin
      try
        if Ctx is TDextIndyHttpContext then
        begin
           IndyCtx := TDextIndyHttpContext(Ctx).Context;
           if (IndyCtx <> nil) and (IndyCtx.Connection <> nil) and IndyCtx.Connection.Connected then
             IndyCtx.Connection.IOHandler.Write(ToBytes(Msg, IndyTextEncoding_UTF8));
        end
        else if Ctx.Response <> nil then
        begin
          // http.sys / native: write SSE frame through the abstract response.
          Ctx.Response.Write(Msg);
        end;
      except
        // Drop dead clients silently; accept loop removes them on disconnect.
      end;
    end;
  finally
    TMonitor.Exit(FLock);
  end;
end;

procedure LoadTelemetryHistory;
var
  Path: string;
  Content: string;
  Node: IDextJsonNode;
  Arr: IDextJsonArray;
  I: Integer;
begin
  Path := TPath.Combine(TPath.Combine(TPath.GetHomePath, '.dext'), 'telemetry.json');
  if not FileExists(Path) then Exit;

  try
    Content := TFile.ReadAllText(Path, TEncoding.UTF8);
    Node := TDextJson.Provider.Parse(Content);
    if (Node <> nil) and (Node.GetNodeType = jntArray) then
    begin
      Arr := Node as IDextJsonArray;
      FTraceHistory.Clear;
      for I := 0 to Arr.GetCount - 1 do
        FTraceHistory.Add(Arr.GetNode(I).ToJson);
    end;
  except
    // ignore load error
  end;
end;

procedure SaveTelemetryHistory;
var
  Path: string;
  Dir: string;
  JSON: string;
  I: Integer;
  Snapshot: TArray<string>;
begin
  Path := TPath.Combine(TPath.Combine(TPath.GetHomePath, '.dext'), 'telemetry.json');
  Dir := TPath.GetDirectoryName(Path);
  try
    if not TDirectory.Exists(Dir) then
      TDirectory.CreateDirectory(Dir);

    // Copy data under lock, then write outside lock to avoid I/O blocking
    TMonitor.Enter(FLock);
    try
      SetLength(Snapshot, FTraceHistory.Count);
      for I := 0 to FTraceHistory.Count - 1 do
        Snapshot[I] := FTraceHistory[I];
    finally
      TMonitor.Exit(FLock);
    end;

    JSON := '[';
    for I := 0 to High(Snapshot) do
    begin
      if I > 0 then JSON := JSON + ',';
      JSON := JSON + Snapshot[I];
    end;
    JSON := JSON + ']';

    TFile.WriteAllText(Path, JSON, TEncoding.UTF8);
  except
    on E: Exception do
      WriteLn('>> [Dashboard] Failed to save telemetry history: ' + E.Message);
  end;
end;

procedure LoadMetricsHistory;
var
  Path: string;
  Content: string;
  Node: IDextJsonNode;
  Arr: IDextJsonArray;
  I: Integer;
begin
  Path := TPath.Combine(TPath.Combine(TPath.GetHomePath, '.dext'), 'metrics.json');
  if not FileExists(Path) then Exit;

  try
    Content := TFile.ReadAllText(Path, TEncoding.UTF8);
    Node := TDextJson.Provider.Parse(Content);
    if (Node <> nil) and (Node.GetNodeType = jntArray) then
    begin
      Arr := Node as IDextJsonArray;
      FMetricsHistory.Clear;
      for I := 0 to Arr.GetCount - 1 do
        FMetricsHistory.Add(Arr.GetNode(I).ToJson);
    end;
  except
    // ignore load error
  end;
end;

procedure SaveMetricsHistory;
var
  Path: string;
  Dir: string;
  JSON: string;
  I: Integer;
  Snapshot: TArray<string>;
begin
  Path := TPath.Combine(TPath.Combine(TPath.GetHomePath, '.dext'), 'metrics.json');
  Dir := TPath.GetDirectoryName(Path);
  try
    if not TDirectory.Exists(Dir) then
      TDirectory.CreateDirectory(Dir);

    // Copy data under lock, then write outside lock to avoid I/O blocking
    TMonitor.Enter(FLock);
    try
      SetLength(Snapshot, FMetricsHistory.Count);
      for I := 0 to FMetricsHistory.Count - 1 do
        Snapshot[I] := FMetricsHistory[I];
    finally
      TMonitor.Exit(FLock);
    end;

    JSON := '[';
    for I := 0 to High(Snapshot) do
    begin
      if I > 0 then JSON := JSON + ',';
      JSON := JSON + Snapshot[I];
    end;
    JSON := JSON + ']';

    TFile.WriteAllText(Path, JSON, TEncoding.UTF8);
  except
    on E: Exception do
      WriteLn('>> [Dashboard] Failed to save metrics history: ' + E.Message);
  end;
end;

initialization
  FHttpHistory := TCollections.CreateList<THttpHistoryItem>(True);
  FSSEClients := TCollections.CreateList<IHttpContext>;
  FTraceHistory := TCollections.CreateList<string>;
  FMetricsHistory := TCollections.CreateList<string>;
  FServerStopping := False;
  FLock := TObject.Create;
  LoadTelemetryHistory;
  LoadMetricsHistory;
  // Start background save timer (flushes to disk every 30 seconds)
  FSaveTimer := TDashboardSaveTimer.Create(30000);

finalization
  FServerStopping := True;
  // Stop timer cleanly before flushing
  if Assigned(FSaveTimer) then
  begin
    FSaveTimer.Terminate;
    FSaveTimer.WaitFor;
    FSaveTimer.Free;
    FSaveTimer := nil;
  end;
  // Final flush to disk
  try SaveTelemetryHistory; except end;
  try SaveMetricsHistory; except end;
  FLock.Free;
  FHttpHistory := nil;
  FTraceHistory := nil;
  FMetricsHistory := nil;
  FSSEClients := nil;

end.
