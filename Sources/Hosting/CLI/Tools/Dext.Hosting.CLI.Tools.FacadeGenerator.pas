unit Dext.Hosting.CLI.Tools.FacadeGenerator;

interface

uses
  System.Classes,
  System.IOUtils,
  System.Math,
  System.StrUtils,
  System.SysUtils,
  Dext.Collections,
  Dext.Collections.HashSet,
  Dext.Collections.Comparers,
  DelphiAST.Classes,
  DelphiAST.Consts,
  DelphiAST,
  Dext.Utils;

type
  TOrdinalIgnoreCaseComparer = class(TInterfacedObject, IEqualityComparer<string>)
  public
    function Equals(const Left, Right: string): Boolean; reintroduce;
    function GetHashCode(const Value: string): Integer; reintroduce;
  end;

  TExtractedUnit = class
  public
    UnitName: string;
    Types: IList<string>;
    GenericTypes: IList<string>; 
    Consts: IList<string>;
    Helpers: IList<string>;
    constructor Create(const AName: string);
    destructor Destroy; override;
  end;

  TFacadeGenerator = class
  private
    FTargetUnitName: string;
    FSkippedUnits: IList<string>;
    FProcessedUnits: Integer;
    function IsFieldName(const AName: string): Boolean;
    function IsUnitProcessed(const UnitName: string): Boolean;
  protected
    FSourcePath: string;
    FSearchPattern: string;
    FExcludedUnits: IHashSet<string>;
    FParsedUnits: IList<TExtractedUnit>;
    FGlobalTypeNames: IHashSet<string>; 
    
    // Configuration
    FStartAliasTag: string;
    FEndAliasTag: string;
    FStartUsesTag: string;
    FEndUsesTag: string;
    FValidateTags: Boolean;
    FVerbose: Boolean;
    
    // Stats
    FTotalTypes: Integer;
    FTotalConsts: Integer;
    
    procedure ScanFolder(const Folder: string);
    procedure ProcessFile(const FileName: string); virtual;
    function IsExcluded(const UnitName: string): Boolean;
    function IsGeneric(Node: TSyntaxNode): Boolean;
    function GetUnitName(Root: TSyntaxNode; const FileName: string): string;
  public
    property ParsedUnits: IList<TExtractedUnit> read FParsedUnits;
    constructor Create(const SourcePath, Wildcard: string; const Excluded: TArray<string>);
    destructor Destroy; override;
    procedure Execute; virtual;
    procedure InjectIntoFile(const TargetFile: string; DryRun: Boolean = False);
    procedure BackupTargetFile(const FileName: string);
    
    property StartAliasTag: string read FStartAliasTag write FStartAliasTag;
    property EndAliasTag: string read FEndAliasTag write FEndAliasTag;
    property StartUsesTag: string read FStartUsesTag write FStartUsesTag;
    property EndUsesTag: string read FEndUsesTag write FEndUsesTag;
    property ValidateTags: Boolean read FValidateTags write FValidateTags;
    property Verbose: Boolean read FVerbose write FVerbose;
    property TargetUnitName: string read FTargetUnitName write FTargetUnitName;
  end;

implementation

{ TOrdinalIgnoreCaseComparer }

function TOrdinalIgnoreCaseComparer.Equals(const Left, Right: string): Boolean;
begin
  Result := SameText(Left, Right);
end;

function TOrdinalIgnoreCaseComparer.GetHashCode(const Value: string): Integer;
begin
  Result := TEqualityComparer<string>.Default.GetHashCode(UpperCase(Value));
end;

{ TExtractedUnit }

constructor TExtractedUnit.Create(const AName: string);
begin
  UnitName := AName;
  Types := TCollections.CreateList<string>;
  GenericTypes := TCollections.CreateList<string>;
  Consts := TCollections.CreateList<string>;
  Helpers := TCollections.CreateList<string>;
end;

destructor TExtractedUnit.Destroy;
begin
  inherited;
end;

{ TFacadeGenerator }

constructor TFacadeGenerator.Create(const SourcePath, Wildcard: string; const Excluded: TArray<string>);
var
  S: string;
