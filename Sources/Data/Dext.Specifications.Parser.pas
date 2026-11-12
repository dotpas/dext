unit Dext.Specifications.Parser;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Rtti,
  System.Variants,
  Dext.Specifications.Interfaces,
  Dext.Specifications.Types;

type
  TStringExpressionParser = class
  public
    class function Parse(const AFilter: string): IExpression;
  end;

  /// <summary>
  ///   Raised when a filter string is not valid. A filter the dataset cannot
  ///   read must not quietly show every row.
  /// </summary>
  EFilterSyntaxError = class(Exception);

  /// <summary>
  ///   The filter syntax of a TDataSet: comparisons (= &lt;&gt; != &lt; &lt;= &gt;
  ///   &gt;=), LIKE, IN, IS [NOT] NULL, combined with AND, OR, NOT and
  ///   parentheses. Strings are quoted with single quotes ('' for a quote).
  ///   An empty filter returns nil.
  /// </summary>
  TFilterParser = class
  public
    class function Parse(const AFilter: string): IExpression;
  end;

implementation

uses
  System.Character,
  System.StrUtils;

{ TStringExpressionParser }

class function TStringExpressionParser.Parse(const AFilter: string): IExpression;
var
  Parts: TArray<string>;
  FieldName, Op, ValStr: string;
  BinaryOp: TBinaryOperator;
  Value: TValue;
  Dbl: Double;
  Int: Integer;
