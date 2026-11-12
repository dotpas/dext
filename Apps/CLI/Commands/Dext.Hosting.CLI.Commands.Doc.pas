unit Dext.Hosting.CLI.Commands.Doc;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections, // for TJSONArray.GetValue
  System.IOUtils,
  System.JSON,
  Dext.Hosting.CLI.Args,
  Dext.Hosting.CLI.Tools.DocGen,
  Dext.Utils;

type
  TDocCommand = class(TInterfacedObject, IConsoleCommand)
  private
    const
      THEME_CSS = 
        '/* Dext Documentation Theme - Default (Dark) */' + sLineBreak +
        ':root {' + sLineBreak +
        '    /* Color Palette */' + sLineBreak +
        '    --bg-primary: #0f172a;' + sLineBreak +
        '    --bg-secondary: #1e293b;' + sLineBreak +
        '    --bg-tertiary: #334155;' + sLineBreak +
        '    ' + sLineBreak +
        '    --text-primary: #f8fafc;' + sLineBreak +
        '    --text-secondary: #94a3b8;' + sLineBreak +
        '    --text-muted: #64748b;' + sLineBreak + // Added muted
        '    --text-link: #38bdf8;' + sLineBreak +
        '    ' + sLineBreak +
        '    --border-color: rgba(255, 255, 255, 0.1);' + sLineBreak +
        '    --accent-color: #38bdf8;' + sLineBreak +
        '    ' + sLineBreak +
        '    /* Code Blocks */' + sLineBreak +
        '    --code-bg: #1e1e1e;' + sLineBreak +
        '    --code-text: #d4d4d4;' + sLineBreak +
        '    ' + sLineBreak +
        '    /* Sidebar */' + sLineBreak +
        '    --sidebar-bg: rgba(15, 23, 42, 0.95);' + sLineBreak +
        '    --sidebar-width: 300px;' + sLineBreak +
        '    ' + sLineBreak +
        '    /* Typography */' + sLineBreak +
        '    --font-family: ''Inter'', -apple-system, system-ui, sans-serif;' + sLineBreak +
        '    --font-code: ''Fira Code'', ''Consolas'', monospace;' + sLineBreak +
        '}' + sLineBreak +
        '' + sLineBreak +
        '[data-theme="light"] {' + sLineBreak +
        '    --bg-primary: #ffffff;' + sLineBreak +
        '    --bg-secondary: #f8fafc;' + sLineBreak +
        '    --bg-tertiary: #e2e8f0;' + sLineBreak +
        '    ' + sLineBreak +
        '    --text-primary: #1e293b;' + sLineBreak +
        '    --text-secondary: #475569;' + sLineBreak +
        '    --text-muted: #94a3b8;' + sLineBreak +
        '    --text-link: #0284c7;' + sLineBreak +
        '    ' + sLineBreak +
        '    --border-color: #e2e8f0;' + sLineBreak +
        '    --accent-color: #0284c7;' + sLineBreak +
        '    ' + sLineBreak +
        '    --code-bg: #f1f5f9;' + sLineBreak +
        '    --code-text: #334155;' + sLineBreak +
        '    ' + sLineBreak +
        '    --sidebar-bg: rgba(255, 255, 255, 0.95);' + sLineBreak +
        '}';
      
      LAYOUT_CSS = 
        '/* Structural Layout - Independent of Color Theme */' + sLineBreak +
        '* {' + sLineBreak +
        '    box-sizing: border-box;' + sLineBreak +
        '}' + sLineBreak +
        '' + sLineBreak +
        'body {' + sLineBreak +
        '    margin: 0;' + sLineBreak +
        '    font-family: var(--font-family);' + sLineBreak +
        '    background-color: var(--bg-primary);' + sLineBreak +
        '    color: var(--text-primary);' + sLineBreak +
        '    height: 100vh;' + sLineBreak +
        '    display: flex;' + sLineBreak +
        '    overflow: hidden;' + sLineBreak +
        '}' + sLineBreak +
        '' + sLineBreak +
        '/* Sidebar */' + sLineBreak +
        '.sidebar {' + sLineBreak +
        '    width: var(--sidebar-width);' + sLineBreak +
        '    background: var(--sidebar-bg);' + sLineBreak +
        '    border-right: 1px solid var(--border-color);' + sLineBreak +
        '    display: flex;' + sLineBreak +
        '    flex-direction: column;' + sLineBreak +
        '    flex-shrink: 0;' + sLineBreak +
        '}' + sLineBreak +
        '' + sLineBreak +
        '.sidebar-header {' + sLineBreak +
        '    padding: 20px;' + sLineBreak +
        '    border-bottom: 1px solid var(--border-color);' + sLineBreak +
        '}' + sLineBreak +
        '' + sLineBreak +
        '.search-box {' + sLineBreak +
        '    padding: 10px 20px;' + sLineBreak +
        '}' + sLineBreak +
        '' + sLineBreak +
        '.search-input {' + sLineBreak +
        '    width: 100%;' + sLineBreak +
        '    padding: 8px;' + sLineBreak +
        '    border-radius: 6px;' + sLineBreak +
        '    border: 1px solid var(--border-color);' + sLineBreak +
        '    background: var(--bg-secondary);' + sLineBreak +
        '    color: var(--text-primary);' + sLineBreak +
        '}' + sLineBreak +
        '' + sLineBreak +
        '.nav-list {' + sLineBreak +
        '    flex: 1;' + sLineBreak +
        '    overflow-y: auto;' + sLineBreak +
        '    padding: 10px;' + sLineBreak +
        '}' + sLineBreak +
        '' + sLineBreak +
        '.nav-item {' + sLineBreak +
        '    display: block;' + sLineBreak +
        '    padding: 8px 12px;' + sLineBreak +
        '    color: var(--text-secondary);' + sLineBreak +
        '    text-decoration: none;' + sLineBreak +
        '    border-radius: 6px;' + sLineBreak +
        '    margin-bottom: 2px;' + sLineBreak +
        '    cursor: pointer;' + sLineBreak +
        '}' + sLineBreak +
        '' + sLineBreak +
        '.nav-item:hover,' + sLineBreak +
        '.nav-item.active {' + sLineBreak +
        '    background: var(--bg-tertiary);' + sLineBreak +
        '    color: var(--text-primary);' + sLineBreak +
        '}' + sLineBreak +
        '' + sLineBreak +
        '/* Main Content */' + sLineBreak +
        '.main-content {' + sLineBreak +
        '    flex: 1;' + sLineBreak +
        '    overflow-y: auto;' + sLineBreak +
        '    padding: 40px;' + sLineBreak +
        '    position: relative;' + sLineBreak +
        '}' + sLineBreak +
        '' + sLineBreak +
        '.header-actions {' + sLineBreak +
        '    position: absolute;' + sLineBreak +
        '    top: 20px;' + sLineBreak +
        '    right: 20px;' + sLineBreak +
        '}' + sLineBreak +
        '' + sLineBreak +
        '.theme-toggle {' + sLineBreak +
        '    background: transparent;' + sLineBreak +
        '    border: 1px solid var(--border-color);' + sLineBreak +
        '    color: var(--text-primary);' + sLineBreak +
        '    padding: 8px;' + sLineBreak +
        '    border-radius: 50%;' + sLineBreak +
        '    cursor: pointer;' + sLineBreak +
        '}' + sLineBreak +
        '' + sLineBreak +
        '/* Content Elements */' + sLineBreak +
        'h1,' + sLineBreak +
        'h2,' + sLineBreak +
        'h3 {' + sLineBreak +
        '    color: var(--text-primary);' + sLineBreak +
        '}' + sLineBreak +
        '' + sLineBreak +
        'h1 {' + sLineBreak +
        '    border-bottom: 2px solid var(--border-color);' + sLineBreak +
        '    padding-bottom: 10px;' + sLineBreak +
        '}' + sLineBreak +
        '' + sLineBreak +
        '.card {' + sLineBreak +
        '    background: var(--bg-secondary);' + sLineBreak +
        '    border: 1px solid var(--border-color);' + sLineBreak +
        '    border-radius: 8px;' + sLineBreak +
        '    padding: 20px;' + sLineBreak +
        '    margin-bottom: 20px;' + sLineBreak +
        '}' + sLineBreak +
        '' + sLineBreak +
        '.code-block {' + sLineBreak +
        '    background: var(--code-bg);' + sLineBreak +
        '    color: var(--code-text);' + sLineBreak +
        '    font-family: var(--font-code);' + sLineBreak +
        '    padding: 15px;' + sLineBreak +
        '    border-radius: 6px;' + sLineBreak +
        '    overflow-x: auto;' + sLineBreak +
        '}' + sLineBreak +
        '' + sLineBreak +
        '.badge {' + sLineBreak +
        '    display: inline-block;' + sLineBreak +
        '    padding: 2px 8px;' + sLineBreak +
        '    border-radius: 12px;' + sLineBreak +
        '    font-size: 0.75rem;' + sLineBreak +
        '    font-weight: bold;' + sLineBreak +
        '    text-transform: uppercase;' + sLineBreak +
        '}' + sLineBreak +
        '' + sLineBreak +
        '.badge-public {' + sLineBreak +
        '    background: #22c55e;' + sLineBreak +
        '    color: #fff;' + sLineBreak +
        '}' + sLineBreak +
        '' + sLineBreak +
        '.badge-private {' + sLineBreak +
        '    background: #ef4444;' + sLineBreak +
        '    color: #fff;' + sLineBreak +
        '}' + sLineBreak +
        '' + sLineBreak +
        '/* Scrollable Mermaid Container */' + sLineBreak +
        '.mermaid-container {' + sLineBreak +
        '    overflow-x: auto;' + sLineBreak +
        '    background: var(--bg-secondary);' + sLineBreak +
        '    padding: 15px;' + sLineBreak +
        '    border-radius: 8px;' + sLineBreak +
        '    border: 1px solid var(--border-color);' + sLineBreak +
        '    margin-bottom: 20px;' + sLineBreak +
        '}' + sLineBreak +
        '' + sLineBreak +
        '.mermaid-container svg {' + sLineBreak +
        '    max-width: none !important;' + sLineBreak +
        '    width: auto !important;' + sLineBreak +
        '}' + sLineBreak +
        '' + sLineBreak +
        '/* Hide raw mermaid text to avoid flash of content */' + sLineBreak +
        '.mermaid {' + sLineBreak +
        '    visibility: hidden;' + sLineBreak +
        '}' + sLineBreak +
        '' + sLineBreak +
        'details.mermaid-details summary {' + sLineBreak +
        '    cursor: pointer;' + sLineBreak +
        '    padding: 10px;' + sLineBreak +
        '    background: var(--bg-tertiary);' + sLineBreak +
        '    border-radius: 6px;' + sLineBreak +
        '    font-weight: bold;' + sLineBreak +
        '    margin-bottom: 10px;' + sLineBreak +
        '    list-style: none;' + sLineBreak +
        '}' + sLineBreak +
        'details.mermaid-details summary::-webkit-details-marker {' + sLineBreak +
        '    display: none;' + sLineBreak +
        '}' + sLineBreak +
        'details.mermaid-details summary::after {' + sLineBreak +
        '    content: "+";' + sLineBreak +
        '    float: right;' + sLineBreak +
        '    font-weight: bold;' + sLineBreak +
        '}' + sLineBreak +
        'details.mermaid-details[open] summary::after {' + sLineBreak +
        '    content: "-";' + sLineBreak +
        '}' + sLineBreak +
        '' + sLineBreak +
        '/* Toggle Text Visibility */' + sLineBreak +
        'details.mermaid-details[open] .expand-text { display: none; }' + sLineBreak +
        'details.mermaid-details:not([open]) .collapse-text { display: none; }' + sLineBreak +
        '' + sLineBreak +
        '/* Specific Overrides for Class/Ancestor visual distinction */' + sLineBreak +
        '.ancestor {' + sLineBreak +
        '    color: var(--text-muted);' + sLineBreak +
        '    font-size: 0.9rem;' + sLineBreak +
        '    margin-bottom: 0.5rem;' + sLineBreak +
        '    font-style: italic;' + sLineBreak +
        '}' + sLineBreak +
        '' + sLineBreak +
        'h3 {' + sLineBreak +
        '    color: var(--accent-color);' + sLineBreak +
        '    font-size: 1.5rem;' + sLineBreak +
        '    margin-top: 1.5rem;' + sLineBreak +
        '    margin-bottom: 0.5rem;' + sLineBreak +
        '}' + sLineBreak +
        '' + sLineBreak +
        '.api-signature {' + sLineBreak +
        '    font-family: var(--font-code);' + sLineBreak +
        '    background: var(--bg-tertiary);' + sLineBreak +
        '    padding: 8px;' + sLineBreak +
        '    border-radius: 4px;' + sLineBreak +
        '    border-left: 3px solid var(--accent-color);' + sLineBreak +
        '    margin-bottom: 8px;' + sLineBreak +
        '}' + sLineBreak +
        '' + sLineBreak +
        '.description {' + sLineBreak +
        '    color: var(--text-secondary);' + sLineBreak +
        '    margin-bottom: 1rem;' + sLineBreak +
        '    line-height: 1.6;' + sLineBreak +
        '}';

      TEMPLATE_HTML = 
        '<!DOCTYPE html>' + sLineBreak +
        '<html lang="en">' + sLineBreak +
        '<head>' + sLineBreak +
        '    <meta charset="UTF-8">' + sLineBreak +
        '    <meta name="viewport" content="width=device-width, initial-scale=1.0">' + sLineBreak +
        '    <title>{{TITLE}} - {{PROJECT_TITLE}}</title>' + sLineBreak +
        '    ' + sLineBreak +
        '    <!-- Blocking script to avoid theme flicker --> ' + sLineBreak +
        '    <script>' + sLineBreak +
        '        (function() {' + sLineBreak +
        '            const storedTheme = localStorage.getItem(''dext-theme'') || ''dark'';' + sLineBreak +
        '            document.documentElement.setAttribute(''data-theme'', storedTheme);' + sLineBreak +
        '        })();' + sLineBreak +
        '    </script>' + sLineBreak +
        '    ' + sLineBreak +
        '    <!-- Theme & Layout (Separate files for internal Dext Tooling) -->' + sLineBreak +
        '    <link rel="stylesheet" href="theme.css">' + sLineBreak +
        '    <link rel="stylesheet" href="layout.css">' + sLineBreak +
        '    ' + sLineBreak +
        '    <!-- Mermaid for Diagrams -->' + sLineBreak +
        '    <script src="https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.min.js"></script>' + sLineBreak +
        '</head>' + sLineBreak +
        '<body>' + sLineBreak +
        '    <div class="sidebar">' + sLineBreak +
        '        <div class="sidebar-header">' + sLineBreak +
        '            <h3>{{PROJECT_TITLE}}</h3>' + sLineBreak +
        '            <small>Documentation</small>' + sLineBreak +
        '        </div>' + sLineBreak +
        '        <div class="search-box">' + sLineBreak +
        '            <input type="text" class="search-input" placeholder="Search API..." id="searchInput">' + sLineBreak +
        '        </div>' + sLineBreak +
        '        <div class="nav-list" id="navList">' + sLineBreak +
        '            <!-- Sidebar Content Loaded Dynamically via toc.json -->' + sLineBreak +
        '        </div>' + sLineBreak +
        '    </div>' + sLineBreak +
        '' + sLineBreak +
        '    <div class="main-content">' + sLineBreak +
        '        <div class="header-actions">' + sLineBreak +
        '            <button class="theme-toggle" id="themeToggle" title="Toggle Dark/Light Mode">&#x1F313;</button>' + sLineBreak +
        '        </div>' + sLineBreak +
        '        ' + sLineBreak +
        '        <div id="contentArea">' + sLineBreak +
        '            <!-- Main Documentation Content Injected Here -->' + sLineBreak +
        '            {{MAIN_CONTENT}}' + sLineBreak +
        '        </div>' + sLineBreak +
        '    </div>' + sLineBreak +
        '' + sLineBreak +
        '    <script src="toc.js"></script>' + sLineBreak +
        '    <script src="viewer.js"></script>' + sLineBreak +
        '</body>' + sLineBreak +
        '</html>';

      VIEWER_JS = 
        '// Client-Side Logic for Dext Documentation' + sLineBreak +
        'document.addEventListener(''DOMContentLoaded'', () => {' + sLineBreak +
        '    ' + sLineBreak +
        '    // 1. Theme Toggling' + sLineBreak +
        '    const themeToggle = document.getElementById(''themeToggle'');' + sLineBreak +
        '    const storedTheme = localStorage.getItem(''dext-theme'') || ''dark'';' + sLineBreak +
        '    document.documentElement.setAttribute(''data-theme'', storedTheme);' + sLineBreak +
        '' + sLineBreak +
        '    themeToggle.addEventListener(''click'', () => {' + sLineBreak +
        '        const currentTheme = document.documentElement.getAttribute(''data-theme'');' + sLineBreak +
        '        const newTheme = currentTheme === ''dark'' ? ''light'' : ''dark'';' + sLineBreak +
        '        ' + sLineBreak +
        '        document.documentElement.setAttribute(''data-theme'', newTheme);' + sLineBreak +
        '        localStorage.setItem(''dext-theme'', newTheme);' + sLineBreak +
        '    });' + sLineBreak +
        '' + sLineBreak +
        '    // 2. Load TOC dynamically from window.DEXT_TOC' + sLineBreak +
        '    const navList = document.getElementById(''navList'');' + sLineBreak +
        '    const searchInput = document.getElementById(''searchInput'');' + sLineBreak +
        '    const currentFile = window.location.pathname.split(''/'').pop() || ''index.html'';' + sLineBreak +
        '    const items = window.DEXT_TOC || [];' + sLineBreak +
        '' + sLineBreak +
        '    if (navList) {' + sLineBreak +
        '        navList.innerHTML = '''';' + sLineBreak +
        '        items.forEach(item => {' + sLineBreak +
        '            const a = document.createElement(''a'');' + sLineBreak +
        '            a.href = item.file;' + sLineBreak +
        '            a.className = ''nav-item'';' + sLineBreak +
        '            if (item.file === currentFile) {' + sLineBreak +
        '                a.classList.add(''active'');' + sLineBreak +
        '            }' + sLineBreak +
        '            a.textContent = item.name;' + sLineBreak +
        '            navList.appendChild(a);' + sLineBreak +
        '        });' + sLineBreak +
        '' + sLineBreak +
        '        // Index page unit list container if present' + sLineBreak +
        '        const indexListGroup = document.getElementById(''indexUnitList'');' + sLineBreak +
        '        if (indexListGroup) {' + sLineBreak +
        '            indexListGroup.innerHTML = navList.innerHTML;' + sLineBreak +
        '        }' + sLineBreak +
        '    }' + sLineBreak +
        '' + sLineBreak +
        '    // 3. Search Functionality' + sLineBreak +
        '    if (searchInput) {' + sLineBreak +
        '        searchInput.addEventListener(''input'', (e) => {' + sLineBreak +
        '            const term = e.target.value.toLowerCase();' + sLineBreak +
        '            const navItems = document.querySelectorAll(''.nav-item'');' + sLineBreak +
        '            navItems.forEach(item => {' + sLineBreak +
        '                const text = item.textContent.toLowerCase();' + sLineBreak +
        '                if (text.includes(term)) {' + sLineBreak +
        '                    item.style.display = ''block'';' + sLineBreak +
        '                } else {' + sLineBreak +
        '                    item.style.display = ''none'';' + sLineBreak +
        '                }' + sLineBreak +
        '            });' + sLineBreak +
        '        });' + sLineBreak +
        '    }' + sLineBreak +
        '' + sLineBreak +
        '    // 4. Initialize Mermaid Manually to fix SVG sizing' + sLineBreak +
        '    mermaid.initialize({ ' + sLineBreak +
        '        startOnLoad: false, ' + sLineBreak +
        '        "class": { useMaxWidth: false },' + sLineBreak +
        '        theme: document.documentElement.getAttribute(''data-theme'') === ''dark'' ? ''dark'' : ''default'' ' + sLineBreak +
        '    });' + sLineBreak +
        '' + sLineBreak +
        '    mermaid.run().then(() => {' + sLineBreak +
        '        document.querySelectorAll(''.mermaid-container svg'').forEach(svg => {' + sLineBreak +
        '             const viewBox = svg.getAttribute("viewBox");' + sLineBreak +
        '             if (viewBox) {' + sLineBreak +
        '                 const parts = viewBox.split(" ");' + sLineBreak +
        '                 const width = parts[2];' + sLineBreak +
        '                 const height = parts[3];' + sLineBreak +
        '                 svg.style.width = width + "px";' + sLineBreak +
        '                 svg.style.height = height + "px";' + sLineBreak +
        '             }' + sLineBreak +
        '             svg.style.maxWidth = "none";' + sLineBreak +
        '             svg.removeAttribute("width");' + sLineBreak +
        '        });' + sLineBreak +
        '        ' + sLineBreak +
        '        document.querySelectorAll(''.mermaid'').forEach(el => el.style.visibility = ''visible'');' + sLineBreak +
        '    });' + sLineBreak +
        '});';

  public
    function GetName: string;
    function GetDescription: string;
    procedure Execute(const Args: TCommandLineArgs);
  end;

implementation

// YAML Helper Functions
function UnescapeYamlString(const S: string): string;
var
  Trimmed: string;
begin
  Trimmed := S.Trim;
  if Trimmed.StartsWith('"') and Trimmed.EndsWith('"') then
  begin
    Trimmed := Trimmed.Substring(1, Trimmed.Length - 2);
    Result := Trimmed.Replace('\"', '"').Replace('\\', '\');
  end
  else if Trimmed.StartsWith('''') and Trimmed.EndsWith('''') then
  begin
    Trimmed := Trimmed.Substring(1, Trimmed.Length - 2);
    Result := Trimmed.Replace('''''', '''');
  end
  else
    Result := Trimmed;
