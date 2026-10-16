unit Dext.Testing.Design.AST;

interface

uses
  System.SysUtils,
  System.Classes,
  System.RegularExpressions,
  System.Generics.Collections;

type
  TTestLocation = record
    ClassName: string;
    MethodName: string;
    Line: Integer;
    FileName: string;
  end;

  TTestASTScanner = class
  public
    class function ScanFile(const AFileName: string; out ATests: TList<TTestLocation>): Boolean; overload;
    class function ScanText(const AText: string; out ATests: TList<TTestLocation>): Boolean; overload;
    /// <summary>C++: DUnit TTestCase + Google Test TEST/TEST_F/TEST_P.</summary>
    class function ScanCppText(const AText: string; out ATests: TList<TTestLocation>): Boolean;
  end;

implementation

{ TTestASTScanner }

class function TTestASTScanner.ScanFile(const AFileName: string; out ATests: TList<TTestLocation>): Boolean;
var
  Ext: string;
  FileContent: string;
  Stream: TStringList;
  i: Integer;
  Test: TTestLocation;
begin
  Result := False;
  ATests := TList<TTestLocation>.Create;
  if not FileExists(AFileName) then
    Exit;

  Stream := TStringList.Create;
  try
    try
      Stream.LoadFromFile(AFileName);
      FileContent := Stream.Text;
      Ext := ExtractFileExt(AFileName);
      if SameText(Ext, '.cpp') or SameText(Ext, '.h') or SameText(Ext, '.hpp') or SameText(Ext, '.cc') then
        Result := ScanCppText(FileContent, ATests)
      else
        Result := ScanText(FileContent, ATests);
      if Result then
      begin
        for i := 0 to ATests.Count - 1 do
        begin
          Test := ATests[i];
          Test.FileName := AFileName;
          ATests[i] := Test;
        end;
      end;
    except
      // Silent fail
    end;
  finally
    Stream.Free;
  end;
end;

class function TTestASTScanner.ScanCppText(const AText: string; out ATests: TList<TTestLocation>): Boolean;
var
  ClassMatch: TMatch;
  ClassRegex: TRegEx;
  CurrentClass: string;
  GTestMatch: TMatch;
  GTestRegex: TRegEx;
  ImplMatch: TMatch;
  ImplRegex: TRegEx;
  i: Integer;
  InPublished: Boolean;
  Line: string;
  Lines: TArray<string>;
  MethodMatch: TMatch;
  MethodRegex: TRegEx;
  TestLoc: TTestLocation;
  Trimmed: string;

  procedure AddLoc(const AClass, AMethod: string; ALine: Integer);
  var
    Existing: TTestLocation;
    k: Integer;
  begin
    if (AClass = '') or (AMethod = '') then
      Exit;
    for k := 0 to ATests.Count - 1 do
    begin
      Existing := ATests[k];
      if SameText(Existing.ClassName, AClass) and SameText(Existing.MethodName, AMethod) then
      begin
        { Prefer .cpp implementation line over .h declaration when re-scanned. }
        if ALine > Existing.Line then
        begin
          Existing.Line := ALine;
          ATests[k] := Existing;
        end;
        Exit;
      end;
    end;
    TestLoc.ClassName := AClass;
    TestLoc.MethodName := AMethod;
    TestLoc.Line := ALine;
    TestLoc.FileName := '';
    ATests.Add(TestLoc);
    Result := True;
  end;