begin
  Result := nil;
  if AFilter.Trim = '' then Exit;

  // Parser simplificado baseado em Split por Espaço
  // Sintaxe esperada: "Campo Operador Valor"
  Parts := AFilter.Trim.Split([' ']);
  
  if Length(Parts) < 3 then
    Exit; // Formato inválido para esse parser básico

  FieldName := Parts[0];
  Op := Parts[1].ToUpper;
  
  // Capturar o Valor (pode conter espaços se for string entre aspas)
  ValStr := string.Join(' ', Parts, 2, Length(Parts) - 2).Trim;
  if ValStr.StartsWith('''') and ValStr.EndsWith('''') then
    ValStr := ValStr.Substring(1, ValStr.Length - 2);

  // Identificar Operador
  if (Op = '=') or (Op = 'EQUAL') then BinaryOp := boEqual
  else if (Op = '<>') or (Op = 'NOTEQUAL') then BinaryOp := boNotEqual
  else if Op = '>' then BinaryOp := boGreaterThan
  else if Op = '>=' then BinaryOp := boGreaterThanOrEqual
  else if Op = '<' then BinaryOp := boLessThan
  else if Op = '<=' then BinaryOp := boLessThanOrEqual
  else if Op = 'LIKE' then BinaryOp := boLike
  else Exit;

  // Converter valor tipado
  if ValStr.ToLower = 'true' then Value := True
  else if ValStr.ToLower = 'false' then Value := False
  else if (ValStr.Contains('.')) and (TryStrToFloat(ValStr, Dbl, FormatSettings.Invariant)) then Value := Dbl
  else if TryStrToInt(ValStr, Int) then Value := Int
  else Value := ValStr;

  // Criar Expressão Binary
  Result := TBinaryExpression.Create(
    TPropertyExpression.Create(FieldName),
    TLiteralExpression.Create(Value),
    BinaryOp
  );
end;

{ TFilterParser }

type
  TFilterTokenKind = (fkEnd, fkIdent, fkString, fkNumber, fkOperator,
    fkOpen, fkClose, fkComma);

  TFilterReader = class
  private
    FText: string;
    FPos: Integer;
    FKind: TFilterTokenKind;
    FToken: string;
    procedure Fail(const AMessage: string);
    procedure Next;
    function IsWord(const AWord: string): Boolean;
    function ParseOr: IExpression;
    function ParseAnd: IExpression;
    function ParseNot: IExpression;
    function ParsePrimary: IExpression;
    function ParseComparison: IExpression;
    function ParseOperand: IExpression;
    function ParseList: IExpression;
  public
    constructor Create(const AText: string);
    function ParseAll: IExpression;
  end;

constructor TFilterReader.Create(const AText: string);
begin
  inherited Create;
  FText := AText;
  FPos := 1;
  Next;
end;

procedure TFilterReader.Fail(const AMessage: string);
begin
  raise EFilterSyntaxError.CreateFmt('Invalid filter "%s": %s (position %d)',
    [FText, AMessage, FPos]);
end;

procedure TFilterReader.Next;
var
  Start: Integer;
  Pair: string;
begin
  while (FPos <= Length(FText)) and (FText[FPos] <= ' ') do
    Inc(FPos);
  FToken := '';
  if FPos > Length(FText) then
  begin
    FKind := fkEnd;
    Exit;
  end;

  if FText[FPos] = '''' then
  begin
    Inc(FPos);
    while True do
    begin
      if FPos > Length(FText) then
        Fail('string without a closing quote');
      if FText[FPos] <> '''' then
      begin
        FToken := FToken + FText[FPos];
        Inc(FPos);
      end
      else if (FPos < Length(FText)) and (FText[FPos + 1] = '''') then
      begin
        FToken := FToken + '''';
        Inc(FPos, 2);
      end
      else
      begin
        Inc(FPos);
        Break;
      end;
    end;
    FKind := fkString;
  end
  else if FText[FPos].IsLetter or (FText[FPos] = '_') then
  begin
    Start := FPos;
    while (FPos <= Length(FText)) and (FText[FPos].IsLetterOrDigit or
      (FText[FPos] = '_') or (FText[FPos] = '.')) do
      Inc(FPos);
    FToken := Copy(FText, Start, FPos - Start);
    FKind := fkIdent;
  end
  else if FText[FPos].IsDigit or ((FText[FPos] = '-') and
    (FPos < Length(FText)) and FText[FPos + 1].IsDigit) then
  begin
    Start := FPos;
    Inc(FPos);
    while (FPos <= Length(FText)) and (FText[FPos].IsDigit or
      (FText[FPos] = '.')) do
      Inc(FPos);
    FToken := Copy(FText, Start, FPos - Start);
    FKind := fkNumber;
  end
  else if FText[FPos] = '(' then
  begin
    FKind := fkOpen;
    Inc(FPos);
  end
  else if FText[FPos] = ')' then
  begin
    FKind := fkClose;
    Inc(FPos);
  end
  else if FText[FPos] = ',' then
  begin
    FKind := fkComma;
    Inc(FPos);
  end
  else if CharInSet(FText[FPos], ['=', '<', '>', '!']) then
  begin
    FKind := fkOperator;
    Pair := Copy(FText, FPos, 2);
    if (Pair = '<>') or (Pair = '<=') or (Pair = '>=') or (Pair = '!=') then
    begin
      FToken := Pair;
      Inc(FPos, 2);
    end
    else if FText[FPos] = '!' then
      Fail('"!" must be followed by "="')
    else
    begin
      FToken := FText[FPos];
      Inc(FPos);
    end;
  end
  else
    Fail('unexpected character "' + FText[FPos] + '"');
end;

function TFilterReader.IsWord(const AWord: string): Boolean;
begin
  Result := (FKind = fkIdent) and SameText(FToken, AWord);
end;

function TFilterReader.ParseAll: IExpression;
begin
  Result := ParseOr;
  if FKind <> fkEnd then
    Fail('unexpected "' + FToken + '"');
end;

function TFilterReader.ParseOr: IExpression;
begin
  Result := ParseAnd;
  while IsWord('OR') do
  begin
    Next;
    Result := TLogicalExpression.Create(Result, ParseAnd, loOr);
  end;
end;

function TFilterReader.ParseAnd: IExpression;
begin
  Result := ParseNot;
  while IsWord('AND') do
  begin
    Next;
    Result := TLogicalExpression.Create(Result, ParseNot, loAnd);
  end;
end;

function TFilterReader.ParseNot: IExpression;
begin
  if IsWord('NOT') then
  begin
    Next;
    Result := TUnaryExpression.Create(ParseNot);
  end
  else
    Result := ParsePrimary;
end;

function TFilterReader.ParsePrimary: IExpression;
begin
  if FKind = fkOpen then
  begin
    Next;
    Result := ParseOr;
    if FKind <> fkClose then
      Fail('expected ")"');
    Next;
  end
  else
    Result := ParseComparison;
end;

function TFilterReader.ParseOperand: IExpression;
var
  I: Integer;
  F: Double;
begin
  case FKind of
    fkIdent:
      begin
        if SameText(FToken, 'TRUE') then
          Result := TLiteralExpression.Create(TValue.From<Boolean>(True))
        else if SameText(FToken, 'FALSE') then
          Result := TLiteralExpression.Create(TValue.From<Boolean>(False))
        else
          Result := TPropertyExpression.Create(FToken);
      end;
    fkString:
      Result := TLiteralExpression.Create(TValue.From<string>(FToken));
    fkNumber:
      begin
        if FToken.Contains('.') then
        begin
          if not TryStrToFloat(FToken, F, TFormatSettings.Invariant) then
            Fail('invalid number "' + FToken + '"');
          Result := TLiteralExpression.Create(TValue.From<Double>(F));
        end
        else if TryStrToInt(FToken, I) then
          Result := TLiteralExpression.Create(TValue.From<Integer>(I))
        else
          Result := TLiteralExpression.Create(
            TValue.From<Int64>(StrToInt64Def(FToken, 0)));
      end;
  else
    Fail('expected a field or a value');
  end;
  Next;
end;

function TFilterReader.ParseList: IExpression;
var
  Ints: TArray<Integer>;
  Texts: TArray<string>;
  AllInts: Boolean;
  I: Integer;
begin
  if FKind <> fkOpen then
    Fail('expected "(" after IN');
  Next;
  AllInts := True;
  repeat
    if (FKind = fkNumber) and not FToken.Contains('.') and
      TryStrToInt(FToken, I) then
      Ints := Ints + [I]
    else if (FKind = fkNumber) or (FKind = fkString) then
      AllInts := False
    else
      Fail('expected a value in the IN list');
    Texts := Texts + [FToken];
    Next;
    if FKind = fkComma then
      Next
    else
      Break;
  until False;
  if FKind <> fkClose then
    Fail('expected ")"');
  Next;
  if AllInts then
    Result := TLiteralExpression.Create(TValue.From<TArray<Integer>>(Ints))
  else
    Result := TLiteralExpression.Create(TValue.From<TArray<string>>(Texts));
end;

function TFilterReader.ParseComparison: IExpression;
var
  Left: IExpression;
  Op: TBinaryOperator;
  Name: string;
begin
  Name := FToken;
  Left := ParseOperand;

  if IsWord('IS') then
  begin
    if not (Left is TPropertyExpression) then
      Fail('IS NULL needs a field');
    Next;
    if IsWord('NOT') then
    begin
      Next;
      if not IsWord('NULL') then
        Fail('expected NULL');
      Next;
      Exit(TUnaryExpression.Create(Name, uoIsNotNull));
    end;
    if not IsWord('NULL') then
      Fail('expected NULL');
    Next;
    Exit(TUnaryExpression.Create(Name, uoIsNull));
  end;

  if IsWord('NOT') then
  begin
    Next;
    if IsWord('LIKE') then
      Op := boNotLike
    else if IsWord('IN') then
      Op := boNotIn
    else
    begin
      Fail('expected LIKE or IN after NOT');
      Exit(nil);
    end;
    Next;
  end
  else if IsWord('LIKE') then
  begin
    Op := boLike;
    Next;
  end
  else if IsWord('IN') then
  begin
    Op := boIn;
    Next;
  end
  else if FKind = fkOperator then
  begin
    if FToken = '=' then Op := boEqual
    else if (FToken = '<>') or (FToken = '!=') then Op := boNotEqual
    else if FToken = '>' then Op := boGreaterThan
    else if FToken = '>=' then Op := boGreaterThanOrEqual
    else if FToken = '<' then Op := boLessThan
    else Op := boLessThanOrEqual;
    Next;
  end
  else
  begin
    Fail('expected a comparison operator');
    Exit(nil);
  end;

  if (Op = boIn) or (Op = boNotIn) then
    Result := TBinaryExpression.Create(Left, ParseList, Op)
  else
    Result := TBinaryExpression.Create(Left, ParseOperand, Op);
end;

class function TFilterParser.Parse(const AFilter: string): IExpression;
var
  Reader: TFilterReader;
begin
  Result := nil;
  if AFilter.Trim = '' then Exit;
  Reader := TFilterReader.Create(AFilter);
  try
    Result := Reader.ParseAll;
  finally
    Reader.Free;
  end;
end;

end.