end;

procedure LoadYamlConfig(const AFileName: string; out ATitle, ASearchPath, AOutputPath, ALastRun: string;
  out AOnlyProjectFiles: Boolean; const ASelectedFiles: TStrings);
var
  Lines: TStringList;
  I: Integer;
  Line: string;
  Key, Val: string;
  ColonPos: Integer;
  InSelectedFiles: Boolean;
  Content: string;
  JSON: TJSONObject;
  FilesArr: TJSONArray;
begin
  ATitle := '';
  ASearchPath := '';
  AOutputPath := '';
  AOnlyProjectFiles := True;
  ALastRun := '';
  if ASelectedFiles <> nil then
    ASelectedFiles.Clear;

  if not TFile.Exists(AFileName) then Exit;

  Content := TFile.ReadAllText(AFileName, TEncoding.UTF8).Trim;
  if Content.StartsWith('{') then
  begin
    try
      JSON := TJSONObject.ParseJSONValue(Content) as TJSONObject;
      if JSON <> nil then
      begin
        try
          if JSON.GetValue('title') <> nil then
            ATitle := JSON.GetValue('title').Value;
          if JSON.GetValue('search_path') <> nil then
            ASearchPath := JSON.GetValue('search_path').Value;
          if JSON.GetValue('output_path') <> nil then
            AOutputPath := JSON.GetValue('output_path').Value;
          if JSON.GetValue('only_project_files') <> nil then
            AOnlyProjectFiles := JSON.GetValue('only_project_files').Value.ToBoolean;
          if JSON.GetValue('last_run') <> nil then
            ALastRun := JSON.GetValue('last_run').Value;
            
          if JSON.GetValue('selected_files') <> nil then
            FilesArr := JSON.GetValue('selected_files') as TJSONArray
          else
            FilesArr := nil;
            
          if (FilesArr <> nil) and (ASelectedFiles <> nil) then
          begin
            for I := 0 to FilesArr.Count - 1 do
              ASelectedFiles.Add(FilesArr.Items[I].Value);
          end;
        finally
          JSON.Free;
        end;
      end;
    except
      // Ignore JSON parsing errors in fallback
    end;
    Exit;
  end;

  Lines := TStringList.Create;
  try
    Lines.Text := Content;
    InSelectedFiles := False;
    
    for I := 0 to Lines.Count - 1 do
    begin
      Line := Lines[I];
      
      if Line.Trim.IsEmpty or Line.Trim.StartsWith('#') then
        Continue;
        
      if InSelectedFiles then
      begin
        if not Line.StartsWith('  - ') and not Line.StartsWith('    - ') and (Line.Contains(':') or not Line.StartsWith(' ')) then
          InSelectedFiles := False;
      end;

      if InSelectedFiles then
      begin
        Val := Line.Trim;
        if Val.StartsWith('- ') then
        begin
          Val := Val.Substring(2);
          if ASelectedFiles <> nil then
            ASelectedFiles.Add(UnescapeYamlString(Val));
          Continue;
        end;
      end;
      
      ColonPos := Line.IndexOf(':');
      if ColonPos > 0 then
      begin
        Key := Line.Substring(0, ColonPos).Trim.ToLower;
        Val := Line.Substring(ColonPos + 1).Trim;
        
        if Key = 'title' then
          ATitle := UnescapeYamlString(Val)
        else if Key = 'search_path' then
          ASearchPath := UnescapeYamlString(Val)
        else if Key = 'output_path' then
          AOutputPath := UnescapeYamlString(Val)
        else if Key = 'only_project_files' then
          AOnlyProjectFiles := Val.ToLower = 'true'
        else if Key = 'last_run' then
          ALastRun := UnescapeYamlString(Val)
        else if Key = 'selected_files' then
          InSelectedFiles := True;
      end;
    end;
  finally
    Lines.Free;
  end;