begin
  Result := False;
  if not Assigned(ATests) then
    ATests := TList<TTestLocation>.Create;

  { class TFoo : public TTestCase }
  ClassRegex := TRegEx.Create(
    '^\s*class\s+(\w+)\s*:\s*public\s+TTestCase\b', [roIgnoreCase]);
  { declaration in __published: void __fastcall TestFoo(); }
  MethodRegex := TRegEx.Create(
    '^\s*(?:void\s+)?(?:__fastcall\s+)?(Test\w+)\s*\(', [roIgnoreCase]);
  { implementation: void __fastcall TFoo::TestFoo() }
  ImplRegex := TRegEx.Create(
    '^\s*(?:void\s+)?(?:__fastcall\s+)?(\w+)::(Test\w+)\s*\(', [roIgnoreCase]);
  { Google Test: TEST(Suite, Name) / TEST_F / TEST_P }
  GTestRegex := TRegEx.Create(
    '^\s*TEST(?:_F|_P)?\s*\(\s*(\w+)\s*,\s*(\w+)\s*\)', []);

  CurrentClass := '';
  InPublished := False;
  Lines := AText.Split([#10]);
  for i := 0 to Length(Lines) - 1 do
  begin
    Line := Lines[i];
    Trimmed := Line.Trim;
    if Trimmed = '' then
      Continue;
    if (Length(Trimmed) > 0) and (Trimmed[Length(Trimmed)] = #13) then
      Trimmed := Trimmed.TrimRight([#13]);
    if Trimmed = '' then
      Continue;

    GTestMatch := GTestRegex.Match(Trimmed);
    if GTestMatch.Success then
    begin
      AddLoc(GTestMatch.Groups[1].Value, GTestMatch.Groups[2].Value, i + 1);
      Continue;
    end;

    ImplMatch := ImplRegex.Match(Trimmed);
    if ImplMatch.Success then
    begin
      AddLoc(ImplMatch.Groups[1].Value, ImplMatch.Groups[2].Value, i + 1);
      Continue;
    end;

    ClassMatch := ClassRegex.Match(Trimmed);
    if ClassMatch.Success then
    begin
      CurrentClass := ClassMatch.Groups[1].Value;
      InPublished := False;
      Continue;
    end;

    if CurrentClass = '' then
      Continue;

    if Trimmed.StartsWith('__published') then
    begin
      InPublished := True;
      Continue;
    end;
    if SameText(Trimmed, 'public:') or SameText(Trimmed, 'private:') or
       SameText(Trimmed, 'protected:') or SameText(Trimmed, 'public') or
       SameText(Trimmed, 'private') or SameText(Trimmed, 'protected') then
    begin
      InPublished := False;
      Continue;
    end;
    if Trimmed = '};' then
    begin
      CurrentClass := '';
      InPublished := False;
      Continue;
    end;

    if not InPublished then
      Continue;

    MethodMatch := MethodRegex.Match(Trimmed);
    if MethodMatch.Success then
      AddLoc(CurrentClass, MethodMatch.Groups[1].Value, i + 1);
  end;
end;

/// <summary>
/// Returns True if the trimmed line contains one of the fixture-level attributes:
///   [TestFixture], [TestFixture('...')], [TestClass], [Fixture], [Fixture('...')]
/// </summary>
function IsFixtureAttribute(const ATrimmed: string): Boolean;
var
  Lower: string;
begin
  Lower := LowerCase(ATrimmed);
  Result :=
    (Lower = '[testfixture]') or Lower.StartsWith('[testfixture(') or
    (Lower = '[fixture]')     or Lower.StartsWith('[fixture(') or
    (Lower = '[testclass]')   or Lower.StartsWith('[testclass(');
end;

/// <summary>
/// Returns True if the trimmed line is exactly '[Test]', '[Fact]', '[TestCase]',
/// '[TestCase(...]', '[TestCaseSource(...]', '[Ignore]' etc. - i.e. a method-level
/// attribute that appears on the line immediately before the procedure/function.
/// We treat any line matching \[Test...\] or \[Fact\] as "the next method is a test".
/// </summary>
function IsTestAttribute(const ATrimmed: string): Boolean;
var
  Lower: string;
begin
  Lower := LowerCase(ATrimmed);
  Result :=
    (Lower = '[test]') or
    (Lower = '[fact]') or
    Lower.StartsWith('[test(') or
    Lower.StartsWith('[testcase') or
    Lower.StartsWith('[testcasesource') or
    Lower.StartsWith('[fact(') or
    Lower.StartsWith('[customtestcase') or
    Lower.StartsWith('[autonametestcase');
end;

class function TTestASTScanner.ScanText(const AText: string; out ATests: TList<TTestLocation>): Boolean;
var
  Lines: TArray<string>;
  i: Integer;
  Line: string;
  Trimmed: string;
  CurrentClass: string;
  InTypeSection: Boolean;
  InPublishedSection: Boolean;
  NextLineIsFixture: Boolean;  // The NEXT class declaration is a test fixture
  NextMethodIsTest: Boolean;   // The NEXT method declaration is a test
  MatchObj: TMatch;
  TestLoc: TTestLocation;
  TypeDeclRegex, MethodRegex: TRegEx;
  MethodName: string;
  NestingDepth: Integer;
  Keyword: string;
  BracketEnd: Integer;
  AttrPart: string;
  Remainder: string;
  Accept: Boolean;
begin
  Result := False;
  if not Assigned(ATests) then
    ATests := TList<TTestLocation>.Create;

  Lines := AText.Split([#10]);
  CurrentClass := '';
  NestingDepth := 0;
  InTypeSection := False;
  InPublishedSection := False;
  NextLineIsFixture := False;
  NextMethodIsTest := False;

  // Regex patterns
  // Matches: ClassName = class(...) or ClassName = class
  TypeDeclRegex := TRegEx.Create('^\s*(\w+)\s*=\s*(class|record|interface|object)\b', [roIgnoreCase]);
  // Matches: procedure/function Name(...); or procedure/function Name;
  MethodRegex := TRegEx.Create('^\s*(procedure|function)\s+(\w+)\s*(\([^)]*\))?\s*;', [roIgnoreCase]);

  for i := 0 to Length(Lines) - 1 do
  begin
    Line := Lines[i];
    Trimmed := Line.Trim;

    if Trimmed = '' then Continue;

    // Remove trailing CR that may remain after splitting on LF
    if (Length(Trimmed) > 0) and (Trimmed[Length(Trimmed)] = #13) then
      Trimmed := Trimmed.TrimRight([#13]);
    if Trimmed = '' then Continue;

    // Stop at implementation section - we only parse the interface
    if SameText(Trimmed, 'implementation') then
      Break;

    // Detect type section
    if SameText(Trimmed, 'type') then
    begin
      InTypeSection := True;
      Continue;
    end;

    // -----------------------------------------------------------------------
    // Attribute detection (works both inside and outside type sections)
    // We look for attribute lines like [TestFixture], [Test], etc.
    // Handles both standalone attribute lines AND inline attribute+method lines:
    //   [Test]                          <- standalone attribute line
    //   [Test] procedure MethodName;    <- inline attribute + method
    //   [TestFixture('desc')]           <- fixture attribute with argument
    // -----------------------------------------------------------------------
    if (Length(Trimmed) >= 2) and (Trimmed[1] = '[') then
    begin
      BracketEnd := Pos(']', Trimmed);
      if BracketEnd > 0 then
      begin
        // Extract the attribute part: from '[' up to and including ']'
        AttrPart := Copy(Trimmed, 1, BracketEnd);
        // Everything after the attribute on the same line (trimmed)
        Remainder := Trim(Copy(Trimmed, BracketEnd + 1, MaxInt));

        if IsFixtureAttribute(AttrPart) then
        begin
          NextLineIsFixture := True;
          // If the class declaration is also on this line (unusual but handle it):
          // fall through so the TypeDeclRegex can match the remainder below.
          if Remainder <> '' then
            Trimmed := Remainder  // parse the remainder as a normal line below
          else
            Continue;
        end
        else if IsTestAttribute(AttrPart) then
        begin
          NextMethodIsTest := True;
          // If the method declaration is also on this line (e.g. [Test] procedure Foo;):
          // parse the remainder as a normal line so we match it immediately.
          if Remainder <> '' then
            Trimmed := Remainder  // fall through to method regex below
          else
            Continue;
        end
        else
        begin
          // Some other attribute - clear method flag only if the attribute
          // itself is on its own line (no remainder following it)
          if Remainder = '' then
            Continue;
          // Otherwise there might be a declaration after the attribute - fall through
          Trimmed := Remainder;
        end;
      end;
    end;

    if not InTypeSection then
      Continue;

    // -----------------------------------------------------------------------
    // Inside type section
    // -----------------------------------------------------------------------

    // Class / Record / Interface declaration
    MatchObj := TypeDeclRegex.Match(Trimmed);
    if MatchObj.Success and (Pos('class of', LowerCase(Trimmed)) = 0) and
       (not TRegEx.IsMatch(Trimmed, '\b(class|interface)\s*;', [roIgnoreCase])) then
    begin
      Keyword := MatchObj.Groups[2].Value;
      if CurrentClass = '' then
      begin
        if SameText(Keyword, 'class') then
        begin
          CurrentClass := MatchObj.Groups[1].Value;
          NestingDepth := 1;

          // Decide whether this class is a test fixture:
          //   1. Preceded by a fixture attribute ([TestFixture], [TestClass], …)
          //   2. OR class name contains 'Test' or 'Tests' (heuristic fallback)
          if NextLineIsFixture then
            InPublishedSection := True
          else if CurrentClass.ToLower.Contains('test') then
            InPublishedSection := True  // heuristic: name implies tests
          else
            InPublishedSection := False;

          NextLineIsFixture := False;
        end;
      end
      else
      begin
        // Nested type inside current class - track depth
        Inc(NestingDepth);
        NextLineIsFixture := False;
      end;
      NextMethodIsTest := False;
      Continue;
    end;

    // Block termination
    if SameText(Trimmed, 'end;') then
    begin
      if CurrentClass <> '' then
      begin
        Dec(NestingDepth);
        if NestingDepth <= 0 then
        begin
          CurrentClass := '';
          NestingDepth := 0;
          InPublishedSection := False;
        end;
      end;
      NextLineIsFixture := False;
      NextMethodIsTest := False;
      Continue;
    end;

    // Visibility markers
    if SameText(Trimmed, 'private') or SameText(Trimmed, 'protected') or
       SameText(Trimmed, 'strict private') or SameText(Trimmed, 'strict protected') then
    begin
      // Only suppress heuristic-name scanning; attribute-tagged methods still work
      // because NextMethodIsTest will be set by the [Test] line above.
      // We track InPublishedSection for the heuristic path only.
      InPublishedSection := False;
      Continue;
    end;

    if SameText(Trimmed, 'public') or SameText(Trimmed, 'published') then
    begin
      InPublishedSection := True;
      Continue;
    end;

    // Method discovery
    if CurrentClass <> '' then
    begin
      MatchObj := MethodRegex.Match(Trimmed);
      if MatchObj.Success then
      begin
        MethodName := MatchObj.Groups[2].Value;

        // Accept if:
        //   (A) The line was preceded by [Test] / [Fact] attribute, OR
        //   (B) Heuristic: public section + name starts with Test/Should
        //       and is not Setup/TearDown
        Accept := False;

        if NextMethodIsTest then
          Accept := True
        else if InPublishedSection then
        begin
          Accept :=
            (SameText(Copy(MethodName, 1, 4), 'Test') or
             SameText(Copy(MethodName, 1, 6), 'Should')) and
            (not SameText(MethodName, 'setup')) and
            (not SameText(MethodName, 'teardown'));
        end;

        if Accept then
        begin
          TestLoc.ClassName := CurrentClass;
          TestLoc.MethodName := MethodName;
          TestLoc.Line := i + 1;
          TestLoc.FileName := '';
          ATests.Add(TestLoc);
          Result := True;
        end;

        NextMethodIsTest := False; // consumed
      end;
    end;
  end;
end;

end.