begin
  FSourcePath := SourcePath;
  FSearchPattern := Wildcard;
  FExcludedUnits := TCollections.CreateHashSet<string>;
  FGlobalTypeNames := TCollections.CreateHashSet<string>; 
  for S in Excluded do
    FExcludedUnits.Add(S);
    
  FParsedUnits := TCollections.CreateList<TExtractedUnit>(True);
  FSkippedUnits := TCollections.CreateList<string>;
  FProcessedUnits := 0;
  
  // Defaults
  FStartAliasTag := '// {BEGIN_DEXT_ALIASES}';
  FEndAliasTag := '// {END_DEXT_ALIASES}';
  FStartUsesTag := '// {BEGIN_DEXT_USES}';
  FEndUsesTag := '// {END_DEXT_USES}';
  FValidateTags := True;
  FVerbose := False;
  FTotalTypes := 0;
  FTotalConsts := 0;
end;

destructor TFacadeGenerator.Destroy;
begin
  // All collections are ARC managed
  inherited;
end;

function TFacadeGenerator.IsFieldName(const AName: string): Boolean;
begin
  Result := (Length(AName) >= 2) and 
            (AName[1] = 'F') and 
            CharInSet(AName[2], ['A'..'Z']);
end;

function TFacadeGenerator.IsGeneric(Node: TSyntaxNode): Boolean;
begin
  Result := Node.FindNode(ntTypeParams) <> nil;
end;

function TFacadeGenerator.GetUnitName(Root: TSyntaxNode; const FileName: string): string;
begin
  if (Root <> nil) and (Root.Typ = ntUnit) then
    Result := Root.GetAttribute(anName)
  else
    Result := '';
    
  if Result = '' then
    Result := TPath.GetFileNameWithoutExtension(FileName);
end;

function TFacadeGenerator.IsExcluded(const UnitName: string): Boolean;
begin
  Result := FExcludedUnits.Contains(UnitName);
end;

function TFacadeGenerator.IsUnitProcessed(const UnitName: string): Boolean;
var
  U: TExtractedUnit;
begin
  Result := False;
  for U in FParsedUnits do
    if SameText(U.UnitName, UnitName) then Exit(True);
end;

procedure TFacadeGenerator.Execute;
begin
  if (FTargetUnitName <> '') and (not FExcludedUnits.Contains(FTargetUnitName)) then
  begin
     FExcludedUnits.Add(FTargetUnitName);
     if FVerbose then SafeWriteLn('Auto-excluded target unit: ' + FTargetUnitName);
  end;

  ScanFolder(FSourcePath);
  
  if FVerbose then
  begin
    SafeWriteLn('Statistics:');
    SafeWriteLn(Format('  Units Processed: %d', [FProcessedUnits]));
    SafeWriteLn(Format('  Types Found    : %d', [FTotalTypes]));
    SafeWriteLn(Format('  Consts Found   : %d', [FTotalConsts]));
  end;
end;

procedure TFacadeGenerator.ScanFolder(const Folder: string);
var
  FileName: string;
  SubFolder: string;
begin
  for FileName in TDirectory.GetFiles(Folder, FSearchPattern) do
  begin
    ProcessFile(FileName);
  end;

  for SubFolder in TDirectory.GetDirectories(Folder) do
  begin
    ScanFolder(SubFolder);
  end;
end;

procedure TFacadeGenerator.ProcessFile(const FileName: string);
var
  Root, IntfNode, SectionNode, DeclNode: TSyntaxNode;
  UnitName, TypeName: string;
  UnitDecl: TExtractedUnit;
  GenericParams: string;
  FoundElements: Boolean;
  StandardEnumNode: TSyntaxNode;
  TypeWrapper: TSyntaxNode;
  IdCount: Integer;
  C: TSyntaxNode;
  ConstName: string;
  
  function IsHelper(Decl: TSyntaxNode): Boolean;
  var
    TypeNode: TSyntaxNode;
  begin
    TypeNode := Decl.FindNode(ntType);
    Result := (TypeNode <> nil) and (TypeNode.FindNode(ntHelper) <> nil);
  end;

  function IsValidType(Name: string): Boolean;
  begin
     Result := True;
     if MatchStr(Name, ['type', 'const', 'var', 'class', 'interface', 'record', 'end']) then Exit(False);
     if IsFieldName(Name) then Exit(False);
  end;

  // Robust search for Enum Elements anywhere in sub-tree of TypeDecl
  procedure ScanForElements(UnitDecl: TExtractedUnit; N: TSyntaxNode; const TypeName: string; var FoundElements: Boolean);
  var
    EnumItemName: string;
    C: TSyntaxNode;
  begin
     if N = nil then Exit;
     
     // User says ntElement (32), Debugger says ntIdentifier (56) inside ntType (114)
     // We accept both to be safe. 
     if (N.Typ = ntElement) or (Ord(N.Typ) = 56) then // 56 = ntIdentifier
     begin
         // Check if it's the TypeName itself (DeclNode name) to avoid self-reference? 
         EnumItemName := N.GetAttribute(anName);
         if (not EnumItemName.IsEmpty) and (not FGlobalTypeNames.Contains(EnumItemName)) and (EnumItemName <> TypeName) then
         begin
            if not UnitDecl.Consts.Contains(EnumItemName) then
            begin
               UnitDecl.Consts.Add(EnumItemName);
               FGlobalTypeNames.Add(EnumItemName);
               Inc(FTotalConsts);
            end;
            FoundElements := True;
         end;
     end;
     
     for C in N.ChildNodes do
       ScanForElements(UnitDecl, C, TypeName, FoundElements);
  end;
  
