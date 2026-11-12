unit TestManyToManyIntegration;

interface

uses
  Data.DB,
  FireDAC.Comp.Client,
  FireDAC.Comp.DataSet,
  FireDAC.DApt,
  FireDAC.Phys.SQLite,
  FireDAC.Phys.SQLiteDef,
  FireDAC.Stan.Async,
  FireDAC.Stan.Def,
  System.Classes,
  System.Rtti,
  System.SysUtils,
  Dext.Assertions,
  Dext.Collections,
  Dext.Entity,
  Dext.Entity.Attributes,
  Dext.Entity.Collections,
  Dext.Entity.Core,
  Dext.Entity.Drivers.FireDAC,
  Dext.Entity.Drivers.Interfaces,
  Dext.Testing.Attributes,
  Dext.Types.Lazy;

type
  TCourseInt = class;
  TTagInt = class;

  // Test Entities
  [Table('Students')]
  TStudentInt = class
  private
    FId: Integer;
    FName: string;
    FCourses: Lazy<IList<TCourseInt>>;
  public
    [PK, AutoInc]
    property Id: Integer read FId write FId;
    property Name: string read FName write FName;
    
    [ManyToMany('StudentCourses', 'student_id', 'course_id')]
    property Courses: Lazy<IList<TCourseInt>> read FCourses write FCourses;
  end;

  [Table('Courses')]
  TCourseInt = class
  private
    FId: Integer;
    FTitle: string;
    FStudents: Lazy<IList<TStudentInt>>;
  public
    [PK, AutoInc]
    property Id: Integer read FId write FId;
    property Title: string read FTitle write FTitle;

    [ManyToMany('StudentCourses', 'course_id', 'student_id')]
    property Students: Lazy<IList<TStudentInt>> read FStudents write FStudents;
  end;

  // The target of this pair has a key that is not called Id
  [Table('Articles')]
  TArticleInt = class
  private
    FId: Integer;
    FTitle: string;
    FTags: Lazy<IList<TTagInt>>;
  public
    [PK, AutoInc]
    property Id: Integer read FId write FId;
    property Title: string read FTitle write FTitle;

    [ManyToMany('ArticleTags', 'article_id', 'tag_code')]
    property Tags: Lazy<IList<TTagInt>> read FTags write FTags;
  end;

  [Table('Tags')]
  TTagInt = class
  private
    FCode: Integer;
    FName: string;
    FArticles: Lazy<IList<TArticleInt>>;
  public
    [PK]
    property Code: Integer read FCode write FCode;
    property Name: string read FName write FName;

    [ManyToMany('ArticleTags', 'tag_code', 'article_id')]
    property Articles: Lazy<IList<TArticleInt>> read FArticles write FArticles;
  end;

  // DbContext
  TIntegrationContext = class(TDbContext)
  protected
    procedure OnModelCreating(Builder: TModelBuilder); override;
  public
    function Students: IDbSet<TStudentInt>;
    function Courses: IDbSet<TCourseInt>;
    function Articles: IDbSet<TArticleInt>;
    function Tags: IDbSet<TTagInt>;
  end;

  [TestFixture]
  TManyToManyIntegrationTests = class
  private
    FConn: TFDConnection;
    FContext: TIntegrationContext;
    FEntities: IList<TObject>;
    procedure SetupSchema;
    procedure Track(Obj: TObject);
  public
    [Setup]
    procedure Setup;
    [Teardown]
    procedure Teardown;
    
    [Test]
    procedure TestLazyLoading_ManyToMany;
    
    [Test]
    procedure TestLink_ManyToMany;

    [Test]
    procedure TestSync_ManyToMany;

    [Test]
    procedure TestManualInsertSQL;

    [Test]
    procedure TestGenerateJoinTableScripts_LazyList;

    [Test]
    procedure TestLazyLoading_ManyToMany_TargetKeyNotNamedId;

    [Test]
    procedure TestLink_WrongProperty_Raises;
  end;

implementation

{ TIntegrationContext }

procedure TIntegrationContext.OnModelCreating(Builder: TModelBuilder);
begin
  inherited;
  Builder.Entity<TStudentInt>;
  Builder.Entity<TCourseInt>;
  Builder.Entity<TArticleInt>;
  Builder.Entity<TTagInt>;