end;

{ TDocCommand }

function TDocCommand.GetName: string;
begin
  Result := 'doc';
end;

function TDocCommand.GetDescription: string;
begin
  Result := 'Generates static HTML documentation for the project (SSG).';
end;

procedure TDocCommand.Execute(const Args: TCommandLineArgs);
var
  InputDir, OutputDir, Title: string;
  Generator: TDextDocGenerator;
  ConfigPath: string;
  FilesToParse: TStringList;
  LoadedLastRun: string;
  LoadedOnlyProject: Boolean;
begin
  // 1. Parse Default Arguments
  if Args.HasOption('input') then
    InputDir := Args.GetOption('input')
  else if Args.Values.Count > 0 then
    InputDir := Args.Values[0] // Assume first pos arg is input
  else
    InputDir := GetCurrentDir;

  if Args.HasOption('output') then
    OutputDir := Args.GetOption('output')
  else
    OutputDir := TPath.Combine(InputDir, 'Docs/Output');
    
  if Args.HasOption('title') then
    Title := Args.GetOption('title')
  else
    Title := 'Dext Framework';

  // 2. Parse Config file if provided
  FilesToParse := nil;
  if Args.HasOption('config') then
  begin
    ConfigPath := Args.GetOption('config');
    if TFile.Exists(ConfigPath) then
    begin
      try
        FilesToParse := TStringList.Create;
        LoadYamlConfig(ConfigPath, Title, InputDir, OutputDir, LoadedLastRun, LoadedOnlyProject, FilesToParse);
        
        // If files list is empty in the config, we free the list so it parses all files
        if FilesToParse.Count = 0 then
        begin
          FreeAndNil(FilesToParse);
        end;
      except
        on E: Exception do
          SafeWriteLn('Error parsing config file: ' + E.Message);
      end;
    end
    else
      SafeWriteLn('Warning: Config file not found: ' + ConfigPath);
  end;
    
  // A relative name such as 'docs' made ForceDirectories fail; work with
  // full paths from here on.
  InputDir := TPath.GetFullPath(InputDir);
  OutputDir := TPath.GetFullPath(OutputDir);

  SafeWriteLn('Generating Documentation...');
  SafeWriteLn('Input: ' + InputDir);
  SafeWriteLn('Output: ' + OutputDir);
  SafeWriteLn('Title: ' + Title);
  if FilesToParse <> nil then
    SafeWriteLn('Selected Files: ' + IntToStr(FilesToParse.Count))
  else
    SafeWriteLn('Selected Files: All in Input directory');
  
  ForceDirectories(OutputDir);

  // 3. Write Static Assets
  SafeWriteLn('Writing static assets...');
  TFile.WriteAllText(TPath.Combine(OutputDir, 'theme.css'), THEME_CSS);
  TFile.WriteAllText(TPath.Combine(OutputDir, 'layout.css'), LAYOUT_CSS);
  TFile.WriteAllText(TPath.Combine(OutputDir, 'viewer.js'), VIEWER_JS);
  
  // 4. Generate Documentation
  SafeWriteLn('Parsing source and generating HTML...');
  Generator := TDextDocGenerator.Create(TEMPLATE_HTML, OutputDir, Title);
  try
    Generator.Generate(InputDir, FilesToParse);
  finally
    Generator.Free;
    FilesToParse.Free;
  end;
  
  SafeWriteLn('Success! Open ' + TPath.Combine(OutputDir, 'index.html'));
end;

end.