begin
  if TPath.GetFileName(FileName).StartsWith('.') then Exit;
  if TPath.GetFileName(FileName).Contains('.Aliases.inc') then Exit;
  if TPath.GetFileName(FileName).Contains('.Uses.inc') then Exit;
  
  if TPath.GetFileName(FileName).Contains('.Uses.inc') then Exit;
  
  if FVerbose then
    SafeWriteLn('Processing: ' + FileName); // Log FULL PATH to check case/format
  Inc(FProcessedUnits);

  Root := nil;
  try
    try
      Root := TPasSyntaxTreeBuilder.Run(FileName);
    except
      on E: Exception do
      begin
        SafeWriteLn('Error parsing ' + FileName + ': ' + E.Message);
        Exit;
      end;
    end;

    if Root = nil then 
    begin
       safeWriteLn('DEBUG: Root is nil for ' + FileName);
     Exit;
    end;

    UnitName := GetUnitName(Root, FileName);
    if IsExcluded(UnitName) then 
    begin
      SafeWriteLn('  Excluded: ' + UnitName);
      Exit;
    end;

    if IsUnitProcessed(UnitName) then
    begin
       SafeWriteLn('  Duplicate unit skipped: ' + UnitName);
       Exit;
    end;

    UnitDecl := TExtractedUnit.Create(UnitName);
    
    IntfNode := Root.FindNode(ntInterface);
    if IntfNode <> nil then
    begin

      for SectionNode in IntfNode.ChildNodes do
      begin
        if SectionNode.Typ = ntTypeSection then
        begin

          for DeclNode in SectionNode.ChildNodes do
          begin
            if DeclNode.Typ = ntTypeDecl then
            begin
              TypeName := DeclNode.GetAttribute(anName);

              if TypeName.IsEmpty then Continue;
              if not IsValidType(TypeName) then Continue;

              // An alias of a helper does not activate the helper in Delphi
              if IsHelper(DeclNode) then
              begin
                if not UnitDecl.Helpers.Contains(TypeName) then
                  UnitDecl.Helpers.Add(TypeName);
                Continue;
              end;

              if IsGeneric(DeclNode) then 
              begin
                 GenericParams := '<T>'; 
                 UnitDecl.GenericTypes.Add(TypeName + GenericParams); 
                 Continue;
              end;
              
              if FGlobalTypeNames.Contains(TypeName) then
              begin
                 Continue;
              end;
              
              if not UnitDecl.Types.Contains(TypeName) then
              begin
                UnitDecl.Types.Add(TypeName);
                FGlobalTypeNames.Add(TypeName);
                Inc(FTotalTypes);
              end;

              // Robust search for Enum Elements anywhere in sub-tree of TypeDecl
              FoundElements := False;
              
              // Only scan if we suspect it is an enum? 
              // Hard to know without ntEnum node.
              // But extracting constants from other types (like Aliases) is not desired.
              // TMyInt = Integer; -> Integer is ntIdentifier. We don't want "const Integer = ...".
              
              // Heuristic: If we find ntEnum, scan only children.
              // If we find ntType (114) and it has MULTIPLE identifiers, it's likely an Enum.
              // If it has ONE identifier, it's likely an Alias.
              
              // Let's look for known structure ntEnum first.
              StandardEnumNode := DeclNode.FindNode(ntEnum);
              if StandardEnumNode = nil then
              begin
                  TypeWrapper := DeclNode.FindNode(ntType);
                  if TypeWrapper <> nil then
                     StandardEnumNode := TypeWrapper.FindNode(ntEnum);
              end;
              
              if StandardEnumNode <> nil then
              begin
                 ScanForElements(UnitDecl, StandardEnumNode, TypeName, FoundElements);
              end
              else 
              begin
                 // If no ntEnum found, fallback to ntType container with heuristics?
                 // TCascadeAction = (caNoAction, ...) -> 4 items.
                 // If we see > 1 identifier inside ntType, treat as Enum.
                 TypeWrapper := DeclNode.FindNode(ntType);
                 if (TypeWrapper <> nil) then
                 begin
                     // Count identifiers
                     IdCount := 0;
                     for C in TypeWrapper.ChildNodes do
                        if Ord(C.Typ) = 56 then Inc(IdCount);
                        
                     if IdCount > 1 then
                        ScanForElements(UnitDecl, TypeWrapper, TypeName, FoundElements);
                 end;
              end;
            end;
          end;
        end
        else if SectionNode.Typ = ntConstants then
        begin
           for DeclNode in SectionNode.ChildNodes do
           begin
             if DeclNode.Typ = ntConstant then
             begin
               ConstName := DeclNode.GetAttribute(anName);
               
               if ConstName.IsEmpty then Continue;
               
               if FGlobalTypeNames.Contains(ConstName) then Continue;
               
               if not UnitDecl.Consts.Contains(ConstName) then
               begin
                 UnitDecl.Consts.Add(ConstName);
                 FGlobalTypeNames.Add(ConstName);
               end;
             end;
           end;
        end;
      end;
    end;

    if (UnitDecl.Types.Count > 0) or (UnitDecl.Consts.Count > 0) or (UnitDecl.GenericTypes.Count > 0) or
      (UnitDecl.Helpers.Count > 0) then
      FParsedUnits.Add(UnitDecl)
    else
      UnitDecl.Free;

  finally
    Root.Free;
  end;