end;

function TIntegrationContext.Courses: IDbSet<TCourseInt>;
begin
  Result := Entities<TCourseInt>;
end;

function TIntegrationContext.Articles: IDbSet<TArticleInt>;
begin
  Result := Entities<TArticleInt>;
end;

function TIntegrationContext.Tags: IDbSet<TTagInt>;
begin
  Result := Entities<TTagInt>;
end;

function TIntegrationContext.Students: IDbSet<TStudentInt>;
begin
  Result := Entities<TStudentInt>;
end;

{ TManyToManyIntegrationTests }

procedure TManyToManyIntegrationTests.Setup;
var
  DbConn: IDbConnection;
  Dummy1: IList<TCourseInt>;
  Dummy2: IList<TStudentInt>;
  Dummy3: TTrackingList<TCourseInt>;
  Dummy4: TTrackingList<TStudentInt>;
  Dummy5: IList<TTagInt>;
  Dummy6: IList<TArticleInt>;
  Dummy7: TTrackingList<TTagInt>;
  Dummy8: TTrackingList<TArticleInt>;
begin
  FEntities := TCollections.CreateList<TObject>(False); // ORM manages object lifetime
  // Create In-Memory SQLite Connection
  FConn := TFDConnection.Create(nil);
  FConn.DriverName := 'SQLite';
  FConn.Params.Add('Database=:memory:');
  FConn.LoginPrompt := False;
  FConn.Open;

  // Wrap connection
  // Using explicit class from unit to avoid ambiguity if any
  DbConn := TFireDACConnection.Create(FConn, False); 

  // Create Context
  FContext := TIntegrationContext.Create(DbConn);
  
  // Force RTTI for generic lists and tracking lists
  Dummy1 := TSmartList<TCourseInt>.Create;
  Dummy2 := TSmartList<TStudentInt>.Create;
  Dummy3 := TTrackingList<TCourseInt>.Create(nil, nil, '');
  Dummy4 := TTrackingList<TStudentInt>.Create(nil, nil, '');
  Dummy3.Free;
  Dummy4.Free;
  Dummy5 := TSmartList<TTagInt>.Create;
  Dummy6 := TSmartList<TArticleInt>.Create;
  Dummy7 := TTrackingList<TTagInt>.Create(nil, nil, '');
  Dummy8 := TTrackingList<TArticleInt>.Create(nil, nil, '');
  Dummy7.Free;
  Dummy8.Free;
  
  SetupSchema;
end;

procedure TManyToManyIntegrationTests.SetupSchema;
begin
  // Use Quoted identifiers to match Dext behavior
  FContext.Connection.CreateCommand('CREATE TABLE "Students" ("Id" INTEGER PRIMARY KEY AUTOINCREMENT, "Name" TEXT)').Execute;
  FContext.Connection.CreateCommand('CREATE TABLE "Courses" ("Id" INTEGER PRIMARY KEY AUTOINCREMENT, "Title" TEXT)').Execute;
  FContext.Connection.CreateCommand('CREATE TABLE "StudentCourses" ("student_id" INTEGER, "course_id" INTEGER, PRIMARY KEY("student_id", "course_id"))').Execute;
  FContext.Connection.CreateCommand('CREATE TABLE "Articles" ("Id" INTEGER PRIMARY KEY AUTOINCREMENT, "Title" TEXT)').Execute;
  FContext.Connection.CreateCommand('CREATE TABLE "Tags" ("Code" INTEGER PRIMARY KEY, "Name" TEXT)').Execute;
  FContext.Connection.CreateCommand('CREATE TABLE "ArticleTags" ("article_id" INTEGER, "tag_code" INTEGER, PRIMARY KEY("article_id", "tag_code"))').Execute;
end;

procedure TManyToManyIntegrationTests.Track(Obj: TObject);
begin
  if FEntities <> nil then
    FEntities.Add(Obj);
end;

procedure TManyToManyIntegrationTests.Teardown;
begin
  // Free FEntities first (doesn't own objects), then context (which frees via IdentityMap)
  FEntities := nil;
  if FContext <> nil then FContext.Free;
  if FConn <> nil then FConn.Free;
end;

