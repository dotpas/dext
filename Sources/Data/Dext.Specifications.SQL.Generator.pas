{***************************************************************************}
{                                                                           }
{           Dext Framework                                                  }
{                                                                           }
{           Copyright (C) 2025 Cesar Romero & Dext Contributors             }
{                                                                           }
{           Licensed under the Apache License, Version 2.0 (the "License"); }
{           you may not use this file except in compliance with the License.}
{           You may obtain a copy of the License at                         }
{                                                                           }
{               http://www.apache.org/licenses/LICENSE-2.0                  }
{                                                                           }
{           Unless required by applicable law or agreed to in writing,      }
{           software distributed under the License is distributed on an     }
{           "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,    }
{           either express or implied. See the License for the specific     }
{           language governing permissions and limitations under the        }
{           License.                                                        }
{                                                                           }
{***************************************************************************}
{                                                                           }
{  Author:  Cesar Romero                                                    }
{  Created: 2025-12-08                                                      }
{                                                                           }
{***************************************************************************}
unit Dext.Specifications.SQL.Generator;

interface

uses
  System.Character,
  System.Classes,
  System.Rtti,
  System.SysUtils,
  System.TypInfo,
  System.Variants,
  Data.DB,
  Dext.Collections,
  Dext.Collections.Base,
  Dext.Collections.Dict,
  Dext.Entity.Attributes,
  Dext.Entity.Cache,
  Dext.Entity.Core,
  Dext.Entity.Dialects,
  Dext.Entity.Mapping,
  Dext.Entity.Naming,
  Dext.Entity.TypeConverters,
  Dext.MultiTenancy,
  Dext.Specifications.Interfaces,
  Dext.Specifications.Types,
  Dext.Types.Nullable,
  Dext.Types.UUID,
  Dext.Utils,
  Dext.Core.Reflection;

type
  ISQLColumnMapper = interface
    ['{6C3E8F9A-1B2C-4D5E-9F0A-1B2C3D4E5F6A}']
    function MapColumn(const AName: string): string;
  end;

  /// <summary>
  ///   Translates a Expression Tree into a SQL WHERE clause and Parameters.
  /// </summary>
  TSQLWhereGenerator = class
  private
    FSQL: TStringBuilder;
    FParams: IDictionary<string, TValue>;
    FParamCount: Integer;
    FDialect: ISQLDialect;
    FColumnMapper: ISQLColumnMapper;
    FQualifyUnaliasedColumns: Boolean;
    FBaseTableName: string;

    procedure ProcessBinary(const C: TBinaryExpression);
    procedure ProcessArithmetic(const C: TArithmeticExpression);
    procedure ProcessLogical(const C: TLogicalExpression);
    procedure ProcessUnary(const C: TUnaryExpression);
    procedure ProcessConstant(const C: TConstantExpression);
    procedure ProcessProperty(const C: TPropertyExpression);
    procedure ProcessJsonProperty(const C: TJsonPropertyExpression);
    procedure ProcessLiteral(const C: TLiteralExpression);

    procedure ResolveSQL(const AExpression: IExpression);
    
    function GetNextParamName: string;
    function GetBinaryOpSQL(Op: TBinaryOperator): string;
    function GetArithmeticOpSQL(Op: TArithmeticOperator): string;
    function GetLogicalOpSQL(Op: TLogicalOperator): string;
    function GetUnaryOpSQL(Op: TUnaryOperator): string;

    function MapColumn(const AName: string): string;
    function QuoteColumnOrAlias(const AName: string): string;
  public
    constructor Create(ADialect: ISQLDialect; AMapper: ISQLColumnMapper = nil;
      AQualifyUnaliasedColumns: Boolean = False; const ABaseTableName: string = '');
    destructor Destroy; override;
    
    function Generate(const AExpression: IExpression): string;
    
    property Params: IDictionary<string, TValue> read FParams;
    property ParamCount: Integer read FParamCount write FParamCount;
  end;

  TSQLColumnMapper<T: class> = class(TInterfacedObject, ISQLColumnMapper)
  private
    FNamingStrategy: INamingStrategy;
  public
    constructor Create(ANamingStrategy: INamingStrategy = nil);
    destructor Destroy; override;
    function MapColumn(const AName: string): string;
    property NamingStrategy: INamingStrategy read FNamingStrategy write FNamingStrategy;
  end;

  /// <summary>A column declared by a class of a TPH hierarchy.</summary>
  TDeclaredColumn = record
    Prop: TRttiProperty;
    ColumnName: string;
  end;

  TSQLGeneratorHelper = class
  public
    /// <summary>Mapped columns declared by the class of AMap itself (not inherited): used by TPH.</summary>
    class function GetDeclaredColumns(AMap: TEntityMap; ANamingStrategy: INamingStrategy): TArray<TDeclaredColumn>; static;
    class function GetCascadeSQL(AAction: TCascadeAction): string;
    class function GetColumnNameForProperty(ATyp: TRttiType; const APropName: string; ANamingStrategy: INamingStrategy = nil): string;
    class function GetRelatedTableAndPK(AClass: TClass; out ATable, ASchema, APK: string; ANamingStrategy: INamingStrategy = nil): Boolean;
    /// <summary>The dialect of ADialect, recognized from its quoting when
    ///   GetDialect does not say.</summary>
    class function ResolveDialect(const ADialect: ISQLDialect): TDatabaseDialect; static;
  end;

  /// <summary>
  ///   Helper class to generate SQL for Many-to-Many join table operations.
  /// </summary>
  TJoinTableSQLHelper = class
  public
    class function GenerateInsert(ADialect: ISQLDialect; 
      const AJoinTable, ALeftColumn, ARightColumn: string): string;
    class function GenerateDelete(ADialect: ISQLDialect;
      const AJoinTable, ALeftColumn, ARightColumn: string): string;
    class function GenerateDeleteByLeft(ADialect: ISQLDialect;
      const AJoinTable, ALeftColumn: string): string;
  end;

  /// <summary>
  ///   Generates SQL for CRUD operations (Insert, Update, Delete).
  /// </summary>
  TSQLGenerator<T: class> = class
  private
    FDialect: ISQLDialect;
    FParams: IDictionary<string, TValue>;
    FParamTypes: IDictionary<string, TFieldType>;  // Explicit types from [DbType] attribute
    FParamCount: Integer;
    FMap: TEntityMap;
    FNamingStrategy: INamingStrategy;
    // Properties to control filtering
    FIgnoreQueryFilters: Boolean;
    FOnlyDeleted: Boolean;
    FSchema: string;
    FContext: IDbContext;
    FTenantProvider: ITenantProvider;

    procedure Initialize(ADialect: ISQLDialect; AMap: TEntityMap; ATenantProvider: ITenantProvider);
  protected
    function GetNextParamName: string;
    function GetTableName: string;
    function GetSoftDeleteFilter: string;
    function GetDiscriminatorFilter: string;
    function GetDiscriminatorValueSQL: string;
    // Table-per-hierarchy support
    function IsHierarchyMember: Boolean;
    function IsRootMap(AMap: TEntityMap): Boolean;
    function GetHierarchyRoot: TEntityMap;
    function GetSubtypeMaps(ARoot: TEntityMap): TArray<TEntityMap>;
    function GetHierarchyColumns: TArray<string>;
    function GetQueryFiltersSQL: string;
    
    function GetDialectEnum: TDatabaseDialect;
    function GetJoinTypeSQL(AType: TJoinType): string;
    function GenerateJoins(const AJoins: TArray<IJoin>): string;
    function GenerateGroupBy(const AGroupBy: TArray<string>): string;
    function QuoteColumnOrAlias(const AName: string): string;
    function QualifyBaseColumn(const AColumnName, ABaseTableName: string; AHasJoins: Boolean): string;
    function TryUnwrapSmartValue(var AValue: TValue): Boolean;
    function IsTenantAwareEntity: Boolean;
    procedure AppendTenantWhereParams(SBWhere: TStringBuilder; var AFirstWhere: Boolean);
    procedure AppendTenantWhereTemplate(SBWhere: TStringBuilder; var AFirstWhere: Boolean;
      AWhereProps: IList<TPair<TRttiProperty, string>>);
  public
    constructor Create(ADialect: ISQLDialect; AMap: TEntityMap = nil; ATenantProvider: ITenantProvider = nil); overload;
    constructor Create(AContext: IDbContext; AMap: TEntityMap = nil; ATenantProvider: ITenantProvider = nil); overload;
    destructor Destroy; override;
    
    property IgnoreQueryFilters: Boolean read FIgnoreQueryFilters write FIgnoreQueryFilters;
    property OnlyDeleted: Boolean read FOnlyDeleted write FOnlyDeleted;
    property Schema: string read FSchema write FSchema;
    property NamingStrategy: INamingStrategy read FNamingStrategy write FNamingStrategy;
    
    function GenerateInsertTemplate(out AProps: IList<TPair<TRttiProperty, string>>): string;
    function GenerateUpdateTemplate(out ASetProps, AWhereProps: IList<TPair<TRttiProperty, string>>): string;
    function GenerateDeleteTemplate(out AWhereProps: IList<TPair<TRttiProperty, string>>): string;
    /// <summary>Generates a parameterized INSERT statement for the entity.</summary>
    function GenerateInsert(const AEntity: T): string;
    /// <summary>Generates a parameterized UPDATE statement for the entity using its Primary Key.</summary>
    function GenerateUpdate(const AEntity: T): string;
    /// <summary>Generates a parameterized DELETE statement for the entity using its Primary Key.</summary>
    function GenerateDelete(const AEntity: T): string;
    
    function GenerateSelect(const ASpec: ISpecification<T>): string; overload;
    function GenerateSelect: string; overload;
    function GenerateCount(const ASpec: ISpecification<T>): string; overload;
    function GenerateCount: string; overload;
    function GenerateCreateTable(const ATableName: string): string;
    
    property Params: IDictionary<string, TValue> read FParams;
    property ParamTypes: IDictionary<string, TFieldType> read FParamTypes;
  end;

  TSQLParamCollector = class
  private
    FParams: IDictionary<string, TValue>;
    FParamCount: Integer;
    FDialect: TDatabaseDialect;

    function GetNextParamName: string;
    procedure Resolve(const Ex: IExpression);
    procedure ProcessBinary(const C: TBinaryExpression);
    procedure ProcessArithmetic(const C: TArithmeticExpression);
    procedure ProcessLogical(const C: TLogicalExpression);
    procedure ProcessUnary(const C: TUnaryExpression);
    procedure ProcessLiteral(const C: TLiteralExpression);
  public
    /// <param name="ADialect">The dialect the cached statement was generated
    ///   for: StartsWith / EndsWith / Contains escape their value per dialect.</param>
    constructor Create(AParams: IDictionary<string, TValue>;
      ADialect: TDatabaseDialect = ddUnknown);
    procedure Collect(const AExpression: IExpression);
  end;

implementation

uses
  Dext.Entity.Context,
  Dext.Entity.Tenancy;

// The escape character for StartsWith / EndsWith / Contains. Not a backslash:
// in MySQL string literals the backslash is itself an escape character.
const
  LikeEscapeChar = '!';

/// <summary>The dialect of AD, recognized from its quoting when GetDialect
///   does not say. The where generator and the parameter collector use the
///   same function, so that a cached statement gets the same parameters.</summary>
function ResolveDialect(const AD: ISQLDialect): TDatabaseDialect;
var
  Quoted: string;
begin
  Result := ddUnknown;
  if AD = nil then
    Exit;
  Result := AD.GetDialect;
  if Result = ddUnknown then
  begin
    Quoted := AD.QuoteIdentifier('t');
    if Quoted.StartsWith('[') then Result := ddSQLServer
    else if Quoted.StartsWith('`') then Result := ddMySQL
    else if Quoted.StartsWith('"') then
    begin
       if SameText(AD.BooleanToSQL(True), 'TRUE') then Result := ddPostgreSQL
       else Result := ddSQLite;
    end;
  end;
end;

/// <summary>The LIKE pattern for StartsWith / EndsWith / Contains: the value
///   with every character LIKE treats as special escaped by LikeEscapeChar,
///   plus the wildcards of the operator. SQL Server also reads [ as the start
///   of a character class.</summary>
function LiteralLikePattern(const AValue: string; AOperator: TBinaryOperator;
  ADialect: TDatabaseDialect): string;
var
  SB: TStringBuilder;
  C: Char;
begin
  SB := TStringBuilder.Create(Length(AValue) + 8);
  try
    if AOperator in [boEndsWith, boContains] then
      SB.Append('%');
    for C in AValue do
    begin
      if (C = LikeEscapeChar) or (C = '%') or (C = '_') or
        ((C = '[') and (ADialect = ddSQLServer)) then
        SB.Append(LikeEscapeChar);
      SB.Append(C);
    end;
    if AOperator in [boStartsWith, boContains] then
      SB.Append('%');
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

/// <summary>True when StartsWith is written as STARTING WITH :p instead of a
///   LIKE. On Firebird a LIKE with a parameter never uses an index (PLAN
///   NATURAL: every row is read), while STARTING WITH :p does, and it has no
///   wildcards, so the value goes as it is. Measured on Firebird 5, one
///   million rows, a VARCHAR parameter: LIKE :p ESCAPE '!' 640 ms with
///   1,000,009 natural reads, STARTING WITH :p 1-8 ms with indexed reads
///   only; the same rows in every case tried.</summary>
function UsesStartingWith(AOperator: TBinaryOperator;
  ADialect: TDatabaseDialect): Boolean;
begin
  Result := (AOperator = boStartsWith) and (ADialect = ddFirebird);
end;

/// <summary>The parameter value for StartsWith / EndsWith / Contains: the
///   value itself for STARTING WITH, the escaped LIKE pattern otherwise.
///   TSQLWhereGenerator and TSQLParamCollector both use it.</summary>
function LiteralMatchValue(const AValue: string; AOperator: TBinaryOperator;
  ADialect: TDatabaseDialect): string;
begin
  if UsesStartingWith(AOperator, ADialect) then
    Result := AValue
  else
    Result := LiteralLikePattern(AValue, AOperator, ADialect);
end;

{ TSQLParamCollector }

constructor TSQLParamCollector.Create(AParams: IDictionary<string, TValue>;
  ADialect: TDatabaseDialect);
begin
  FDialect := ADialect;
  FParams := AParams;
  FParamCount := 0; 
end;

function TSQLParamCollector.GetNextParamName: string;
begin
  Inc(FParamCount);
  Result := 'p' + IntToStr(FParamCount);
end;

procedure TSQLParamCollector.Collect(const AExpression: IExpression);
begin
  if AExpression <> nil then
    Resolve(AExpression);
end;

procedure TSQLParamCollector.Resolve(const Ex: IExpression);
begin
  if Ex is TBinaryExpression then
    ProcessBinary(TBinaryExpression(Ex))
  else if Ex is TLogicalExpression then
    ProcessLogical(TLogicalExpression(Ex))
  else if Ex is TUnaryExpression then
    ProcessUnary(TUnaryExpression(Ex))
  else if Ex is TArithmeticExpression then
    ProcessArithmetic(TArithmeticExpression(Ex))
  else if Ex is TConstantExpression then
    // No params
  else if Ex is TPropertyExpression then
    // No params
  else if Ex is TJsonPropertyExpression then
    // No params
  else if Ex is TLiteralExpression then
    ProcessLiteral(TLiteralExpression(Ex))
  else
    raise Exception.Create('Unknown expression type in ParamCollector: ' + Ex.ToString);
end;

procedure TSQLParamCollector.ProcessBinary(const C: TBinaryExpression);
var
  I: Integer;
  ArrayValue: TValue;
  PName: string;
  PVal: TValue;
begin
  // Standard traversal order must match TSQLWhereGenerator exactly:
  // 1. IN/NOT IN with Array -> Loop elements
  // 2. Others -> Resolve Left -> Resolve Right (or Literal)
  
  if (C.BinaryOperator = boIn) or (C.BinaryOperator = boNotIn) then
  begin
    if (C.Right is TLiteralExpression) and TLiteralExpression(C.Right).Value.IsArray then
    begin
       ArrayValue := TLiteralExpression(C.Right).Value;
       for I := 0 to ArrayValue.GetArrayLength - 1 do
       begin
         PName := GetNextParamName;
         PVal := ArrayValue.GetArrayElement(I);
         FParams.Add(PName, PVal);
       end;
       
       // Important: Must resolve Left side as it might contain parameters too!
       Resolve(C.Left);
       Exit;
    end;
  end;
  
  Resolve(C.Left);
  
  if C.Right is TLiteralExpression then
  begin
    // Same parameter value as TSQLWhereGenerator.ProcessBinary.
    if C.BinaryOperator in [boStartsWith, boEndsWith, boContains] then
      FParams.Add(GetNextParamName, TValue.From<string>(LiteralMatchValue(
        TLiteralExpression(C.Right).Value.ToString, C.BinaryOperator, FDialect)))
    else
      FParams.Add(GetNextParamName, TLiteralExpression(C.Right).Value);
  end
  else
    Resolve(C.Right);
end;

procedure TSQLParamCollector.ProcessArithmetic(const C: TArithmeticExpression);
begin
  Resolve(C.Left);
  Resolve(C.Right);
end;

procedure TSQLParamCollector.ProcessLogical(const C: TLogicalExpression);
begin
  Resolve(C.Left);
  Resolve(C.Right);
end;

procedure TSQLParamCollector.ProcessUnary(const C: TUnaryExpression);
begin
  if C.UnaryOperator = uoNot then
    Resolve(C.Expression)
  else
    // IsNull/IsNotNull has no params (uses PropertyName)
    ;
end;

procedure TSQLParamCollector.ProcessLiteral(const C: TLiteralExpression);
begin
  FParams.Add(GetNextParamName, C.Value);
end;

{ TSQLGeneratorHelper }

class function TSQLGeneratorHelper.ResolveDialect(const ADialect: ISQLDialect): TDatabaseDialect;
begin
  Result := Dext.Specifications.SQL.Generator.ResolveDialect(ADialect);
end;

class function TSQLGeneratorHelper.GetCascadeSQL(AAction: TCascadeAction): string;
begin
  case AAction of
    caCascade: Result := 'CASCADE';
    caSetNull: Result := 'SET NULL';
    caRestrict: Result := 'RESTRICT';
    else Result := 'NO ACTION';
  end;
end;

class function TSQLGeneratorHelper.GetColumnNameForProperty(ATyp: TRttiType; const APropName: string; ANamingStrategy: INamingStrategy): string;
var
  P: TRttiProperty;
  A: TCustomAttribute;
begin
  Result := APropName; // Default
  P := ATyp.GetProperty(APropName);
  if P <> nil then
  begin
    for A in P.GetAttributes do
    begin
      if A is ColumnAttribute then Exit(ColumnAttribute(A).Name);
    end;
    
    if (Result = APropName) and (ANamingStrategy <> nil) then
      Result := ANamingStrategy.GetColumnName(P);
  end;
end;

class function TSQLGeneratorHelper.GetRelatedTableAndPK(AClass: TClass; out ATable, ASchema, APK: string; ANamingStrategy: INamingStrategy): Boolean;
var
  RTyp: TRttiType;
  RProp: TRttiProperty;
  RAttr, SubAttr: TCustomAttribute;
  HasTableAttr: Boolean;
  HasColAttr: Boolean;
begin
  Result := False;
  ASchema := '';
  RTyp := TReflection.GetMetadata(AClass.ClassInfo).RttiType;
  if RTyp = nil then Exit;
  
  // Table Name
  ATable := RTyp.Name;
  HasTableAttr := False;
  for RAttr in RTyp.GetAttributes do
    if RAttr is TableAttribute then
    begin
      ATable := TableAttribute(RAttr).Name;
      ASchema := TableAttribute(RAttr).Schema;
      HasTableAttr := True;
    end;
      
  if (not HasTableAttr) and (ANamingStrategy <> nil) then
    ATable := ANamingStrategy.GetTableName(AClass);

  // PK
  for RProp in RTyp.GetProperties do
  begin
    for RAttr in RProp.GetAttributes do
    begin
      if RAttr is PrimaryKeyAttribute then
      begin
        APK := RProp.Name;
        HasColAttr := False;
        // Check for Column Attribute on PK
        for SubAttr in RProp.GetAttributes do
          if SubAttr is ColumnAttribute then
          begin
            APK := ColumnAttribute(SubAttr).Name;
            HasColAttr := True;
          end;
          
        if (not HasColAttr) and (ANamingStrategy <> nil) then
          APK := ANamingStrategy.GetColumnName(RProp);
          
        Exit(True);
      end;
    end;
  end;
  
  // Fallback to 'Id'
  RProp := RTyp.GetProperty('Id');
  if RProp <> nil then
  begin
    APK := 'Id';
    HasColAttr := False;
    for RAttr in RProp.GetAttributes do
      if RAttr is ColumnAttribute then
      begin
        APK := ColumnAttribute(RAttr).Name;
        HasColAttr := True;
      end;
      
    if (not HasColAttr) and (ANamingStrategy <> nil) then
       APK := ANamingStrategy.GetColumnName(RProp);
       
    Exit(True);
  end;
end;

{ TJoinTableSQLHelper }

class function TJoinTableSQLHelper.GenerateInsert(ADialect: ISQLDialect;
  const AJoinTable, ALeftColumn, ARightColumn: string): string;
begin
  // INSERT INTO "JoinTable" ("left_col", "right_col") VALUES (:p1, :p2)
  Result := Format('INSERT INTO %s (%s, %s) VALUES (:p1, :p2)',
    [ADialect.QuoteIdentifier(AJoinTable),
     ADialect.QuoteIdentifier(ALeftColumn),
     ADialect.QuoteIdentifier(ARightColumn)]);
end;

class function TJoinTableSQLHelper.GenerateDelete(ADialect: ISQLDialect;
  const AJoinTable, ALeftColumn, ARightColumn: string): string;
begin
  // DELETE FROM "JoinTable" WHERE "left_col" = :p1 AND "right_col" = :p2
  Result := Format('DELETE FROM %s WHERE %s = :p1 AND %s = :p2',
    [ADialect.QuoteIdentifier(AJoinTable),
     ADialect.QuoteIdentifier(ALeftColumn),
     ADialect.QuoteIdentifier(ARightColumn)]);
end;

class function TJoinTableSQLHelper.GenerateDeleteByLeft(ADialect: ISQLDialect;
  const AJoinTable, ALeftColumn: string): string;
begin
  // DELETE FROM "JoinTable" WHERE "left_col" = :p1
  Result := Format('DELETE FROM %s WHERE %s = :p1',
    [ADialect.QuoteIdentifier(AJoinTable),
     ADialect.QuoteIdentifier(ALeftColumn)]);
end;

{ TSQLWhereGenerator }

constructor TSQLWhereGenerator.Create(ADialect: ISQLDialect; AMapper: ISQLColumnMapper;
  AQualifyUnaliasedColumns: Boolean; const ABaseTableName: string);
begin
  FSQL := TStringBuilder.Create;
  FParams := TCollections.CreateDictionary<string, TValue>;
  FParamCount := 0;
  FDialect := ADialect;
  FColumnMapper := AMapper;
  FQualifyUnaliasedColumns := AQualifyUnaliasedColumns;
  FBaseTableName := ABaseTableName;
end;

destructor TSQLWhereGenerator.Destroy;
begin
  FSQL.Free;
  FParams := nil;
  inherited;
end;

function TSQLWhereGenerator.MapColumn(const AName: string): string;
begin
  if FColumnMapper <> nil then
    Result := FColumnMapper.MapColumn(AName)
  else
    Result := AName;
end;

function TSQLWhereGenerator.QuoteColumnOrAlias(const AName: string): string;
var
  Parts: TArray<string>;
  i: Integer;
begin
  if AName.Contains('.') then
  begin
    Parts := AName.Split(['.']);
    Result := '';
    for i := 0 to High(Parts) do
    begin
      if i > 0 then Result := Result + '.';
      Result := Result + FDialect.QuoteIdentifier(Parts[i]);
    end;
  end
  else
  begin
    if FQualifyUnaliasedColumns and (FBaseTableName <> '') then
      Result := FBaseTableName + '.' + FDialect.QuoteIdentifier(AName)
    else
      Result := FDialect.QuoteIdentifier(AName);
  end;
end;

function TSQLWhereGenerator.Generate(const AExpression: IExpression): string;
begin
  FSQL.Clear;
  FParams.Clear;
  
  if AExpression = nil then
    Exit('');
    
  ResolveSQL(AExpression);
  Result := FSQL.ToString;
end;

function TSQLWhereGenerator.GetNextParamName: string;
begin
  Inc(FParamCount);
  Result := 'p' + IntToStr(FParamCount);
end;

procedure TSQLWhereGenerator.ResolveSQL(const AExpression: IExpression);
begin
  if AExpression is TBinaryExpression then
    ProcessBinary(TBinaryExpression(AExpression))
  else if AExpression is TArithmeticExpression then
    ProcessArithmetic(TArithmeticExpression(AExpression))
  else if AExpression is TLogicalExpression then
    ProcessLogical(TLogicalExpression(AExpression))
  else if AExpression is TUnaryExpression then
    ProcessUnary(TUnaryExpression(AExpression))
  else if AExpression is TConstantExpression then
    ProcessConstant(TConstantExpression(AExpression))
  else if AExpression is TPropertyExpression then
    ProcessProperty(TPropertyExpression(AExpression))
  else if AExpression is TJsonPropertyExpression then
    ProcessJsonProperty(TJsonPropertyExpression(AExpression))
  else if AExpression is TLiteralExpression then
    ProcessLiteral(TLiteralExpression(AExpression))
  else
    raise Exception.Create('Unknown expression type: ' + AExpression.ToString);
end;

procedure TSQLWhereGenerator.ProcessBinary(const C: TBinaryExpression);
var
  ParamName: string;
  ArrayValue: TValue;
  I: Integer;
  ParamNames: TStringBuilder;
  SQLCast: string;
  Converter: ITypeConverter;
  DialectEnum: TDatabaseDialect;
  PVal: TValue;
  URType: TRttiType;
  UFValue: TRttiField;
  Lit: TLiteralExpression;
begin
  // Special handling for IN and NOT IN operators
  if (C.BinaryOperator = boIn) or (C.BinaryOperator = boNotIn) then
  begin
    if (C.Right is TLiteralExpression) and TLiteralExpression(C.Right).Value.IsArray then
    begin
      ArrayValue := TLiteralExpression(C.Right).Value;
      ParamNames := TStringBuilder.Create;
      try
        for I := 0 to ArrayValue.GetArrayLength - 1 do
        begin
          ParamName := GetNextParamName;
          PVal := ArrayValue.GetArrayElement(I);
          // Inline unwrap for Smart Types (same logic as TSQLGenerator.TryUnwrapSmartValue)
          if PVal.Kind = tkRecord then
          begin
            URType := TReflection.Context.GetType(PVal.TypeInfo);
            if URType <> nil then
            begin
              UFValue := URType.GetField('FValue');
              if (UFValue <> nil) and
                 (URType.Name.Contains('Prop<') or URType.Name.Contains('TProp') or
                  (URType.Name.EndsWith('Type') and (URType.TypeKind = tkRecord))) then
                PVal := UFValue.GetValue(PVal.GetReferenceToRawData);
            end;
          end;

          if PVal.IsEmpty then
             FParams.Add(ParamName, TValue.Empty)
          else
             FParams.Add(ParamName, PVal);
             
          if I > 0 then ParamNames.Append(', ');
          ParamNames.Append(':').Append(ParamName);
        end;
        
        FSQL.Append('(');
        ResolveSQL(C.Left);
        FSQL.Append(' ')
            .Append(GetBinaryOpSQL(C.BinaryOperator))
            .Append(' (')
            .Append(ParamNames.ToString)
            .Append('))');
      finally
        ParamNames.Free;
      end;
      Exit;
    end;
  end;

  DialectEnum := ResolveDialect(FDialect);

  FSQL.Append('(');
  ResolveSQL(C.Left);
  FSQL.Append(' ');
  if (C.Right is TLiteralExpression) and
    UsesStartingWith(C.BinaryOperator, DialectEnum) then
    FSQL.Append('STARTING WITH')
  else
    FSQL.Append(GetBinaryOpSQL(C.BinaryOperator));
  FSQL.Append(' ');

  if C.Right is TLiteralExpression then
  begin
    Lit := TLiteralExpression(C.Right);
    ParamName := GetNextParamName;

    // StartsWith / EndsWith / Contains: the value is matched literally, so
    // its % and _ are escaped and the LIKE says which escape character it
    // uses; STARTING WITH has no wildcards. The parameter is always a plain
    // string (no uuid/text cast).
    if C.BinaryOperator in [boStartsWith, boEndsWith, boContains] then
    begin
      FParams.Add(ParamName, TValue.From<string>(LiteralMatchValue(
        Lit.Value.ToString, C.BinaryOperator, DialectEnum)));
      FSQL.Append(':').Append(ParamName);
      if not UsesStartingWith(C.BinaryOperator, DialectEnum) then
        FSQL.Append(' ESCAPE ''').Append(LikeEscapeChar).Append('''');
      FSQL.Append(')');
      Exit;
    end;

    FParams.Add(ParamName, Lit.Value);
    
    // Type converter support for SQL casting in WHERE clause
    Converter := TTypeConverterRegistry.Instance.GetConverter(Lit.Value.TypeInfo);
    
    // When comparing JSON property extraction result (returns TEXT) with non-string values,
    // we need to cast the parameter to TEXT for PostgreSQL
    if (DialectEnum = ddPostgreSQL) and (C.Left is TJsonPropertyExpression) and
       (Lit.Value.Kind in [tkInteger, tkInt64, tkFloat]) then
    begin
      SQLCast := ':' + ParamName + '::text';
    end
    else if (DialectEnum = ddPostgreSQL) and 
       ((Lit.Value.TypeInfo = TypeInfo(TGUID)) or 
        (Lit.Value.TypeInfo = TypeInfo(TUUID)) or
        ((Lit.Value.Kind in [tkString, tkUString, tkWString]) and
         ((Length(Lit.Value.AsString) = 36) or (Length(Lit.Value.AsString) = 38)) and
         (Lit.Value.AsString.IndexOf('-') > 0))) then
    begin
       SQLCast := ':' + ParamName + '::uuid';
    end
    else if Converter <> nil then
    begin
      SQLCast := Converter.GetSQLCast(':' + ParamName, DialectEnum);
    end
    else
      SQLCast := ':' + ParamName;

    FSQL.Append(SQLCast);
  end
  else
    ResolveSQL(C.Right);

  FSQL.Append(')');
end;

procedure TSQLWhereGenerator.ProcessArithmetic(const C: TArithmeticExpression);
begin
  FSQL.Append('(');
  ResolveSQL(C.Left);
  FSQL.Append(' ')
      .Append(GetArithmeticOpSQL(C.ArithmeticOperator))
      .Append(' ');
  ResolveSQL(C.Right);
  FSQL.Append(')');
end;

procedure TSQLWhereGenerator.ProcessLogical(const C: TLogicalExpression);
begin
  FSQL.Append('(');
  ResolveSQL(C.Left);
  FSQL.Append(' ')
      .Append(GetLogicalOpSQL(C.LogicalOperator))
      .Append(' ');
  ResolveSQL(C.Right);
  FSQL.Append(')');
end;

procedure TSQLWhereGenerator.ProcessUnary(const C: TUnaryExpression);
begin
  if C.UnaryOperator = uoNot then
  begin
    FSQL.Append('(NOT ');
    ResolveSQL(C.Expression);
    FSQL.Append(')');
  end
  else
  begin
    // IsNull / IsNotNull
    FSQL.Append('(');
    if C.Expression <> nil then
      ResolveSQL(C.Expression)
    else
      FSQL.Append(QuoteColumnOrAlias(MapColumn(C.PropertyName)));
    
    FSQL.Append(' ')
        .Append(GetUnaryOpSQL(C.UnaryOperator))
        .Append(')');
  end;
end;

procedure TSQLWhereGenerator.ProcessProperty(const C: TPropertyExpression);
begin
  FSQL.Append(QuoteColumnOrAlias(MapColumn(C.PropertyName)));
end;

procedure TSQLWhereGenerator.ProcessJsonProperty(const C: TJsonPropertyExpression);
var
  Mapped: string;
begin
  Mapped := MapColumn(C.PropertyName);
  FSQL.Append(FDialect.GetJsonValueSQL(QuoteColumnOrAlias(Mapped), C.JsonPath));
end;

procedure TSQLWhereGenerator.ProcessLiteral(const C: TLiteralExpression);
var
  ParamName: string;
begin
  ParamName := GetNextParamName;
  FParams.Add(ParamName, C.Value);
  FSQL.Append(':').Append(ParamName);
end;

procedure TSQLWhereGenerator.ProcessConstant(const C: TConstantExpression);
begin
  if C.Value then
    FSQL.Append('(1=1)')
  else
    FSQL.Append('(1=0)');
end;

function TSQLWhereGenerator.GetBinaryOpSQL(Op: TBinaryOperator): string;
begin
  case Op of
    boEqual: Result := '=';
    boNotEqual: Result := '<>';
    boGreaterThan: Result := '>';
    boGreaterThanOrEqual: Result := '>=';
    boLessThan: Result := '<';
    boLessThanOrEqual: Result := '<=';
    boLike: Result := 'LIKE';
    boNotLike: Result := 'NOT LIKE';
    boIn: Result := 'IN';
    boNotIn: Result := 'NOT IN';
    boStartsWith, boEndsWith, boContains: Result := 'LIKE';
    boBitwiseAnd: Result := '&';
    boBitwiseOr: Result := '|';
    boBitwiseXor: Result := '#';
  else
    Result := '=';
  end;
end;

function TSQLWhereGenerator.GetArithmeticOpSQL(Op: TArithmeticOperator): string;
begin
  case Op of
    aoAdd: Result := '+';
    aoSubtract: Result := '-';
    aoMultiply: Result := '*';
    aoDivide: Result := '/';
    aoModulus: Result := '%';
    aoIntDivide: Result := '/';
  else
    Result := '+';
  end;
end;

function TSQLWhereGenerator.GetLogicalOpSQL(Op: TLogicalOperator): string;
begin
  case Op of
    loAnd: Result := 'AND';
    loOr: Result := 'OR';
  else
    Result := 'AND';
  end;
end;

function TSQLWhereGenerator.GetUnaryOpSQL(Op: TUnaryOperator): string;
begin
  case Op of
    uoIsNull: Result := 'IS NULL';
    uoIsNotNull: Result := 'IS NOT NULL';
  else
    Result := '';
  end;
end;

{ TSQLColumnMapper<T> }

constructor TSQLColumnMapper<T>.Create(ANamingStrategy: INamingStrategy);
begin
  inherited Create;
  FNamingStrategy := ANamingStrategy;
end;

destructor TSQLColumnMapper<T>.Destroy;
begin
  inherited;
end;

function TSQLColumnMapper<T>.MapColumn(const AName: string): string;
var
  Typ: TRttiType;
  Prop: TRttiProperty;
  Attr: TCustomAttribute;
  PropMap: TPropertyMap;
begin
  Result := AName;
  Typ := TReflection.GetMetadata(TypeInfo(T)).RttiType;
  Prop := Typ.GetProperty(AName);
  if Prop <> nil then
  begin
    PropMap := nil;
    if TModelBuilder.Instance.HasMap(TypeInfo(T)) then
      TModelBuilder.Instance.GetMap(TypeInfo(T)).Properties.TryGetValue(Prop.Name, PropMap);

    if (PropMap <> nil) and (PropMap.ColumnName <> '') then
      Exit(PropMap.ColumnName);

    for Attr in Prop.GetAttributes do
    begin
      if Attr is ColumnAttribute then Exit(ColumnAttribute(Attr).Name);
      if Attr is ForeignKeyAttribute then Exit(ForeignKeyAttribute(Attr).ColumnName);
    end;

    if (Result = Prop.Name) and (FNamingStrategy <> nil) then
      Result := FNamingStrategy.GetColumnName(Prop);
  end;
end;

{ TSQLGenerator<T> }

constructor TSQLGenerator<T>.Create(AContext: IDbContext; AMap: TEntityMap; ATenantProvider: ITenantProvider);
begin
  Initialize(AContext.Dialect, AMap, ATenantProvider);
  FContext := AContext;
  if FContext <> nil then
    FNamingStrategy := FContext.NamingStrategy;
end;

constructor TSQLGenerator<T>.Create(ADialect: ISQLDialect; AMap: TEntityMap; ATenantProvider: ITenantProvider);
begin
  Initialize(ADialect, AMap, ATenantProvider);
end;

procedure TSQLGenerator<T>.Initialize(ADialect: ISQLDialect; AMap: TEntityMap; ATenantProvider: ITenantProvider);
begin
  FDialect := ADialect;
  FMap := AMap;
  if FMap = nil then
    FMap := TModelBuilder.Instance.GetMap(TypeInfo(T));
    
  if FMap <> nil then
    FSchema := FMap.Schema;
    
  if (FNamingStrategy = nil) then
    FNamingStrategy := TDefaultNamingStrategy.Create;

  FTenantProvider := ATenantProvider;
  FParams := TCollections.CreateDictionary<string, TValue>;
  FParamTypes := TCollections.CreateDictionary<string, TFieldType>;
  FParamCount := 0;
end;

destructor TSQLGenerator<T>.Destroy;
begin
  FParams := nil;
  FParamTypes := nil;
  inherited;
end;

function TSQLGenerator<T>.GetNextParamName: string;
begin
  Inc(FParamCount);
  Result := 'p' + IntToStr(FParamCount);
end;

function TSQLGenerator<T>.IsTenantAwareEntity: Boolean;
begin
  Result := (PTypeInfo(TypeInfo(T)).Kind = tkClass) and
    (GetTypeData(TypeInfo(T))^.ClassType.GetInterfaceEntry(ITenantAware) <> nil);
end;

procedure TSQLGenerator<T>.AppendTenantWhereParams(SBWhere: TStringBuilder;
  var AFirstWhere: Boolean);
var
  ParamName: string;
begin
  if FIgnoreQueryFilters then
    Exit;
  if not IsTenantAwareEntity then
    Exit;
  if (FTenantProvider = nil) or (FTenantProvider.Tenant = nil) then
    Exit;

  ParamName := GetNextParamName;
  FParams.Add(ParamName, FTenantProvider.Tenant.Id);
  if not AFirstWhere then
    SBWhere.Append(' AND ');
  AFirstWhere := False;
  SBWhere.Append(FDialect.QuoteIdentifier('TenantId')).Append(' = :').Append(ParamName);
end;

procedure TSQLGenerator<T>.AppendTenantWhereTemplate(SBWhere: TStringBuilder;
  var AFirstWhere: Boolean; AWhereProps: IList<TPair<TRttiProperty, string>>);
var
  Typ: TRttiType;
  Prop: TRttiProperty;
  TenantProp: TRttiProperty;
begin
  if FIgnoreQueryFilters then
    Exit;
  if not IsTenantAwareEntity then
    Exit;
  if (FTenantProvider = nil) or (FTenantProvider.Tenant = nil) then
    Exit;
  if AWhereProps = nil then
    Exit;

  TenantProp := nil;
  Typ := TReflection.Context.GetType(TypeInfo(T));
  for Prop in Typ.GetProperties do
    if SameText(Prop.Name, 'TenantId') then
    begin
      TenantProp := Prop;
      Break;
    end;
  if TenantProp = nil then
    Exit;

  if not AFirstWhere then
    SBWhere.Append(' AND ');
  AFirstWhere := False;
  SBWhere.Append(FDialect.QuoteIdentifier('TenantId')).Append(' = :TenantId');
  AWhereProps.Add(TPair<TRttiProperty, string>.Create(TenantProp, 'TenantId'));
end;

function TSQLGenerator<T>.GetTableName: string;
var
  Typ: TRttiType;
  Attr: TCustomAttribute;
  LSortedSchema: string;
  LDotPos: Integer;
  LRawTable: string;
begin
  if (FMap <> nil) and (FMap.TableName <> '') then
    LRawTable := FMap.TableName
  else
  begin
    LRawTable := '';
    Typ := TReflection.Context.GetType(T);
    
    // Check TableAttribute
    for Attr in Typ.GetAttributes do
      if Attr is TableAttribute then
        if TableAttribute(Attr).Name <> '' then
          LRawTable := TableAttribute(Attr).Name;
    
    // Fallback to NamingStrategy or class name
    if LRawTable = '' then
    begin
      if FNamingStrategy <> nil then
        LRawTable := FNamingStrategy.GetTableName(T)
      else
      begin
        // Ultimate fallback: remove T prefix from class name
        LRawTable := Typ.Name;
        if (Length(LRawTable) > 1) and (LRawTable[1] = 'T') and CharInSet(LRawTable[2], ['A'..'Z']) then
          LRawTable := Copy(LRawTable, 2, MaxInt);
      end;
    end;
  end;

  // Resolve active schema: Tenant (Dynamic) > Entity Map (Static)
  LSortedSchema := FSchema;
  if (FTenantProvider <> nil) and (FTenantProvider.Tenant <> nil) and (FTenantProvider.Tenant.Schema <> '') then
    LSortedSchema := FTenantProvider.Tenant.Schema;

  // Split schema if provided in table name (e.g. 'schema.table')
  LDotPos := LRawTable.IndexOf('.');
  if LDotPos >= 0 then
  begin
    if LSortedSchema = '' then
      LSortedSchema := LRawTable.Substring(0, LDotPos);
    LRawTable := LRawTable.Substring(LDotPos + 1);
  end;

  // Final Quote
  Result := FDialect.QuoteIdentifier(LRawTable);
  
  if (LSortedSchema <> '') and FDialect.UseSchemaPrefix then
    Result := FDialect.QuoteIdentifier(LSortedSchema) + '.' + Result;
end;

function TSQLGenerator<T>.TryUnwrapSmartValue(var AValue: TValue): Boolean;
begin
  Result := TReflection.TryUnwrapProp(AValue, AValue);
end;

function TSQLGenerator<T>.QualifyBaseColumn(const AColumnName, ABaseTableName: string;
  AHasJoins: Boolean): string;
begin
  if AColumnName.Contains('.') then
    Exit(QuoteColumnOrAlias(AColumnName));

  if AHasJoins then
    Exit(ABaseTableName + '.' + FDialect.QuoteIdentifier(AColumnName));

  Result := FDialect.QuoteIdentifier(AColumnName);
end;

function TSQLGenerator<T>.GetSoftDeleteFilter: string;
var
  Attr: TCustomAttribute;
  IsSoftDelete: Boolean;
  DeletedVal, NotDeletedVal: Variant;
  Prop: TRttiProperty;
  PropMap: TPropertyMap;
  ColumnName: string;
  PropName: string;
  SoftDeleteAttr: SoftDeleteAttribute;
  TargetPropType: PTypeInfo;
  Typ: TRttiType;
  LiteralVal: string;
  IsTargetBool: Boolean;
  BoolVal: Boolean;
  PropColumnName: string;
begin
  Result := '';
  IsSoftDelete := False;
  PropName := '';
  DeletedVal := True;
  NotDeletedVal := False;
  TargetPropType := nil;
  
  Typ := TReflection.Context.GetType(T);
  if Typ = nil then Exit;
  
  if (FMap <> nil) and FMap.IsSoftDelete then
  begin
    IsSoftDelete := True;
    PropName := FMap.SoftDeleteProp;
    DeletedVal := FMap.SoftDeleteDeletedValue;
    NotDeletedVal := FMap.SoftDeleteNotDeletedValue;
  end
  else
  begin
    for Attr in Typ.GetAttributes do
    begin
      if Attr is SoftDeleteAttribute then
      begin
        SoftDeleteAttr := SoftDeleteAttribute(Attr);
        IsSoftDelete := True;
        PropName := SoftDeleteAttr.ColumnName;
        DeletedVal := SoftDeleteAttr.DeletedValue;
        NotDeletedVal := SoftDeleteAttr.NotDeletedValue;
        Break;
      end;
    end;
  end;

  if not IsSoftDelete then Exit;

  ColumnName := PropName;

  for Prop in Typ.GetProperties do
  begin
    PropColumnName := Prop.Name;

    if (FMap <> nil) and FMap.Properties.TryGetValue(Prop.Name, PropMap) then
    begin
       if PropMap.ColumnName <> '' then PropColumnName := PropMap.ColumnName;
    end
    else
    begin
      for Attr in Prop.GetAttributes do
      begin
        if Attr is ColumnAttribute then
        begin
          PropColumnName := ColumnAttribute(Attr).Name;
          Break;
        end;
      end;
    end;

    if SameText(Prop.Name, PropName) or SameText(PropColumnName, PropName) then
    begin
      if (PropColumnName = Prop.Name) and (FNamingStrategy <> nil) then
        PropColumnName := FNamingStrategy.GetColumnName(Prop);

      ColumnName := PropColumnName;
      TargetPropType := Prop.PropertyType.Handle;
      
      // Check if it's a Timestamp-based soft delete
      if (PropMap <> nil) and PropMap.IsDeletedAt then
      begin
        if FIgnoreQueryFilters then Exit('');
        
        if FOnlyDeleted then
          Result := Format('%s IS NOT NULL', [FDialect.QuoteIdentifier(ColumnName)])
        else
          Result := Format('%s IS NULL', [FDialect.QuoteIdentifier(ColumnName)]);
        Exit;
      end;
      
      Break;
    end;
  end;

  if FIgnoreQueryFilters then Exit;

  if FOnlyDeleted then
  begin
     IsTargetBool := (TargetPropType <> nil) and
       ((TargetPropType = TypeInfo(Boolean)) or (SameText(string(TargetPropType.Name), 'Boolean')));

     if IsTargetBool then
     begin
       if VarIsType(DeletedVal, varBoolean) then
         BoolVal := DeletedVal
       else if VarIsNumeric(DeletedVal) then
         BoolVal := (Integer(DeletedVal) <> 0)
       else
         BoolVal := StrToBoolDef(VarToStr(DeletedVal), True);
       
       LiteralVal := FDialect.BooleanToSQL(BoolVal);
     end
     else if VarIsType(DeletedVal, varBoolean) then
     begin
        LiteralVal := FDialect.BooleanToSQL(DeletedVal);
     end
     else if VarIsNull(DeletedVal) then
     begin
        LiteralVal := 'NULL';
     end
     else
     begin
       LiteralVal := VarToStr(DeletedVal);
       if VarIsType(DeletedVal, varString) or VarIsType(DeletedVal, varUString) then
         LiteralVal := QuotedStr(LiteralVal);
     end;

     if LiteralVal = 'NULL' then
       Result := Format('%s IS NULL', [FDialect.QuoteIdentifier(ColumnName)])
     else
       Result := Format('%s = %s', [FDialect.QuoteIdentifier(ColumnName), LiteralVal]);
  end
  else
  begin
     IsTargetBool := (TargetPropType <> nil) and
       ((TargetPropType = TypeInfo(Boolean)) or (SameText(string(TargetPropType.Name), 'Boolean')));

     if IsTargetBool then
     begin
       if VarIsType(NotDeletedVal, varBoolean) then
         BoolVal := NotDeletedVal
       else if VarIsNumeric(NotDeletedVal) then
         BoolVal := (Integer(NotDeletedVal) <> 0)
       else
         BoolVal := StrToBoolDef(VarToStr(NotDeletedVal), False);
       
       LiteralVal := FDialect.BooleanToSQL(BoolVal);
     end
     else if VarIsType(NotDeletedVal, varBoolean) then
     begin
       LiteralVal := FDialect.BooleanToSQL(NotDeletedVal);
     end
     else if VarIsNull(NotDeletedVal) then
     begin
        LiteralVal := 'NULL';
     end
     else
     begin
       LiteralVal := VarToStr(NotDeletedVal);
       if VarIsType(NotDeletedVal, varString) or VarIsType(NotDeletedVal, varUString) then
         LiteralVal := QuotedStr(LiteralVal);
     end;
   
     if LiteralVal = 'NULL' then
        Result := Format('%s IS NULL', [FDialect.QuoteIdentifier(ColumnName)])
     else
        Result := Format('COALESCE(%s, %s) = %s',
          [FDialect.QuoteIdentifier(ColumnName), LiteralVal, LiteralVal]);
  end;
end;

function TSQLGenerator<T>.GetDiscriminatorValueSQL: string;
begin
  if (FMap <> nil) and (FMap.DiscriminatorValue <> Null) then
  begin
    if VarIsType(FMap.DiscriminatorValue, varString) or VarIsType(FMap.DiscriminatorValue, varUString) then
      Result := QuotedStr(VarToStr(FMap.DiscriminatorValue))
    else
      Result := VarToStr(FMap.DiscriminatorValue);
  end
  else
    Result := 'NULL';
end;

function TSQLGenerator<T>.GetDiscriminatorFilter: string;
begin
  Result := '';
  if (FMap <> nil) and (FMap.InheritanceStrategy = TInheritanceStrategy.TablePerHierarchy) and 
     (FMap.DiscriminatorColumn <> '') and (GetDiscriminatorValueSQL <> 'NULL') then
  begin
    Result := FDialect.QuoteIdentifier(FMap.DiscriminatorColumn) + ' = ' + GetDiscriminatorValueSQL;
    // Note: DiscriminatorColumn should be quoted if needed, but FMap usually has raw name. 
    // Ideally use FDialect.QuoteIdentifier(FMap.DiscriminatorColumn).
    // Let's fix that below.
  end;
end;

function TSQLGenerator<T>.IsHierarchyMember: Boolean;
begin
  Result := (FMap <> nil) and (FContext <> nil) and (FContext.ModelBuilder <> nil) and
    (FMap.InheritanceStrategy = TInheritanceStrategy.TablePerHierarchy) and
    (FMap.DiscriminatorColumn <> '');
end;

function TSQLGenerator<T>.IsRootMap(AMap: TEntityMap): Boolean;
begin
  Result := VarIsNull(AMap.DiscriminatorValue) or VarIsEmpty(AMap.DiscriminatorValue);
end;

// The topmost mapped class of the hierarchy, or nil when T is not in one.
function TSQLGenerator<T>.GetHierarchyRoot: TEntityMap;
var
  Cls: TClass;
  Info: PTypeInfo;
begin
  Result := nil;
  if not IsHierarchyMember then Exit;
  Result := FMap;
  if IsRootMap(FMap) then Exit;
  Cls := GetTypeData(FMap.EntityType)^.ClassType.ClassParent;
  while Cls <> nil do
  begin
    Info := Cls.ClassInfo;
    if (Info <> nil) and FContext.ModelBuilder.HasMap(Info) and
       (FContext.ModelBuilder.GetMap(Info).InheritanceStrategy =
        TInheritanceStrategy.TablePerHierarchy) then
      Result := FContext.ModelBuilder.GetMap(Info);
    Cls := Cls.ClassParent;
  end;
end;

function TSQLGenerator<T>.GetSubtypeMaps(ARoot: TEntityMap): TArray<TEntityMap>;
var
  Map: TEntityMap;
  RootClass, MapClass: TClass;
  List: IList<TEntityMap>;
begin
  List := TCollections.CreateList<TEntityMap>;
  RootClass := GetTypeData(ARoot.EntityType)^.ClassType;
  for Map in FContext.ModelBuilder.GetMaps do
  begin
    if Map = ARoot then Continue;
    if Map.InheritanceStrategy <> TInheritanceStrategy.TablePerHierarchy then Continue;
    MapClass := GetTypeData(Map.EntityType)^.ClassType;
    if MapClass.InheritsFrom(RootClass) then
      List.Add(Map);
  end;
  Result := List.ToArray;
end;

// For the root set: the discriminator and the columns of every subclass, so a
// query on the root can build the right subclass and fill its properties.
function TSQLGenerator<T>.GetHierarchyColumns: TArray<string>;
var
  List: IList<string>;
  Map: TEntityMap;
  Col: TDeclaredColumn;
begin
  SetLength(Result, 0);
  if (not IsHierarchyMember) or (not IsRootMap(FMap)) then Exit;
  List := TCollections.CreateList<string>;
  List.Add(FMap.DiscriminatorColumn);
  for Map in GetSubtypeMaps(FMap) do
    for Col in TSQLGeneratorHelper.GetDeclaredColumns(Map, FNamingStrategy) do
      if not List.Contains(Col.ColumnName) then
        List.Add(Col.ColumnName);
  Result := List.ToArray;
end;

class function TSQLGeneratorHelper.GetDeclaredColumns(AMap: TEntityMap;
  ANamingStrategy: INamingStrategy): TArray<TDeclaredColumn>;
var
  Typ: TRttiType;
  Prop: TRttiProperty;
  PropMap: TPropertyMap;
  Attr: TCustomAttribute;
  ColName: string;
  IsMapped: Boolean;
  LKind: TTypeKind;
  List: IList<TDeclaredColumn>;
  Item: TDeclaredColumn;
begin
  List := TCollections.CreateList<TDeclaredColumn>;
  Typ := TReflection.Context.GetType(AMap.EntityType);
  if Typ <> nil then
    for Prop in Typ.GetProperties do
    begin
      if Prop.Parent.Handle <> Typ.Handle then Continue;
      ColName := Prop.Name;
      IsMapped := True;
      PropMap := nil;
      AMap.Properties.TryGetValue(Prop.Name, PropMap);
      if PropMap <> nil then
      begin
        if PropMap.IsIgnored or PropMap.IsNavigation or PropMap.IsLazy then IsMapped := False;
        if PropMap.ColumnName <> '' then ColName := PropMap.ColumnName;
      end;
      for Attr in Prop.GetAttributes do
      begin
        if Attr is NotMappedAttribute then IsMapped := False;
        if ((PropMap = nil) or (PropMap.ColumnName = '')) and (Attr is ColumnAttribute) then
          ColName := ColumnAttribute(Attr).Name;
      end;
      LKind := Prop.PropertyType.TypeKind;
      if (LKind in [tkClass, tkInterface]) and ((PropMap = nil) or (not PropMap.IsJsonColumn)) then
        IsMapped := False;
      if (LKind = tkRecord) and Prop.PropertyType.Name.StartsWith('Lazy<') then
        IsMapped := False;
      if not IsMapped then Continue;
      if (ColName = Prop.Name) and (ANamingStrategy <> nil) then
        ColName := ANamingStrategy.GetColumnName(Prop);
      Item.Prop := Prop;
      Item.ColumnName := ColName;
      List.Add(Item);
    end;
  Result := List.ToArray;
end;

function TSQLGenerator<T>.GetDialectEnum: TDatabaseDialect;
begin
  if FDialect <> nil then
    Result := FDialect.GetDialect
  else
    Result := ddUnknown;
end;

function TSQLGenerator<T>.GetQueryFiltersSQL: string;
var
  Filter: IExpression;
  WhereGen: TSQLWhereGenerator;
  SB: TStringBuilder;
  Pair: TPair<string, TValue>;
begin
  Result := '';
  if FIgnoreQueryFilters then Exit;
  if (FMap = nil) or (FMap.QueryFilters.Count = 0) then Exit;

  SB := TStringBuilder.Create;
  try
    WhereGen := TSQLWhereGenerator.Create(FDialect, TSQLColumnMapper<T>.Create(FNamingStrategy));
    try
      // Pass the current parameter count to avoid collisions
      WhereGen.ParamCount := FParamCount;
      
      for Filter in FMap.QueryFilters do
      begin
        if SB.Length > 0 then SB.Append(' AND ');
        SB.Append(WhereGen.Generate(Filter));
        
        // Merge Params
        for Pair in WhereGen.Params do
          FParams.AddOrSetValue(Pair.Key, Pair.Value);
          
        // Update local count
        FParamCount := WhereGen.ParamCount;
      end;
      Result := SB.ToString;
    finally
      WhereGen.Free;
    end;
  finally
    SB.Free;
  end;

end;

function TSQLGenerator<T>.GenerateInsert(const AEntity: T): string;
var
  ColName, ParamName: string;
  SBCols, SBVals: TStringBuilder;
  IsAutoInc, IsMapped, First: Boolean;
  Val: TValue;
  Converter: ITypeConverter;
  PropMap: TPropertyMap;
  Meta: TTypeMetadata;
  Handler: IPropertyHandler;
begin
  FParams.Clear;
  FParamTypes.Clear;
  FParamCount := 0;
  SBCols := TStringBuilder.Create;
  SBVals := TStringBuilder.Create;
  try
    First := True;
    
    Meta := TReflection.GetMetadata(TypeInfo(T));
    for Handler in Meta.GetPropertyHandlers() do
    begin
      IsMapped := True;
      IsAutoInc := Handler.GetIsAutoInc();
      ColName := Handler.GetColumnName();
      
      PropMap := nil;
      if FMap <> nil then
        FMap.Properties.TryGetValue(Handler.GetName(), PropMap);
        
      if PropMap <> nil then
      begin
        if PropMap.IsIgnored then IsMapped := False;
        if PropMap.IsNavigation and not PropMap.IsJsonColumn then IsMapped := False;
        if PropMap.IsAutoInc then IsAutoInc := True;
        if PropMap.ColumnName <> '' then ColName := PropMap.ColumnName;
      end;

      if IsMapped and (PropMap = nil) and (Handler.GetMember() is TRttiProperty) and 
         (TRttiProperty(Handler.GetMember()).PropertyType.TypeKind in [tkClass, tkInterface]) then
        IsMapped := False;

      if IsMapped and Handler.GetMember().HasAttribute(NotMappedAttribute) then IsMapped := False;
      
      if IsMapped and ((Handler.GetMember().HasAttribute(HasManyAttribute)) or (Handler.GetMember().HasAttribute(BelongsToAttribute)) or 
         (Handler.GetMember().HasAttribute(HasOneAttribute)) or (Handler.GetMember().HasAttribute(ManyToManyAttribute))) then
        IsMapped := False;

      if Handler.GetMember().HasAttribute(JsonColumnAttribute) then IsMapped := True;
      
      if (ColName = Handler.GetName()) and (FNamingStrategy <> nil) and (Handler.GetMember() is TRttiProperty) then
         ColName := FNamingStrategy.GetColumnName(TRttiProperty(Handler.GetMember()));
      
      if not IsMapped or IsAutoInc then Continue;
      
      if not First then
      begin
        SBCols.Append(', ');
        SBVals.Append(', ');
      end;
      First := False;
      
      SBCols.Append(FDialect.QuoteIdentifier(ColName));
      
      Val := Handler.GetValue(Pointer(AEntity));

      // Unwrap Nullable<T> and Prop<T> (Smart Type)
      TryUnwrapSmartValue(Val);



      // DateTime Range Guard: out-of-range (< 1900-01-01) -> NULL
      if (Val.Kind = tkFloat) and (Val.AsExtended < 2.0) and
         (((PropMap <> nil) and
           (PropMap.DataType in [ftDateTime, ftDate, ftTime])) or
          (Val.TypeInfo = TypeInfo(TDateTime)) or
          (Val.TypeInfo = TypeInfo(TDate)) or
          (Val.TypeInfo = TypeInfo(TTime))) then
      begin
        SBVals.Append('NULL');
        Continue;
      end;

      // After unwrapping, check if the value is Null or Empty
      if Val.IsEmpty then
      begin
        SBVals.Append('NULL');
        Continue; 
      end;

      ParamName := GetNextParamName;
      
      // Look up converter: PropMap -> Registry -> [JsonColumn] auto-detect
      Converter := nil;
      if PropMap <> nil then
        Converter := PropMap.Converter;
        
      if Converter = nil then
        Converter := TTypeConverterRegistry.Instance.GetConverter(Val.TypeInfo);
      
      if (Converter = nil) and (PropMap <> nil) and PropMap.IsJsonColumn then
        Converter := TJsonConverter.Create(PropMap.UseJsonB);
        
      if (GetDialectEnum <> ddSQLite) and (Converter <> nil) then
        SBVals.Append(Converter.GetSQLCast(':' + ParamName, GetDialectEnum))
      else
        SBVals.Append(':').Append(ParamName);
        
      if Converter <> nil then
        Val := Converter.ToDatabase(Val, GetDialectEnum);
        
      FParams.Add(ParamName, Val);
      
      // Store explicit type if defined via [DbType] attribute
      if (PropMap <> nil) and (PropMap.DataType <> ftUnknown) then
        FParamTypes.Add(ParamName, PropMap.DataType);
    end;
    
    // Add SHADOW PROPERTIES
    if (FMap <> nil) and (FContext <> nil) then
    begin
      for PropMap in FMap.Properties.Values do
      begin
        if PropMap.IsShadow and not PropMap.IsIgnored then
        begin
          ColName := PropMap.ColumnName;
          if ColName = '' then ColName := PropMap.PropertyName;
          
          if not First then
          begin
            SBCols.Append(', ');
            SBVals.Append(', ');
          end;
          First := False;
          
          SBCols.Append(FDialect.QuoteIdentifier(ColName));
          
          Val := FContext.Entry(AEntity).Member(PropMap.PropertyName).CurrentValue;
          TryUnwrapSmartValue(Val);
          
          if Val.IsEmpty then
          begin
            SBVals.Append('NULL');
            Continue;
          end;
          
          ParamName := GetNextParamName;
          
          Converter := PropMap.Converter;
          if (Converter = nil) and PropMap.IsJsonColumn then
            Converter := TJsonConverter.Create(PropMap.UseJsonB);

          if (Converter = nil) then
             Converter := TTypeConverterRegistry.Instance.GetConverter(Val.TypeInfo);
            
          if (GetDialectEnum <> ddSQLite) and (Converter <> nil) then
            SBVals.Append(Converter.GetSQLCast(':' + ParamName, GetDialectEnum))
          else
            SBVals.Append(':').Append(ParamName);
            
          if Converter <> nil then
            Val := Converter.ToDatabase(Val, GetDialectEnum);
            
          FParams.Add(ParamName, Val);
          if PropMap.DataType <> ftUnknown then
            FParamTypes.Add(ParamName, PropMap.DataType);
        end;
      end;
    end;

    // Add Discriminator
    if (FMap <> nil) and (FMap.InheritanceStrategy = TInheritanceStrategy.TablePerHierarchy) and 
       (FMap.DiscriminatorColumn <> '') then
    begin
       // Check if already added? (Optimization: explicit loop check or just trust map setup usually implies shadow)
       // For now, simpler: assume shadow property if configured via HasDiscriminator
       // If a property maps to it, IsMapped would be true.
       // We can check if SBCols contains the column name... but string search is flaky.
       // Let's rely on standard practice: If users map it properly, they shouldn't use HasDiscriminator with const value?
       // Actually HasDiscriminator SETS the value.
       
       // Safe Add:
       if not SBCols.ToString.Contains(FDialect.QuoteIdentifier(FMap.DiscriminatorColumn)) then
       begin
         if SBCols.Length > 0 then
         begin
           SBCols.Append(', ');
           SBVals.Append(', ');
         end;
         SBCols.Append(FDialect.QuoteIdentifier(FMap.DiscriminatorColumn));
         SBVals.Append(GetDiscriminatorValueSQL);
       end;
    end;

    Result := Format('INSERT INTO %s (%s) VALUES (%s)', 
      [GetTableName, SBCols.ToString, SBVals.ToString]);
      
  finally
    SBCols.Free;
    SBVals.Free;
  end;
end;

function TSQLGenerator<T>.GenerateInsertTemplate(out AProps: IList<TPair<TRttiProperty, string>>): string;
var
  ColName: string;
  SBCols, SBVals: TStringBuilder;
  IsAutoInc, IsMapped, First: Boolean;
  PropMap: TPropertyMap;
  Meta: TTypeMetadata;
  Handler: IPropertyHandler;
  Converter: ITypeConverter;
  ValueSQL: string;
begin
  SBCols := TStringBuilder.Create;
  SBVals := TStringBuilder.Create;
  AProps := TCollections.CreateList<TPair<TRttiProperty, string>>;
  First := True;
  
  try
    Meta := TReflection.GetMetadata(TypeInfo(T));
    for Handler in Meta.GetPropertyHandlers() do
    begin
      IsMapped := True;
      IsAutoInc := Handler.GetIsAutoInc();
      ColName := Handler.GetColumnName();
      
      PropMap := nil;
      if FMap <> nil then
        FMap.Properties.TryGetValue(Handler.GetName(), PropMap);
        
      if PropMap <> nil then
      begin
        if PropMap.IsIgnored then IsMapped := False;
        if PropMap.IsNavigation then IsMapped := False;
        if PropMap.IsAutoInc then IsAutoInc := True;
        if PropMap.ColumnName <> '' then ColName := PropMap.ColumnName;
      end;

      if IsMapped and Handler.GetMember().HasAttribute(NotMappedAttribute) then IsMapped := False;
      
      if (ColName = Handler.GetName()) and (FNamingStrategy <> nil) and (Handler.GetMember() is TRttiProperty) then
         ColName := FNamingStrategy.GetColumnName(TRttiProperty(Handler.GetMember()));
      
      if not IsMapped or IsAutoInc then Continue;
      
      AProps.Add(TPair<TRttiProperty, string>.Create(TRttiProperty(Handler.GetMember()), ColName));
      
      if not First then
      begin
        SBCols.Append(', ');
        SBVals.Append(', ');
      end;
      First := False;
      
      SBCols.Append(FDialect.QuoteIdentifier(ColName));
      // Use Column Name as Parameter Name for Array DML. A column whose converter
      // needs a cast (jsonb, uuid on PostgreSQL) gets it, as in the single-row INSERT.
      ValueSQL := ':' + ColName;
      Converter := nil;
      if PropMap <> nil then Converter := PropMap.Converter;
      if (Converter = nil) and (Handler.GetMember() is TRttiProperty) then
        Converter := TTypeConverterRegistry.Instance.GetConverter(
          TRttiProperty(Handler.GetMember()).PropertyType.Handle);
      if (Converter = nil) and (PropMap <> nil) and PropMap.IsJsonColumn then
        Converter := TJsonConverter.Create(PropMap.UseJsonB);
      if Converter <> nil then
        ValueSQL := Converter.GetSQLCast(ValueSQL, GetDialectEnum);
      SBVals.Append(ValueSQL);
    end;
    
    Result := Format('INSERT INTO %s (%s) VALUES (%s)', 
      [GetTableName, SBCols.ToString, SBVals.ToString]);
      
  finally
    SBCols.Free;
    SBVals.Free;
    // AProps is returned, caller must free
  end;
end;

function TSQLGenerator<T>.GenerateUpdateTemplate(out ASetProps, AWhereProps: IList<TPair<TRttiProperty, string>>): string;
var
  ColName: string;
  SBSet, SBWhere: TStringBuilder;
  IsPK, IsMapped, FirstSet, FirstWhere: Boolean;
  PropMap: TPropertyMap;
  Meta: TTypeMetadata;
  Handler: IPropertyHandler;
begin
  SBSet := TStringBuilder.Create;
  SBWhere := TStringBuilder.Create;
  ASetProps := TCollections.CreateList<TPair<TRttiProperty, string>>;
  AWhereProps := TCollections.CreateList<TPair<TRttiProperty, string>>;
  
  try
    FirstSet := True;
    FirstWhere := True;
    
    Meta := TReflection.GetMetadata(TypeInfo(T));
    for Handler in Meta.GetPropertyHandlers() do
    begin
      IsMapped := True;
      IsPK := Handler.GetIsPK();
      ColName := Handler.GetColumnName();
      
      PropMap := nil;
      if FMap <> nil then
        FMap.Properties.TryGetValue(Handler.GetName(), PropMap);
        
      if PropMap <> nil then
      begin
        if PropMap.IsIgnored then IsMapped := False;
        if PropMap.IsNavigation and not PropMap.IsJsonColumn then IsMapped := False;
        if PropMap.IsPK then IsPK := True;
        if PropMap.ColumnName <> '' then ColName := PropMap.ColumnName;
      end;

      if IsMapped and (PropMap = nil) and (Handler.GetMember() is TRttiProperty) and 
         (TRttiProperty(Handler.GetMember()).PropertyType.TypeKind in [tkClass, tkInterface]) then
        IsMapped := False;

      if IsMapped and Handler.GetMember().HasAttribute(NotMappedAttribute) then IsMapped := False;

      if IsMapped and ((Handler.GetMember().HasAttribute(HasManyAttribute)) or (Handler.GetMember().HasAttribute(BelongsToAttribute)) or 
         (Handler.GetMember().HasAttribute(HasOneAttribute)) or (Handler.GetMember().HasAttribute(ManyToManyAttribute))) then
        IsMapped := False;

      if Handler.GetMember().HasAttribute(JsonColumnAttribute) then IsMapped := True;
      
      if (ColName = Handler.GetName()) and (FNamingStrategy <> nil) and (Handler.GetMember() is TRttiProperty) then
         ColName := FNamingStrategy.GetColumnName(TRttiProperty(Handler.GetMember()));
      
      if not IsMapped then Continue;
      
      if IsPK then
      begin
        AWhereProps.Add(TPair<TRttiProperty, string>.Create(TRttiProperty(Handler.GetMember()), ColName));
        if not FirstWhere then SBWhere.Append(' AND ');
        FirstWhere := False;
        SBWhere.Append(FDialect.QuoteIdentifier(ColName)).Append(' = :').Append(ColName);
      end
      else
      begin
        ASetProps.Add(TPair<TRttiProperty, string>.Create(TRttiProperty(Handler.GetMember()), ColName));
        if not FirstSet then SBSet.Append(', ');
        FirstSet := False;
        SBSet.Append(FDialect.QuoteIdentifier(ColName)).Append(' = :').Append(ColName);
      end;
    end;
    
    if SBWhere.Length = 0 then
      raise Exception.Create('Cannot generate UPDATE template: No Primary Key defined.');

    AppendTenantWhereTemplate(SBWhere, FirstWhere, AWhereProps);
      
    Result := Format('UPDATE %s SET %s WHERE %s', 
      [GetTableName, SBSet.ToString, SBWhere.ToString]);
  finally
    SBSet.Free;
    SBWhere.Free;
  end;
end;

function TSQLGenerator<T>.GenerateDeleteTemplate(out AWhereProps: IList<TPair<TRttiProperty, string>>): string;
var
  ColName: string;
  SBWhere: TStringBuilder;
  IsPK, FirstWhere: Boolean;
  PropMap: TPropertyMap;
  Meta: TTypeMetadata;
  Handler: IPropertyHandler;
begin
  SBWhere := TStringBuilder.Create;
  AWhereProps := TCollections.CreateList<TPair<TRttiProperty, string>>;
  
  try
    FirstWhere := True;
    
    Meta := TReflection.GetMetadata(TypeInfo(T));
    for Handler in Meta.GetPropertyHandlers() do
    begin
      IsPK := Handler.GetIsPK();
      ColName := Handler.GetColumnName();
      
      PropMap := nil;
      if FMap <> nil then
        FMap.Properties.TryGetValue(Handler.GetName(), PropMap);
        
      if PropMap <> nil then
      begin
        if PropMap.IsPK then IsPK := True;
        if PropMap.ColumnName <> '' then ColName := PropMap.ColumnName;
      end;

      if (ColName = Handler.GetName()) and (FNamingStrategy <> nil) and (Handler.GetMember() is TRttiProperty) then
         ColName := FNamingStrategy.GetColumnName(TRttiProperty(Handler.GetMember()));
      
      if not IsPK then Continue;
      
      AWhereProps.Add(TPair<TRttiProperty, string>.Create(TRttiProperty(Handler.GetMember()), ColName));
      if not FirstWhere then SBWhere.Append(' AND ');
      FirstWhere := False;
      SBWhere.Append(FDialect.QuoteIdentifier(ColName)).Append(' = :').Append(ColName);
    end;
    
    if SBWhere.Length = 0 then
      raise Exception.Create('Cannot generate DELETE template: No Primary Key defined.');

    AppendTenantWhereTemplate(SBWhere, FirstWhere, AWhereProps);
      
    Result := Format('DELETE FROM %s WHERE %s', 
      [GetTableName, SBWhere.ToString]);
  finally
    SBWhere.Free;
  end;
end;

function TSQLGenerator<T>.GenerateUpdate(const AEntity: T): string;
var
  ColName, ParamName, ParamNameNew: string;
  SBSet, SBWhere: TStringBuilder;
  IsPK, IsMapped, IsVersion: Boolean;
  Val: TValue;
  NewVersionVal: Integer;
  FirstSet, FirstWhere: Boolean;
  PropMap: TPropertyMap;
  SQLCastStr: string;
  Converter: ITypeConverter;
  NullableHelper: TNullableHelper;
  Meta: TTypeMetadata;
  Handler: IPropertyHandler;
  Shadow: TEntityShadowState;
  HasModifiedFilter: Boolean;
begin
  FParams.Clear;
  FParamTypes.Clear;
  FParamCount := 0;
  
  SBSet := TStringBuilder.Create;
  SBWhere := TStringBuilder.Create;
  try
    FirstSet := True;
    FirstWhere := True;
    
    Shadow := nil;
    HasModifiedFilter := False;
    if (FContext <> nil) and (FContext.ChangeTracker <> nil) then
    begin
      if TObject(FContext.ChangeTracker) is TChangeTracker then
      begin
        Shadow := TChangeTracker(FContext.ChangeTracker)
          .GetShadowState(Pointer(AEntity));
        if (Shadow <> nil) and
           (Shadow.ModifiedProperties.Count > 0) then
          HasModifiedFilter := True;
      end;
    end;
    
    Meta := TReflection.GetMetadata(TypeInfo(T));
    for Handler in Meta.GetPropertyHandlers() do
    begin
      IsMapped := True;
      IsPK := Handler.GetIsPK();
      IsVersion := Handler.GetMember().HasAttribute(VersionAttribute);
      ColName := Handler.GetColumnName();
      
      PropMap := nil;
      if FMap <> nil then
        FMap.Properties.TryGetValue(Handler.GetName(), PropMap);
        
      if PropMap <> nil then
      begin
        if PropMap.IsIgnored then IsMapped := False;
        if PropMap.IsNavigation and not PropMap.IsJsonColumn then IsMapped := False;
        if PropMap.IsPK then IsPK := True;
        if PropMap.ColumnName <> '' then ColName := PropMap.ColumnName;
      end;

      if IsMapped and (PropMap = nil) and (Handler.GetMember() is TRttiProperty) and 
         (TRttiProperty(Handler.GetMember()).PropertyType.TypeKind in [tkClass, tkInterface]) then
        IsMapped := False;

      if IsMapped and Handler.GetMember().HasAttribute(NotMappedAttribute) then IsMapped := False;

      if IsMapped and ((Handler.GetMember().HasAttribute(HasManyAttribute)) or (Handler.GetMember().HasAttribute(BelongsToAttribute)) or 
         (Handler.GetMember().HasAttribute(HasOneAttribute)) or (Handler.GetMember().HasAttribute(ManyToManyAttribute))) then
        IsMapped := False;

      if Handler.GetMember().HasAttribute(JsonColumnAttribute) then IsMapped := True;
      
      if (ColName = Handler.GetName()) and (FNamingStrategy <> nil) and (Handler.GetMember() is TRttiProperty) then
         ColName := FNamingStrategy.GetColumnName(TRttiProperty(Handler.GetMember()));
      
      if not IsMapped then Continue;

      if HasModifiedFilter and not IsPK and not IsVersion then
      begin
        if not Shadow.ModifiedProperties.ContainsKey(Handler.GetName()) then
          Continue;
      end;
      
      Val := Handler.GetValue(Pointer(AEntity));
      
      if IsVersion then
      begin
        // Optimistic Concurrency Logic
        if IsNullable(Val.TypeInfo) then
        begin
          NullableHelper := TNullableHelper.Create(Val.TypeInfo);
          if NullableHelper.HasValue(Val.GetReferenceToRawData) then
            Val := NullableHelper.GetValue(Val.GetReferenceToRawData);
        end;
        TryUnwrapSmartValue(Val);

        // 1. Add to WHERE clause: Version = :OldVersion
        ParamName := GetNextParamName;
        FParams.Add(ParamName, Val);
        
        if not FirstWhere then SBWhere.Append(' AND ');
        FirstWhere := False;
        SBWhere.Append(FDialect.QuoteIdentifier(ColName)).Append(' = :').Append(ParamName);
        
        // 2. Add to SET clause: Version = :NewVersion (OldVersion + 1)
        ParamNameNew := GetNextParamName;
        if Val.IsEmpty then NewVersionVal := 1 else NewVersionVal := Val.AsInteger + 1;
        FParams.Add(ParamNameNew, NewVersionVal);
        
        if not FirstSet then SBSet.Append(', ');
        FirstSet := False;
        
        if (GetDialectEnum <> ddSQLite) and (Converter <> nil) then
           SQLCastStr := Converter.GetSQLCast(':' + ParamNameNew, GetDialectEnum)
        else
           SQLCastStr := ':' + ParamNameNew;

        SBSet.Append(FDialect.QuoteIdentifier(ColName)).Append(' = ').Append(SQLCastStr);
      end
      else if IsPK then
      begin
        // Primary Key -> WHERE clause (unwrap Nullable<T> and Prop<T> before binding)
        if IsNullable(Val.TypeInfo) then
        begin
          NullableHelper := TNullableHelper.Create(Val.TypeInfo);
          if NullableHelper.HasValue(Val.GetReferenceToRawData) then
            Val := NullableHelper.GetValue(Val.GetReferenceToRawData);
        end;
        TryUnwrapSmartValue(Val);

        ParamName := GetNextParamName;
        FParams.Add(ParamName, Val);
        
        if not FirstWhere then SBWhere.Append(' AND ');
        FirstWhere := False;
        
        // Apply ::uuid cast for PostgreSQL if value is GUID/UUID or GUID-like string
        SQLCastStr := ':' + ParamName;
        if (GetDialectEnum = ddPostgreSQL) and
           ((Val.TypeInfo = TypeInfo(TGUID)) or 
            (Val.TypeInfo = TypeInfo(TUUID)) or
            ((Val.Kind in [tkString, tkUString, tkWString]) and
             ((Length(Val.AsString) = 36) or (Length(Val.AsString) = 38)) and
             (Val.AsString.IndexOf('-') > 0))) then
          SQLCastStr := ':' + ParamName + '::uuid';
        
        SBWhere.Append(FDialect.QuoteIdentifier(ColName)).Append(' = ').Append(SQLCastStr);
        
        if (PropMap <> nil) and (PropMap.DataType <> ftUnknown) then
          FParamTypes.Add(ParamName, PropMap.DataType);
      end
      else
      begin
        // Standard Column -> SET clause
        
        // Check for Nullable<T>
        if IsNullable(Val.TypeInfo) then
        begin
          NullableHelper := TNullableHelper.Create(Val.TypeInfo);
          if not NullableHelper.HasValue(Val.GetReferenceToRawData) then
          begin
            if not FirstSet then SBSet.Append(', ');
            FirstSet := False;
            SBSet.Append(FDialect.QuoteIdentifier(ColName)).Append(' = NULL');
            Continue;
          end
          else
            Val := NullableHelper.GetValue(Val.GetReferenceToRawData);
        end;

        TryUnwrapSmartValue(Val);
        // DateTime Range Guard: out-of-range (< 1900-01-01) -> NULL
        if (Val.Kind = tkFloat) and (Val.AsExtended < 2.0) and
           (((PropMap <> nil) and
             (PropMap.DataType in [ftDateTime, ftDate, ftTime])) or
            (Val.TypeInfo = TypeInfo(TDateTime)) or
            (Val.TypeInfo = TypeInfo(TDate)) or
            (Val.TypeInfo = TypeInfo(TTime))) then
        begin
          if not FirstSet then SBSet.Append(', ');
          FirstSet := False;
          SBSet.Append(FDialect.QuoteIdentifier(ColName)).Append(' = NULL');
          Continue;
        end;

        ParamName := GetNextParamName;
        
        // Look up converter: PropMap -> Registry -> [JsonColumn] auto-detect
        Converter := nil;
        if PropMap <> nil then
          Converter := PropMap.Converter;
          
        if Converter = nil then
          Converter := TTypeConverterRegistry.Instance.GetConverter(Val.TypeInfo);

        if (Converter = nil) and (PropMap <> nil) and PropMap.IsJsonColumn then
          Converter := TJsonConverter.Create(PropMap.UseJsonB);

        if (GetDialectEnum <> ddSQLite) and (Converter <> nil) then
           SQLCastStr := Converter.GetSQLCast(':' + ParamName, GetDialectEnum)
        else
           SQLCastStr := ':' + ParamName;

        if Converter <> nil then
          Val := Converter.ToDatabase(Val, GetDialectEnum);

        FParams.Add(ParamName, Val);
        
        // Store explicit type if defined via [DbType] attribute
        if (PropMap <> nil) and (PropMap.DataType <> ftUnknown) then
          FParamTypes.Add(ParamName, PropMap.DataType);
        
        if not FirstSet then SBSet.Append(', ');
        FirstSet := False;

        SBSet.Append(FDialect.QuoteIdentifier(ColName)).Append(' = ').Append(SQLCastStr);
      end;
    end; // End of property loop
    
    if SBWhere.Length = 0 then
      raise Exception.Create('Cannot generate UPDATE: No Primary Key defined.');
      
    // ADD SHADOW PROPERTIES TO UPDATE
    if (FMap <> nil) and (FContext <> nil) then
    begin
      for PropMap in FMap.Properties.Values do
      begin
        if PropMap.IsShadow and not PropMap.IsIgnored and not PropMap.IsPK then
        begin
          if HasModifiedFilter and
             not Shadow.ModifiedProperties.ContainsKey(
               PropMap.PropertyName) then
            Continue;

          ColName := PropMap.ColumnName;
          if ColName = '' then ColName := PropMap.PropertyName;
          
          if SBSet.Length > 0 then SBSet.Append(', ');
          
          Val := FContext.Entry(AEntity).Member(PropMap.PropertyName).CurrentValue;
          TryUnwrapSmartValue(Val);

          // DateTime Range Guard: out-of-range (< 1900-01-01) -> NULL
          if (Val.Kind = tkFloat) and (Val.AsExtended < 2.0) and
             (((PropMap <> nil) and
               (PropMap.DataType in [ftDateTime, ftDate, ftTime])) or
              (Val.TypeInfo = TypeInfo(TDateTime)) or
              (Val.TypeInfo = TypeInfo(TDate)) or
              (Val.TypeInfo = TypeInfo(TTime))) then
          begin
             SBSet.Append(Format('%s = NULL', [FDialect.QuoteIdentifier(ColName)]));
             Continue;
          end;
          
          if Val.IsEmpty then
          begin
             SBSet.Append(Format('%s = NULL', [FDialect.QuoteIdentifier(ColName)]));
             Continue;
          end;
          
          ParamNameNew := GetNextParamName;
          
          Converter := PropMap.Converter;
          if (Converter = nil) and PropMap.IsJsonColumn then
            Converter := TJsonConverter.Create(PropMap.UseJsonB);
            
          if Converter = nil then
            Converter := TTypeConverterRegistry.Instance.GetConverter(Val.TypeInfo);

          if (GetDialectEnum <> ddSQLite) and (Converter <> nil) then
            SBSet.Append(FDialect.QuoteIdentifier(ColName)).Append(' = ').Append(Converter.GetSQLCast(':' + ParamNameNew, GetDialectEnum))
          else
            SBSet.Append(FDialect.QuoteIdentifier(ColName)).Append(' = :').Append(ParamNameNew);
            
          if Converter <> nil then
            Val := Converter.ToDatabase(Val, GetDialectEnum);
            
          FParams.Add(ParamNameNew, Val);
          if PropMap.DataType <> ftUnknown then
            FParamTypes.Add(ParamNameNew, PropMap.DataType);
        end;
      end;
    end;

    AppendTenantWhereParams(SBWhere, FirstWhere);

    Result := Format('UPDATE %s SET %s WHERE %s', 
      [GetTableName, SBSet.ToString, SBWhere.ToString]);
      
  finally
    SBSet.Free;
    SBWhere.Free;
  end;
end;

function TSQLGenerator<T>.GenerateDelete(const AEntity: T): string;
var
  Typ: TRttiType;
  Prop: TRttiProperty;
  Attr: TCustomAttribute;
  ColName, ParamName: string;
  SBWhere: TStringBuilder;
  IsPK, FirstWhere: Boolean;
  Val: TValue;
  PropMap: TPropertyMap;
  NullableHlp: TNullableHelper;
  SQLCastStr: string;
begin
  FParams.Clear;
  FParamCount := 0;

  Typ := TReflection.Context.GetType(T);
  
  SBWhere := TStringBuilder.Create;
  try
    FirstWhere := True;
    
    for Prop in Typ.GetProperties do
    begin
      IsPK := False;
      ColName := Prop.Name;
      
      PropMap := nil;
      if FMap <> nil then
        FMap.Properties.TryGetValue(Prop.Name, PropMap);
        
      if PropMap <> nil then
      begin
        if PropMap.IsPK then IsPK := True;
        if PropMap.ColumnName <> '' then ColName := PropMap.ColumnName;
      end;

      for Attr in Prop.GetAttributes do
      begin
        if (PropMap = nil) or not PropMap.IsPK then
          if Attr is PrimaryKeyAttribute then IsPK := True;
          
        if (PropMap = nil) or (PropMap.ColumnName = '') then
          if Attr is ColumnAttribute then ColName := ColumnAttribute(Attr).Name;
      end;
      
      if (ColName = Prop.Name) and (FNamingStrategy <> nil) then
         ColName := FNamingStrategy.GetColumnName(Prop);
      
      if not IsPK then Continue;
      
      Val := Prop.GetValue(Pointer(AEntity));

      // Check for Nullable<PK>? (Unlikely but for consistency)
      if IsNullable(Val.TypeInfo) then
      begin
         NullableHlp := TNullableHelper.Create(Val.TypeInfo);
         if NullableHlp.HasValue(Val.GetReferenceToRawData) then
           Val := NullableHlp.GetValue(Val.GetReferenceToRawData);
      end;
      
      // Check for Smart Type
      TryUnwrapSmartValue(Val);

      ParamName := GetNextParamName;
      FParams.Add(ParamName, Val);
      
      if not FirstWhere then SBWhere.Append(' AND ');
      FirstWhere := False;
      
      // Apply ::uuid cast for PostgreSQL if value is GUID/UUID or GUID-like string
      SQLCastStr := ':' + ParamName;
      if (GetDialectEnum = ddPostgreSQL) and
         ((Val.TypeInfo = TypeInfo(TGUID)) or 
          (Val.TypeInfo = TypeInfo(TUUID)) or
          ((Val.Kind in [tkString, tkUString, tkWString]) and
           ((Length(Val.AsString) = 36) or (Length(Val.AsString) = 38)) and
           (Val.AsString.IndexOf('-') > 0))) then
        SQLCastStr := ':' + ParamName + '::uuid';
      
      SBWhere.Append(FDialect.QuoteIdentifier(ColName)).Append(' = ').Append(SQLCastStr);
    end;
    
    if SBWhere.Length = 0 then
      raise Exception.Create('Cannot generate DELETE: No Primary Key defined.');

    AppendTenantWhereParams(SBWhere, FirstWhere);
      
    Result := Format('DELETE FROM %s WHERE %s', 
      [GetTableName, SBWhere.ToString]);
      
  finally
    SBWhere.Free;
  end;
end;

function TSQLGenerator<T>.GenerateSelect(const ASpec: ISpecification<T>): string;
var
  WhereGen: TSQLWhereGenerator;
  WhereSQL: string;
  SB: TStringBuilder;
  Prop: TRttiProperty;
  ColName: string;
  Attr: TCustomAttribute;
  Typ: TRttiType;
  First: Boolean;
  SelectedCols: TArray<string>;
  OrderBy: TArray<IOrderBy>;
  Skip, Take, i: Integer;
  Pair: TPair<string, TValue>;
  IsMapped: Boolean;
  PropMap: TPropertyMap;
  SoftDeleteFilter, DiscriminatorFilter: string;
  SortCol: string;
  P: TRttiProperty;
  Sig: string;
  CachedSQL: string;
  Collector: TSQLParamCollector;
  TenantId: string;
  LKind: TTypeKind;
  HasJoins: Boolean;
  BaseTableName: string;
begin
  FParams.Clear;
  FParamCount := 0;
  HasJoins := Length(ASpec.GetJoins) > 0;
  BaseTableName := GetTableName;
  
  // 1. Check Cache
  if TSQLCache.Instance.Enabled then
  begin
    TenantId := '';
    if Assigned(FTenantProvider) and Assigned(FTenantProvider.Tenant) then
      TenantId := FTenantProvider.Tenant.Id;

    Sig := Format('%s:%s:%s:Ign:%d:Del:%d:Ten:%s', 
      [(FDialect as TObject).ClassName, GetTableName, ASpec.GetSignature, 
       Ord(FIgnoreQueryFilters), Ord(FOnlyDeleted), TenantId]);
    // Types of one hierarchy share the table: the SQL differs by type
    if FMap <> nil then
      Sig := Sig + ':Type:' + string(FMap.EntityType.Name) + ':Disc:' +
        VarToStr(FMap.DiscriminatorValue);
    if TSQLCache.Instance.TryGetSQL(Sig, CachedSQL) then
    begin
      // Re-hydrate parameters using Collector (fast traversal)
      Collector := TSQLParamCollector.Create(FParams, TSQLGeneratorHelper.ResolveDialect(FDialect));
      try
        Collector.Collect(ASpec.GetExpression);
      finally
        Collector.Free;
      end;
      Result := CachedSQL;
      Exit;
  end;
  end;
  
  WhereGen := TSQLWhereGenerator.Create(
    FDialect,
    TSQLColumnMapper<T>.Create(FNamingStrategy),
    HasJoins,
    BaseTableName
  );
  try
    WhereSQL := WhereGen.Generate(ASpec.GetExpression);
    FParamCount := WhereGen.ParamCount;
    
    // Copy params
    for Pair in WhereGen.Params do
    begin
      FParams.AddOrSetValue(Pair.Key, Pair.Value);
    end;
  finally
    WhereGen.Free;
  end;
  
  SB := TStringBuilder.Create;
  try
    SB.Append('SELECT ');
    
    SelectedCols := ASpec.GetSelectedColumns;
    if Length(SelectedCols) > 0 then
    begin
      // Custom projection - translate property names to column names
      Typ := TReflection.Context.GetType(T);
      
      for i := 0 to High(SelectedCols) do
      begin
        if i > 0 then SB.Append(', ');
        
        ColName := SelectedCols[i]; // Default to property name
        
        // Try to find the property and get its mapped column name
        Prop := Typ.GetProperty(SelectedCols[i]);
        if Prop <> nil then
        begin
          // Check Fluent mapping first
          PropMap := nil;
          if FMap <> nil then
            FMap.Properties.TryGetValue(Prop.Name, PropMap);
            
          if (PropMap <> nil) and (PropMap.ColumnName <> '') then
            ColName := PropMap.ColumnName
          else
          begin
            // Check attributes
            for Attr in Prop.GetAttributes do
            begin
              if Attr is ColumnAttribute then
              begin
                ColName := ColumnAttribute(Attr).Name;
                Break;
              end;
            end;
          end;
        end;
        
        if (Prop <> nil) and (ColName = Prop.Name) and (FNamingStrategy <> nil) then
           ColName := FNamingStrategy.GetColumnName(Prop);
        
        SB.Append(QualifyBaseColumn(ColName, BaseTableName, HasJoins));
      end;
    end
    else
    begin
      // Select all mapped columns
      Typ := TReflection.Context.GetType(T);
      First := True;
      
      for Prop in Typ.GetProperties do
      begin
        ColName := Prop.Name;
        IsMapped := True;
        
        PropMap := nil;
        if FMap <> nil then
          FMap.Properties.TryGetValue(Prop.Name, PropMap);
          
        if PropMap <> nil then
        begin
          if PropMap.IsIgnored then IsMapped := False;
          if PropMap.ColumnName <> '' then ColName := PropMap.ColumnName;
        end;

        for Attr in Prop.GetAttributes do
        begin
          if Attr is NotMappedAttribute then IsMapped := False;
          
          if (PropMap = nil) or (PropMap.ColumnName = '') then
          begin
            if Attr is ColumnAttribute then ColName := ColumnAttribute(Attr).Name;
            if Attr is ForeignKeyAttribute then ColName := ForeignKeyAttribute(Attr).ColumnName;
          end;
        end;
        
        if (ColName = Prop.Name) and (FNamingStrategy <> nil) then
           ColName := FNamingStrategy.GetColumnName(Prop);
        
        if not IsMapped then Continue;
        
        // Skip navigation properties and lazy properties from default SELECT
        if (PropMap <> nil) and (PropMap.IsLazy or PropMap.IsNavigation) then Continue;

        // TypeKind safety net for navigation properties not explicitly marked
        LKind := Prop.PropertyType.TypeKind;
        
        if (LKind in [tkClass, tkInterface]) then
        begin
           // Allow class/interface ONLY if marked as JsonColumn
           if (PropMap = nil) or (not PropMap.IsJsonColumn) then
             Continue;
        end;

        if (LKind = tkRecord) and Prop.PropertyType.Name.StartsWith('Lazy<') then Continue;
        
        if not First then SB.Append(', ');
        First := False;
        
        SB.Append(QualifyBaseColumn(ColName, BaseTableName, HasJoins));
      end;

      // TPH root: the discriminator and the columns of the subclasses
      for ColName in GetHierarchyColumns do
      begin
        if not First then SB.Append(', ');
        First := False;
        SB.Append(QualifyBaseColumn(ColName, BaseTableName, HasJoins));
      end;
    end;

    SB.Append(' FROM ').Append(GetTableName);
    
    // Apply SQL Server Locking Hints if needed
    if (GetDialectEnum = ddSQLServer) and (ASpec <> nil) and (ASpec.GetLockMode <> lmNone) then
    begin
      SB.Append(' ').Append(FDialect.GetLockingSQL(ASpec.GetLockMode));
    end;
    
    // Add soft delete filter
    SoftDeleteFilter := GetSoftDeleteFilter;
    DiscriminatorFilter := GetDiscriminatorFilter;
    
    // Append Joins
    SB.Append(GenerateJoins(ASpec.GetJoins));
    
    // Combine filters
    if DiscriminatorFilter <> '' then
    begin
       if SoftDeleteFilter <> '' then
         SoftDeleteFilter := SoftDeleteFilter + ' AND ' + DiscriminatorFilter
       else
         SoftDeleteFilter := DiscriminatorFilter;
    end;
    
    if WhereSQL <> '' then
    begin
      SB.Append(' WHERE ').Append(WhereSQL);
      if SoftDeleteFilter <> '' then
        SB.Append(' AND ').Append(SoftDeleteFilter);
    end
    else if SoftDeleteFilter <> '' then
      SB.Append(' WHERE ').Append(SoftDeleteFilter);
      
    // Group By
    SB.Append(GenerateGroupBy(ASpec.GetGroupBy));

    // Order By
    OrderBy := ASpec.GetOrderBy;
    if Length(OrderBy) > 0 then
    begin
      SB.Append(' ORDER BY ');
      for i := 0 to High(OrderBy) do
      begin
        if i > 0 then SB.Append(', ');
        
        SortCol := OrderBy[i].GetPropertyName;
        // Lookup column name (simplified)
        Typ := TReflection.Context.GetType(T);
        P := Typ.GetProperty(SortCol);
        if P <> nil then
        begin
           for Attr in P.GetAttributes do
           begin
             if Attr is ColumnAttribute then SortCol := ColumnAttribute(Attr).Name;
             if Attr is ForeignKeyAttribute then SortCol := ForeignKeyAttribute(Attr).ColumnName;
           end;
        end;
        
        if SortCol.Contains('.') then
          SB.Append(QuoteColumnOrAlias(SortCol))
        else if HasJoins then
          SB.Append(BaseTableName).Append('.').Append(FDialect.QuoteIdentifier(SortCol))
        else
          SB.Append(FDialect.QuoteIdentifier(SortCol));
        
        if not OrderBy[i].GetAscending then
          SB.Append(' DESC');
      end;
    end;
    
    // Paging
    if ASpec.IsPagingEnabled then
    begin
      // SQL Server requires ORDER BY when using OFFSET/FETCH
      // If no ORDER BY was specified, add a default one ONLY if dialect requires it
      if (Length(OrderBy) = 0) and FDialect.RequiresOrderByForPaging then
      begin
        SB.Append(' ORDER BY ');
        // Use first column or (SELECT NULL) as fallback
        if Length(SelectedCols) > 0 then
          SB.Append(FDialect.QuoteIdentifier(SelectedCols[0]))
        else
          SB.Append('(SELECT NULL)');
      end
      else if (Length(OrderBy) > 0) and FDialect.RequiresOrderByForPaging then
      begin
         // OrderBy already appended? NO! It was appended before GroupBy in previous logic?
         // Let's check logic flow.
         // Order By was appended at line 1324.
         // Group By must come BEFORE Order By.
      end;
      
      Skip := ASpec.GetSkip;
      Take := ASpec.GetTake;
      
      // Paging syntax generation
      Result := FDialect.GeneratePaging(SB.ToString, Skip, Take);
    end
    else
    begin
      Result := SB.ToString;
    end;
    
    // Add to cache
    if (ASpec <> nil) and (Result <> '') then
    begin
      // Add Locking Clause for non-MSSQL at the very end
      if (GetDialectEnum <> ddSQLServer) and (ASpec.GetLockMode <> lmNone) then
      begin
        Result := Result + ' ' + FDialect.GetLockingSQL(ASpec.GetLockMode);
      end;
      
      TSQLCache.Instance.AddSQL(Sig, Result);
    end;
      
  finally
    SB.Free;
  end;
end;

function TSQLGenerator<T>.GenerateSelect: string;
var
  SB: TStringBuilder;
  Prop: TRttiProperty;
  ColName: string;
  Attr: TCustomAttribute;
  Typ: TRttiType;
  First, IsMapped: Boolean;
  PropMap: TPropertyMap;
  SoftDeleteFilter, DiscriminatorFilter, GlobalFilters, QFilters: string;
  LKind: TTypeKind;
begin
  FParams.Clear;
  FParamCount := 0;

  SB := TStringBuilder.Create;
  try
    SB.Append('SELECT ');

    // Select all mapped columns
    Typ := TReflection.Context.GetType(T);
    First := True;

    for Prop in Typ.GetProperties do
    begin
      ColName := Prop.Name;
      IsMapped := True;

      PropMap := nil;
      if FMap <> nil then
        FMap.Properties.TryGetValue(Prop.Name, PropMap);

      if PropMap <> nil then
      begin
        if PropMap.IsIgnored then IsMapped := False;
        if PropMap.ColumnName <> '' then ColName := PropMap.ColumnName;
      end;

      for Attr in Prop.GetAttributes do
      begin
        if Attr is NotMappedAttribute then IsMapped := False;

        if (PropMap = nil) or (PropMap.ColumnName = '') then
        begin
          if Attr is ColumnAttribute then ColName := ColumnAttribute(Attr).Name;
          if Attr is ForeignKeyAttribute then ColName := ForeignKeyAttribute(Attr).ColumnName;
        end;
      end;
      
      if (ColName = Prop.Name) and (FNamingStrategy <> nil) then
         ColName := FNamingStrategy.GetColumnName(Prop);

      if not IsMapped then Continue;

      // Skip navigation properties and lazy properties from default SELECT
      if (PropMap <> nil) and (PropMap.IsLazy or PropMap.IsNavigation) then Continue;

      // TypeKind safety net for navigation properties not explicitly marked
      LKind := Prop.PropertyType.TypeKind;

      if (LKind in [tkClass, tkInterface]) then
      begin
         // Allow class/interface ONLY if marked as JsonColumn
         if (PropMap = nil) or (not PropMap.IsJsonColumn) then
           Continue;
      end;

      if (LKind = tkRecord) and Prop.PropertyType.Name.StartsWith('Lazy<') then Continue;

      if not First then SB.Append(', ');
      First := False;

      SB.Append(FDialect.QuoteIdentifier(ColName));
    end;

    // TPH root: the discriminator and the columns of the subclasses
    for ColName in GetHierarchyColumns do
    begin
      if not First then SB.Append(', ');
      First := False;
      SB.Append(FDialect.QuoteIdentifier(ColName));
    end;

    SB.Append(' FROM ').Append(GetTableName);

    // Add global filters
    SoftDeleteFilter := GetSoftDeleteFilter;
    DiscriminatorFilter := GetDiscriminatorFilter;
    GlobalFilters := SoftDeleteFilter;
    
    if DiscriminatorFilter <> '' then
    begin
      if GlobalFilters <> '' then GlobalFilters := GlobalFilters + ' AND ';
      GlobalFilters := GlobalFilters + DiscriminatorFilter;
    end;
    
    QFilters := GetQueryFiltersSQL;
    if QFilters <> '' then
    begin
      if GlobalFilters <> '' then GlobalFilters := GlobalFilters + ' AND ';
      GlobalFilters := GlobalFilters + QFilters;
    end;
    
    if GlobalFilters <> '' then
      SB.Append(' WHERE ').Append(GlobalFilters);

    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

function TSQLGenerator<T>.GenerateCount(const ASpec: ISpecification<T>): string;
var
  WhereGen: TSQLWhereGenerator;
  WhereSQL: string;
  SB: TStringBuilder;
  SoftDeleteFilter, DiscriminatorFilter, GlobalFilters, QFilters: string;
  Pair: TPair<string, TValue>;
  HasJoins: Boolean;
  BaseTableName: string;
begin
  FParams.Clear;
  FParamCount := 0;
  HasJoins := Length(ASpec.GetJoins) > 0;
  BaseTableName := GetTableName;
  
  WhereGen := TSQLWhereGenerator.Create(
    FDialect,
    TSQLColumnMapper<T>.Create(FNamingStrategy),
    HasJoins,
    BaseTableName
  );
  try
    WhereSQL := WhereGen.Generate(ASpec.GetExpression);
    FParamCount := WhereGen.ParamCount;
    
    // Copy params
    for Pair in WhereGen.Params do
      FParams.AddOrSetValue(Pair.Key, Pair.Value);
  finally
    WhereGen.Free;
  end;
  
  SB := TStringBuilder.Create;
  try
    SB.Append('SELECT COUNT(*) FROM ').Append(GetTableName);
    
    // Global filters
    SoftDeleteFilter := GetSoftDeleteFilter;
    DiscriminatorFilter := GetDiscriminatorFilter;
    GlobalFilters := SoftDeleteFilter;
    
    if DiscriminatorFilter <> '' then
    begin
      if GlobalFilters <> '' then GlobalFilters := GlobalFilters + ' AND ';
      GlobalFilters := GlobalFilters + DiscriminatorFilter;
    end;
    
    QFilters := GetQueryFiltersSQL;
    if QFilters <> '' then
    begin
      if GlobalFilters <> '' then GlobalFilters := GlobalFilters + ' AND ';
      GlobalFilters := GlobalFilters + QFilters;
    end;

    // Append Joins
    SB.Append(GenerateJoins(ASpec.GetJoins));

    if WhereSQL <> '' then
    begin
      SB.Append(' WHERE ').Append(WhereSQL);
      if GlobalFilters <> '' then
        SB.Append(' AND ').Append(GlobalFilters);
    end
    else if GlobalFilters <> '' then
      SB.Append(' WHERE ').Append(GlobalFilters);
      
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

function TSQLGenerator<T>.GenerateCount: string;
var
  SoftDeleteFilter, DiscriminatorFilter: string;
begin
  FParams.Clear;
  FParamCount := 0;
  
  Result := 'SELECT COUNT(*) FROM ' + GetTableName;
  
  // Add soft delete filter
  SoftDeleteFilter := GetSoftDeleteFilter;
  DiscriminatorFilter := GetDiscriminatorFilter;
  
  if DiscriminatorFilter <> '' then
  begin
     if SoftDeleteFilter <> '' then
       Result := Result + ' WHERE ' + SoftDeleteFilter + ' AND ' + DiscriminatorFilter
     else
       Result := Result + ' WHERE ' + DiscriminatorFilter;
  end
  else if SoftDeleteFilter <> '' then
    Result := Result + ' WHERE ' + SoftDeleteFilter;
end;

function TSQLGenerator<T>.GenerateCreateTable(const ATableName: string): string;
var
  Typ: TRttiType;
  Prop: TRttiProperty;
  Attr: TCustomAttribute;
  ColName, ColType, Body: string;
  SB: TStringBuilder;
  First, IsPK, IsAutoInc, IsMapped, HasAutoInc: Boolean;
  PKCols: IList<string>;
  FKConstraints: IList<string>;
  Constraint: string;
  TypeAttr: TCustomAttribute;
  PropMap: TPropertyMap;
  i: Integer;
  FK: ForeignKeyAttribute;
  RelatedTable, RelatedPK: string;
  LConstraint: string;
  PropTypeHandle: PTypeInfo;
  LenTypeHandle: PTypeInfo;
  Underlying: PTypeInfo;
  IsSoftDeleteColumn: Boolean;
  IsRequired : Boolean;
  SoftDeleteDefaultValue: Variant;
  SoftDelAttr: SoftDeleteAttribute;
  LKind: TTypeKind;
  LTypeName, LLocalCol, LFKPropName: string;
  LRelatedTargetType: TRttiType;
  LIsNavProp: Boolean;
  LMeta: TTypeMetadata;
  NavProp: TRttiProperty;
  RelatedSchema, LFullRelatedTable: string;
  FieldFValue: TRttiField;
  MaxLen: Integer;
  PrecisionVal, ScaleVal: Integer;
  HierTypes: IList<TRttiType>;
  HierMaps: IList<TEntityMap>;
  Emitted: IList<string>;
  HIdx: Integer;
  CurMap, RootMap, SubMap: TEntityMap;
  DiscValue: Variant;
begin
  SB := TStringBuilder.Create;
  PKCols := TCollections.CreateList<string>;
  FKConstraints := TCollections.CreateList<string>;
  HierTypes := TCollections.CreateList<TRttiType>;
  HierMaps := TCollections.CreateList<TEntityMap>;
  Emitted := TCollections.CreateList<string>;
  try
    Typ := TReflection.Context.GetType(T);
    First := True;
    HasAutoInc := False;

    // Table per hierarchy: the one table has the columns of every class of it
    RootMap := GetHierarchyRoot;
    if RootMap <> nil then
    begin
      HierTypes.Add(TReflection.Context.GetType(RootMap.EntityType));
      HierMaps.Add(RootMap);
      for SubMap in GetSubtypeMaps(RootMap) do
      begin
        HierTypes.Add(TReflection.Context.GetType(SubMap.EntityType));
        HierMaps.Add(SubMap);
      end;
    end
    else
    begin
      HierTypes.Add(Typ);
      HierMaps.Add(FMap);
    end;

    for HIdx := 0 to HierTypes.Count - 1 do
    begin
    Typ := HierTypes[HIdx];
    CurMap := HierMaps[HIdx];

    for Prop in Typ.GetProperties do
    begin
      if (HIdx > 0) and (Prop.Parent.Handle <> Typ.Handle) then Continue;
      IsMapped := True;
      IsPK := False;
      IsAutoInc := False;
      IsRequired := False;
      ColName := Prop.Name;
      
      PropMap := nil;
      if CurMap <> nil then
        CurMap.Properties.TryGetValue(Prop.Name, PropMap);
        
      // Precedence: 
      // 1. Explicit Fluent Mapping (PropMap.ColumnName)
      // 2. Attributes ([Column], [ForeignKey])
      // 3. Naming Strategy
      
      if PropMap <> nil then
      begin
        if PropMap.IsIgnored then IsMapped := False;  
        if PropMap.IsNavigation then IsMapped := False; // Navigation properties are NOT columns
        if PropMap.IsPK then IsPK := True;
        if PropMap.IsAutoInc then IsAutoInc := True;
        if PropMap.ColumnName <> '' then ColName := PropMap.ColumnName;
        if PropMap.IsRequired then IsRequired := True;
      end;

      // Naming Strategy fallback (apply early so ForeignKey logic uses normalized names)
      if (ColName = Prop.Name) and (FNamingStrategy <> nil) then
         ColName := FNamingStrategy.GetColumnName(Prop);

      // Class/Interface detection as a safety net (unless explicitly mapped via attributes/mapping)
      if IsMapped then
      begin
        LKind := Prop.PropertyType.TypeKind;
        if LKind in [tkClass, tkInterface] then
        begin
          // Classes/Interfaces are only mapped if they have a converter (already handled in PropMap.IsNavigation)
          if (PropMap = nil) or PropMap.IsNavigation then
            IsMapped := False;
        end
        else if LKind = tkRecord then
        begin
          LTypeName := Prop.PropertyType.Name;
          if LTypeName.StartsWith('Lazy<') then
             IsMapped := False;
        end;
      end;

      for Attr in Prop.GetAttributes do
      begin
        if Attr is NotMappedAttribute then IsMapped := False;
        if Attr is PrimaryKeyAttribute then IsPK := True;
        if Attr is AutoIncAttribute then IsAutoInc := True;
        if Attr is RequiredAttribute then IsRequired := True;
        if Attr is JsonColumnAttribute then IsMapped := True; // Force mapping for JSON columns

        if Attr is ForeignKeyAttribute then
        begin
             FK := ForeignKeyAttribute(Attr);
          
             LLocalCol := ColName;
             LRelatedTargetType := nil;
             LFKPropName := FK.ColumnName;

             LIsNavProp := (Prop.PropertyType.TypeKind = tkClass);
             if (not LIsNavProp) and (Prop.PropertyType.TypeKind = tkRecord) and Prop.PropertyType.Name.StartsWith('Lazy<') then
               LIsNavProp := True;

             if LIsNavProp then
             begin
                // Pattern A: [ForeignKey('RequesterId')] property Requester: TUser (or Lazy<TUser>)
                LLocalCol := TSQLGeneratorHelper.GetColumnNameForProperty(Typ, LFKPropName, FNamingStrategy);
                if Prop.PropertyType.TypeKind = tkRecord then
                begin
                   LMeta := TReflection.GetMetadata(Prop.PropertyType.Handle);
                   if LMeta.InnerType <> nil then
                     LRelatedTargetType := TReflection.Context.GetType(LMeta.InnerType);
                end
                else
                  LRelatedTargetType := Prop.PropertyType;
             end
             else
             begin
                // Pattern B: [ForeignKey('Requester')] property RequesterId: Integer
                NavProp := Typ.GetProperty(LFKPropName);
                if NavProp <> nil then
                begin
                   if NavProp.PropertyType.TypeKind = tkClass then
                     LRelatedTargetType := NavProp.PropertyType
                   else if (NavProp.PropertyType.TypeKind = tkRecord) and NavProp.PropertyType.Name.StartsWith('Lazy<') then
                   begin
                     LMeta := TReflection.GetMetadata(NavProp.PropertyType.Handle);
                     if LMeta.InnerType <> nil then
                       LRelatedTargetType := TReflection.Context.GetType(LMeta.InnerType);
                   end;
                end;
             end;

             RelatedSchema := '';
             if (LRelatedTargetType <> nil) and 
                TSQLGeneratorHelper.GetRelatedTableAndPK(LRelatedTargetType.AsInstance.MetaclassType, RelatedTable, RelatedSchema, RelatedPK, FNamingStrategy) then
             begin
                 LFullRelatedTable := RelatedTable;
                 if RelatedSchema <> '' then
                   LFullRelatedTable := RelatedSchema + '.' + RelatedTable;

                 LConstraint := Format('FOREIGN KEY (%s) REFERENCES %s (%s)', 
                   [FDialect.QuoteIdentifier(LLocalCol), 
                    FDialect.QuoteIdentifier(LFullRelatedTable), 
                    FDialect.QuoteIdentifier(RelatedPK)]);
                    
                 if FK.OnDelete <> caNoAction then
                   LConstraint := LConstraint + ' ON DELETE ' + TSQLGeneratorHelper.GetCascadeSQL(FK.OnDelete);
                   
                 if FK.OnUpdate <> caNoAction then
                   LConstraint := LConstraint + ' ON UPDATE ' + TSQLGeneratorHelper.GetCascadeSQL(FK.OnUpdate);
                   
                 FKConstraints.Add(LConstraint);
             end;
        end;
        
        if Attr is ColumnAttribute then
        begin
          if (PropMap = nil) or (PropMap.ColumnName = '') then
            ColName := ColumnAttribute(Attr).Name;
        end;
      end;

      
      if not IsMapped then Continue;

      // A column already emitted by another class of the hierarchy
      if Emitted.Contains(LowerCase(ColName)) then Continue;
      Emitted.Add(LowerCase(ColName));
      // Columns of subclasses are nullable: other subclasses never fill them
      if HIdx > 0 then
      begin
        IsPK := False;
        IsAutoInc := False;
        IsRequired := False;
      end;

      if not First then SB.Append(', ');
      First := False;
      
      SB.Append(FDialect.QuoteIdentifier(ColName));
      SB.Append(' ');
      
      PropTypeHandle := Prop.PropertyType.Handle;
      
      // Extract Precision and Scale from PropMap or PrecisionAttribute
      PrecisionVal := 0;
      ScaleVal := 0;
      if PropMap <> nil then
      begin
        PrecisionVal := PropMap.Precision;
        ScaleVal := PropMap.Scale;
      end;
      if PrecisionVal = 0 then
      begin
        for Attr in Prop.GetAttributes do
        begin
          if Attr is PrecisionAttribute then
          begin
            PrecisionVal := PrecisionAttribute(Attr).Precision;
            ScaleVal := PrecisionAttribute(Attr).Scale;
            Break;
          end;
        end;
      end;

      // Handle Explicit DbType (Attributes or Fluent).
      // Skip GetColumnTypeForField when AutoInc is True: DiscoverAttributes always fills
      // PropMap.DataType from the property type (e.g. ftInteger), so we must NOT fall into
      // GetColumnTypeForField for AutoInc columns - TBaseDialect returns plain 'INTEGER'
      // from that path, losing the dialect-specific identity syntax (e.g. 'INTEGER GENERATED
      // BY DEFAULT AS IDENTITY' for Firebird, 'SERIAL' for PostgreSQL).
      if (PropMap <> nil) and (PropMap.DataType <> ftUnknown) and (not IsAutoInc) then
      begin
        ColType := FDialect.GetColumnTypeForField(PropMap.DataType, IsAutoInc, PrecisionVal, ScaleVal);
      end
      else
      begin
        // Handle Nullable<T>
        if IsNullable(Prop.PropertyType.Handle) then
        begin
          IsRequired := false;  // can't be nullable<T> and required
          Underlying := GetUnderlyingType(Prop.PropertyType.Handle);
          if Underlying <> nil then
            PropTypeHandle := Underlying;
        end
        // Handle Prop<T> (Smart Types)
        else if (Prop.PropertyType.TypeKind = tkRecord) then
        begin
           FieldFValue := Prop.PropertyType.GetField('FValue');
           if (FieldFValue <> nil) and 
              (Prop.PropertyType.Name.Contains('Prop<') or (Prop.PropertyType.GetProperty('Value') <> nil)) then
           begin
              PropTypeHandle := FieldFValue.FieldType.Handle;
           end;
        end;
        
        ColType := FDialect.GetColumnType(PropTypeHandle, IsAutoInc, PrecisionVal, ScaleVal);
      end;
      
      // Apply MaxLength for string columns - check from PropMap or Attribute
      MaxLen := 0;
      if (PropMap <> nil) and (PropMap.MaxLength > 0) then
        MaxLen := PropMap.MaxLength
      else
      begin
        // Check for MaxLengthAttribute
        for Attr in Prop.GetAttributes do
        begin
          if Attr is MaxLengthAttribute then
          begin
            MaxLen := MaxLengthAttribute(Attr).Length;
            Break;
          end;
        end;
      end;
      
      // For string types with MaxLength, replace generic types with sized VARCHAR.
      // A Smart Property (Prop<T>) is a record: the length rule uses the wrapped type.
      LenTypeHandle := PropTypeHandle;
      if (LenTypeHandle <> nil) and (LenTypeHandle.Kind = tkRecord) then
      begin
        FieldFValue := Prop.PropertyType.GetField('FValue');
        if FieldFValue <> nil then
          LenTypeHandle := FieldFValue.FieldType.Handle;
      end;

      if (MaxLen > 0) and (LenTypeHandle.Kind in [tkString, tkUString, tkWString, tkChar, tkWChar]) then
      begin
        if GetDialectEnum = ddSQLServer then
          ColType := Format('NVARCHAR(%d)', [MaxLen])
        else if GetDialectEnum = ddOracle then
          ColType := Format('VARCHAR2(%d)', [MaxLen])
        else
          ColType := Format('VARCHAR(%d)', [MaxLen]);
      end;

      SB.Append(ColType);
      
      // Check if this is a soft delete column and add DEFAULT
      IsSoftDeleteColumn := False;
      for TypeAttr in Typ.GetAttributes do
      begin
        if TypeAttr is SoftDeleteAttribute then
        begin
          SoftDelAttr := SoftDeleteAttribute(TypeAttr);
          if SameText(ColName, SoftDelAttr.ColumnName) then
          begin
            IsSoftDeleteColumn := True;
            SoftDeleteDefaultValue := SoftDelAttr.NotDeletedValue;
            Break;
          end;
        end;
      end;
      
      if IsPK then
      begin
        PKCols.Add(FDialect.QuoteIdentifier(ColName));
        if IsAutoInc then
        begin
            SB.Append(' PRIMARY KEY');
            HasAutoInc := True;
        end
        else
          IsRequired := true;
      end;

      if IsRequired then
        SB.Append(' NOT NULL');

      if (not IsPk) and IsSoftDeleteColumn then
      begin
        SB.Append(' DEFAULT ').Append(VarToStr(SoftDeleteDefaultValue));
      end;
    end; // End of Properties Loop
    end; // End of hierarchy loop

    // Discriminator column of the hierarchy
    if (RootMap <> nil) and (not Emitted.Contains(LowerCase(RootMap.DiscriminatorColumn))) then
    begin
      DiscValue := Null;
      for SubMap in GetSubtypeMaps(RootMap) do
        if not VarIsNull(SubMap.DiscriminatorValue) then
        begin
          DiscValue := SubMap.DiscriminatorValue;
          Break;
        end;
      if not First then SB.Append(', ');
      First := False;
      SB.Append(FDialect.QuoteIdentifier(RootMap.DiscriminatorColumn)).Append(' ');
      if VarIsNumeric(DiscValue) then
        SB.Append(FDialect.GetColumnType(TypeInfo(Integer), False, 0, 0))
      else
        SB.Append(FDialect.GetColumnType(TypeInfo(string), False, 0, 0));
    end;

    // Add Composite PK constraint or Single PK constraint (if not AutoInc)
    if (PKCols.Count > 0) and not HasAutoInc then
    begin
      SB.Append(', PRIMARY KEY (');
      for i := 0 to PKCols.Count - 1 do
      begin
        if i > 0 then SB.Append(', ');
        SB.Append(PKCols[i]);
      end;
      SB.Append(')');
    end;
    
    // Add FK Constraints
    for Constraint in FKConstraints do
    begin
      SB.Append(', ').Append(Constraint);
    end;
    
    Body := SB.ToString;
    Result := FDialect.GetCreateTableSQL(ATableName, Body);
  finally
    FKConstraints := nil;
    PKCols := nil;
    SB.Free;
  end;
end;




function TSQLGenerator<T>.GetJoinTypeSQL(AType: TJoinType): string;
begin
  case AType of
    jtInner: Result := 'INNER JOIN';
    jtLeft: Result := 'LEFT JOIN';
    jtRight: Result := 'RIGHT JOIN';
    jtFull: Result := 'FULL JOIN';
    jtCross: Result := 'CROSS JOIN';
  else
    Result := 'INNER JOIN';
  end;
end;

function TSQLGenerator<T>.GenerateJoins(const AJoins: TArray<IJoin>): string;
var
  SB: TStringBuilder;
  JoinObj: IJoin;
  WhereGen: TSQLWhereGenerator;
  Pair: TPair<string, TValue>;
begin
  if Length(AJoins) = 0 then Exit('');
  
  SB := TStringBuilder.Create;
  try
    for JoinObj in AJoins do
    begin
       SB.Append(' ')
         .Append(GetJoinTypeSQL(JoinObj.GetJoinType))
         .Append(' ')
         .Append(FDialect.QuoteIdentifier(JoinObj.GetTableName));
         
       if JoinObj.GetAlias <> '' then
         SB.Append(' ').Append(FDialect.QuoteIdentifier(JoinObj.GetAlias));
         
       if JoinObj.GetJoinType <> jtCross then
       begin
         WhereGen := TSQLWhereGenerator.Create(FDialect, nil);
         try
           SB.Append(' ON ')
             .Append(WhereGen.Generate(JoinObj.GetCondition));
             
           // Merge Params
           for Pair in WhereGen.Params do
             FParams.AddOrSetValue(Pair.Key, Pair.Value);
             
         finally
           WhereGen.Free;
         end;
       end;
    end;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

function TSQLGenerator<T>.GenerateGroupBy(const AGroupBy: TArray<string>): string;
var
  SB: TStringBuilder;
  i: Integer;
begin
  if Length(AGroupBy) = 0 then Exit('');
  
  SB := TStringBuilder.Create;
  try
    SB.Append(' GROUP BY ');
    for i := 0 to High(AGroupBy) do
    begin
      if i > 0 then SB.Append(', ');
      SB.Append(QuoteColumnOrAlias(AGroupBy[i]));
    end;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

function TSQLGenerator<T>.QuoteColumnOrAlias(const AName: string): string;
var
  Parts: TArray<string>;
  i: Integer;
begin
  if AName.Contains('.') then
  begin
    Parts := AName.Split(['.']);
    Result := '';
    for i := 0 to High(Parts) do
    begin
      if i > 0 then Result := Result + '.';
      Result := Result + FDialect.QuoteIdentifier(Parts[i]);
    end;
  end
  else
    Result := FDialect.QuoteIdentifier(AName);
end;

end.