end;



procedure TFacadeGenerator.InjectIntoFile(const TargetFile: string; DryRun: Boolean);
var
  Lines: TStringList;
  NewLines: TStringList;
  I: Integer;
  InAliasesBlock, InUsesBlock: Boolean;
  Trimmed: string;
  
  TargetUnitName: string;
  
  procedure AddAliases;
  var
    LUnitInfo: TExtractedUnit;
    LTypeName: string;
    LConstName: string;
    LGenericName: string;
    HasConsts: Boolean;
  begin
    NewLines.Add('  // Generated Aliases');
    
    FParsedUnits.Sort(TComparer<TExtractedUnit>.Construct(
      function(const L, R: TExtractedUnit): Integer
      begin
        Result := CompareText(L.UnitName, R.UnitName);
      end
    ));

    for LUnitInfo in FParsedUnits do
    begin
      if SameText(LUnitInfo.UnitName, TargetUnitName) then Continue;

      if LUnitInfo.Types.Count > 0 then
      begin
        NewLines.Add('');
        NewLines.Add('  // ' + LUnitInfo.UnitName);
        for LTypeName in LUnitInfo.Types do
        begin
          if LTypeName.IsEmpty then Continue;
          NewLines.Add(Format('  %s = %s.%s;', [LTypeName, LUnitInfo.UnitName, LTypeName]));
        end;
      end;
      
      if LUnitInfo.GenericTypes.Count > 0 then
      begin
         if LUnitInfo.Types.Count = 0 then 
         begin
            NewLines.Add('');
            NewLines.Add('  // ' + LUnitInfo.UnitName);
         end;
         for LGenericName in LUnitInfo.GenericTypes do
           NewLines.Add(Format('  // %s = %s.%s;', [LGenericName, LUnitInfo.UnitName, LGenericName]));
      end;

      if LUnitInfo.Helpers.Count > 0 then
      begin
         if (LUnitInfo.Types.Count = 0) and (LUnitInfo.GenericTypes.Count = 0) then
         begin
            NewLines.Add('');
            NewLines.Add('  // ' + LUnitInfo.UnitName);
         end;
         for LTypeName in LUnitInfo.Helpers do
           NewLines.Add(Format('  // %s is a helper: an alias would not activate it, declare a delegating helper in this unit', [LTypeName]));
      end;
    end;
    
    HasConsts := False;
    for LUnitInfo in FParsedUnits do 
    begin
       if SameText(LUnitInfo.UnitName, TargetUnitName) then Continue;
       if LUnitInfo.Consts.Count > 0 then HasConsts := True;
    end;
    
    if HasConsts then
    begin
        NewLines.Add('');
        NewLines.Add('const');
        for LUnitInfo in FParsedUnits do
        begin
          if SameText(LUnitInfo.UnitName, TargetUnitName) then Continue;

          if LUnitInfo.Consts.Count > 0 then
          begin
             NewLines.Add('  // ' + LUnitInfo.UnitName);
             for LConstName in LUnitInfo.Consts do
             begin
                if LConstName.IsEmpty then Continue;
                NewLines.Add(Format('  %s = %s.%s;', [LConstName, LUnitInfo.UnitName, LConstName]));
             end;
          end;
        end;
    end;
  end;
  
  procedure AddUses;
  var
    LUnitInfo: TExtractedUnit;
    LUnits: IList<string>;
    i: Integer;
  begin
      NewLines.Add('  // Generated Uses');
      LUnits := TCollections.CreateList<string>;
      for LUnitInfo in FParsedUnits do
        begin
           if SameText(LUnitInfo.UnitName, TargetUnitName) then Continue;

           if (LUnitInfo.Types.Count > 0) or (LUnitInfo.Consts.Count > 0) or (LUnitInfo.GenericTypes.Count > 0) then
              LUnits.Add(LUnitInfo.UnitName);
        end;
        
        for i := 0 to LUnits.Count - 1 do
        begin
          if i < LUnits.Count - 1 then
            NewLines.Add('  ' + LUnits[i] + ',')
          else
            NewLines.Add('  ' + LUnits[i]);
        end;
  end;
  