procedure TManyToManyIntegrationTests.TestLazyLoading_ManyToMany;
var
  S1: TStudentInt;
  C1, C2: TCourseInt;
  CheckStudent: TStudentInt;
  CoursesList: IList<TCourseInt>;
begin
  // 1. Insert Data
  S1 := TStudentInt.Create; Track(S1);
  S1.Name := 'John Doe';
  FContext.Students.Add(S1);
  FContext.SaveChanges;
  
  C1 := TCourseInt.Create; Track(C1);
  C1.Title := 'Math';
  FContext.Courses.Add(C1);
  
  C2 := TCourseInt.Create; Track(C2);
  C2.Title := 'Physics';
  FContext.Courses.Add(C2);
  FContext.SaveChanges;
  
  // 2. Link them
  FContext.Students.LinkManyToMany(S1, 'Courses', C1);
  FContext.Students.LinkManyToMany(S1, 'Courses', C2);
  
  // Detach everything to ensure fresh load
  FContext.DetachAll;
  
  // 3. Load Student (Lazy)
  CheckStudent := FContext.Students.Find(S1.Id);
  Should(CheckStudent).NotBeNil;
  Should(CheckStudent.Name).Be('John Doe');
  
  // 4. Trigger Lazy Loading
  Should(CheckStudent.Courses.IsValueCreated).BeFalse; // Not loaded yet
  
  CoursesList := CheckStudent.Courses.Value; // Access property trigger

  Should(CheckStudent.Courses.IsValueCreated).BeTrue;
  Should(CoursesList).NotBeNil;
  Should(CoursesList.Count).Be(2);
end;

procedure TManyToManyIntegrationTests.TestLink_ManyToMany;
var
  S1: TStudentInt;
  C1: TCourseInt;
  Cmd: IDbCommand;
  Val, Val2: TValue;
begin
  S1 := TStudentInt.Create; 
  S1.Name := 'Alice';
  FContext.Students.Add(S1);
  
  C1 := TCourseInt.Create; 
  C1.Title := 'Chemistry';
  FContext.Courses.Add(C1);
  
  FContext.SaveChanges;
  
  // Link
  FContext.Students.LinkManyToMany(S1, 'Courses', C1);
  
  // Verify in Join Table
  Cmd := FContext.Connection.CreateCommand('SELECT COUNT(*) FROM "StudentCourses" WHERE "student_id" = :p1 AND "course_id" = :p2');
  Cmd.AddParam('p1', S1.Id);
  Cmd.AddParam('p2', C1.Id);
  
  Val := Cmd.ExecuteScalar;
  Should(Val.AsInteger).Be(1);
  
  // Unlink
  FContext.Students.UnlinkManyToMany(S1, 'Courses', C1);
  
  Val2 := Cmd.ExecuteScalar;
  Should(Val2.AsInteger).Be(0);
end;

procedure TManyToManyIntegrationTests.TestSync_ManyToMany;
var
  S1: TStudentInt;
  C1, C2, C3: TCourseInt;
  Related: TArray<TObject>;
  Cmd, CmdCheck: IDbCommand;
begin
  S1 := TStudentInt.Create; 
  FContext.Students.Add(S1);
  
  C1 := TCourseInt.Create; 
  C2 := TCourseInt.Create; 
  C3 := TCourseInt.Create; 
  FContext.Courses.Add(C1);
  FContext.Courses.Add(C2);
  FContext.Courses.Add(C3);
  FContext.SaveChanges;
  
  // Initial Link: C1, C2
  SetLength(Related, 2);
  Related[0] := C1;
  Related[1] := C2;
  FContext.Students.SyncManyToMany(S1, 'Courses', Related);
  
  Cmd := FContext.Connection.CreateCommand('SELECT COUNT(*) FROM "StudentCourses" WHERE "student_id" = :p1');
  Cmd.AddParam('p1', S1.Id);
  Should(Cmd.ExecuteScalar.AsInteger).Be(2);
  
  // Sync: C2, C3 (Should remove C1, keep C2, add C3)
  SetLength(Related, 2);
  Related[0] := C2;
  Related[1] := C3;
  FContext.Students.SyncManyToMany(S1, 'Courses', Related);
  
  Should(Cmd.ExecuteScalar.AsInteger).Be(2);
  
  // Verify C1 is gone
  CmdCheck := FContext.Connection.CreateCommand('SELECT COUNT(*) FROM "StudentCourses" WHERE "student_id" = :p1 AND "course_id" = :p2');
  CmdCheck.AddParam('p1', S1.Id);
  CmdCheck.AddParam('p2', C1.Id);
  Should(CmdCheck.ExecuteScalar.AsInteger).Be(0);
  
  // Verify C3 is present
  // Verify C3 is present
  CmdCheck := FContext.Connection.CreateCommand('SELECT COUNT(*) FROM "StudentCourses" WHERE "student_id" = :p1 AND "course_id" = :p2');
  CmdCheck.AddParam('p1', S1.Id);
  CmdCheck.AddParam('p2', C3.Id);
  Should(CmdCheck.ExecuteScalar.AsInteger).Be(1);
end;

procedure TManyToManyIntegrationTests.TestGenerateJoinTableScripts_LazyList;
var
  Scripts: TArray<TJoinTableScript>;
begin
  // The collections are Lazy<IList<T>>: the join table must still be found,
  // otherwise EnsureCreated leaves it out and Link fails with "no such table".
  Scripts := FContext.Students.GenerateJoinTableScripts;

  Should(Length(Scripts)).Be(1);
  Should(Scripts[0].TableName).Be('StudentCourses');
  Should(Scripts[0].Sql).Contain('student_id');
  Should(Scripts[0].Sql).Contain('course_id');
end;

procedure TManyToManyIntegrationTests.TestLazyLoading_ManyToMany_TargetKeyNotNamedId;
var
  A, Check: TArticleInt;
  T1, T2: TTagInt;
begin
  A := TArticleInt.Create;
  A.Title := 'Dext';
  FContext.Articles.Add(A);
  T1 := TTagInt.Create;
  T1.Code := 10;
  T1.Name := 'orm';
  FContext.Tags.Add(T1);
  T2 := TTagInt.Create;
  T2.Code := 20;
  T2.Name := 'delphi';
  FContext.Tags.Add(T2);
  FContext.SaveChanges;

  FContext.Articles.LinkManyToMany(A, 'Tags', T1);
  FContext.Articles.LinkManyToMany(A, 'Tags', T2);
  FContext.DetachAll;

  // The lazy loader looked the tags up by a column called Id: with the key
  // called Code, the list came back empty and nothing said why.
  Check := FContext.Articles.Find(A.Id);
  Should(Check.Tags.Value.Count).Be(2);

  FContext.DetachAll;
  Should(FContext.Tags.Find(10).Articles.Value.Count).Be(1);
end;

procedure TManyToManyIntegrationTests.TestLink_WrongProperty_Raises;
var
  S1: TStudentInt;
  C1: TCourseInt;
  Raised: Integer;

  procedure Expect(const AProc: TProc);
  begin
    try
      AProc();
    except
      on Exception do Inc(Raised);
    end;
  end;

begin
  S1 := TStudentInt.Create;
  FContext.Students.Add(S1);
  C1 := TCourseInt.Create;
  FContext.Courses.Add(C1);
  FContext.SaveChanges;

  // A misspelled name, and a property that is not many-to-many, used to
  // return without doing anything: the caller believed the link was made.
  Raised := 0;
  Expect(procedure begin FContext.Students.LinkManyToMany(S1, 'Cursos', C1); end);
  Expect(procedure begin FContext.Students.UnlinkManyToMany(S1, 'Cursos', C1); end);
  Expect(procedure begin FContext.Students.SyncManyToMany(S1, 'Cursos', []); end);
  Expect(procedure begin FContext.Students.LinkManyToMany(S1, 'Name', C1); end);
  Should(Raised).Be(4);
end;

procedure TManyToManyIntegrationTests.TestManualInsertSQL;
var
  Cmd: IDbCommand;
  Val: Integer;
begin
  // Verifying writes work
  FContext.Connection.CreateCommand('INSERT INTO "StudentCourses" ("student_id", "course_id") VALUES (99, 88)').Execute;
  
  Cmd := FContext.Connection.CreateCommand('SELECT COUNT(*) FROM "StudentCourses" WHERE "student_id" = 99');
  Val := Cmd.ExecuteScalar.AsInteger;
  Should(Val).Be(1);
end;

end.