begin
  if not TFile.Exists(TargetFile) then
  begin
    SafeWriteLn('Target file not found: ' + TargetFile);
    Exit;
  end;
  
  if DryRun then
    SafeWriteLn('[DRY RUN] Would inject code into: ' + TargetFile);
    
  TargetUnitName := TPath.GetFileNameWithoutExtension(TargetFile);
  
  Lines := TStringList.Create;
  NewLines := TStringList.Create;
  try
    Lines.LoadFromFile(TargetFile);
    
    // Validation
    if FValidateTags then
    begin
       if (not Lines.Text.Contains(FStartAliasTag)) or (not Lines.Text.Contains(FEndAliasTag)) then
         raise Exception.CreateFmt('Alias delimiters not found in %s.' + sLineBreak + 
           'Expected "%s" and "%s".', [TargetFile, FStartAliasTag, FEndAliasTag]);
           
       if (not Lines.Text.Contains(FStartUsesTag)) or (not Lines.Text.Contains(FEndUsesTag)) then
         raise Exception.CreateFmt('Uses delimiters not found in %s.' + sLineBreak + 
           'Expected "%s" and "%s".', [TargetFile, FStartUsesTag, FEndUsesTag]);
    end;
    
    InAliasesBlock := False;
    InUsesBlock := False;
    
    for I := 0 to Lines.Count - 1 do
    begin
      Trimmed := Trim(Lines[I]);
      
      if Trimmed.StartsWith(FStartAliasTag) then
      begin
         NewLines.Add(Lines[I]);
         AddAliases;
         InAliasesBlock := True;
         Continue;
      end;
      
      if Trimmed.StartsWith(FEndAliasTag) then
      begin
         NewLines.Add(Lines[I]);
         InAliasesBlock := False;
         Continue;
      end;
      
      if Trimmed.StartsWith(FStartUsesTag) then
      begin
         NewLines.Add(Lines[I]);
         AddUses;
         InUsesBlock := True;
         Continue;
      end;
      
      if Trimmed.StartsWith(FEndUsesTag) then
      begin
         NewLines.Add(Lines[I]);
         InUsesBlock := False;
         Continue;
      end;
      
      if not InAliasesBlock and not InUsesBlock then
         NewLines.Add(Lines[I]);
    end;
    
    if not DryRun then
    begin
      NewLines.SaveToFile(TargetFile);
      SafeWriteLn('Injected code into ' + TargetFile);
    end
    else
    begin
       SafeWriteLn('[DRY RUN] Content preview (first 10 lines):');
       for I := 0 to Min(9, NewLines.Count - 1) do
         SafeWriteLn('  ' + NewLines[I]);
       SafeWriteLn('  ...');
    end;
    
  finally
    Lines.Free;
    NewLines.Free;
  end;
end;



procedure TFacadeGenerator.BackupTargetFile(const FileName: string);
var
  BackupFile: string;
begin
  BackupFile := FileName + '.bak';
  if TFile.Exists(BackupFile) then
    TFile.Delete(BackupFile);
  TFile.Copy(FileName, BackupFile);
  SafeWriteLn('Backup created: ' + BackupFile);
end;

end.
