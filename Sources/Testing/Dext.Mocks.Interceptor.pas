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

unit Dext.Mocks.Interceptor;

interface

uses
  System.Rtti,
  System.SysUtils,
  System.TypInfo,
  Dext.Interception,
  Dext.Interception.ClassProxy,
  Dext.Collections,
  Dext.Mocks;

type
  TMockState = (Acting, Arranging, Asserting);

  TMethodSetup = class
  private
    FName: string;
    FReturnValues: TArray<TValue>;
    FCurrentValueIndex: Integer;
    FExceptionClass: ExceptClass;
    FExceptionMessage: string;
    FAction: TProc<IInvocation>;
    FArgumentMatchers: TArray<TPredicate<TValue>>;
    FSetupArguments: TArray<TValue>;
    FDescription: string;
  public
    constructor Create(const AName: string);
    function MatchesArguments(const Args: TArray<TValue>): Boolean;
    function GetNextReturnValue: TValue;
    property Name: string read FName;
    property Description: string read FDescription;
    property ReturnValues: TArray<TValue> read FReturnValues write FReturnValues;
    property ExceptionClass: ExceptClass read FExceptionClass write FExceptionClass;
    property ExceptionMessage: string read FExceptionMessage write FExceptionMessage;
    property Action: TProc<IInvocation> read FAction write FAction;
    property ArgumentMatchers: TArray<TPredicate<TValue>> read FArgumentMatchers write FArgumentMatchers;
  end;

  TMethodCall = class
  private
    FName: string;
    FArguments: TArray<TValue>;
    FVerified: Boolean;
  public
    constructor Create(const AName: string; const AArguments: TArray<TValue>);
    property Name: string read FName;
    property Arguments: TArray<TValue> read FArguments;
    property Verified: Boolean read FVerified write FVerified;
  end;

  TMockInterceptor = class(TInterfacedObject, IInterceptor)
  private
    FBehavior: TMockBehavior;
    FState: TMockState;
    FSetups: IList<TMethodSetup>;
    FReceivedCalls: IList<TMethodCall>;
    FPendingSetup: TMethodSetup;
    FVerifyTimes: Times;
    FCallBase: Boolean;
    function DescribeReceivedCalls(const AMethodName: string): string;
  public
    constructor Create(ABehavior: TMockBehavior);
    destructor Destroy; override;
    procedure ClearInterceptors;
    procedure Intercept(const Invocation: IInvocation);
    procedure BeginSetup(ASetup: TMethodSetup);
    procedure BeginVerify(const ATimes: Times);
    procedure Verify;
    procedure VerifyNoOtherCalls;
    procedure Reset;
    property Behavior: TMockBehavior read FBehavior write FBehavior;
    property State: TMockState read FState;
    property Setups: IList<TMethodSetup> read FSetups;
    property ReceivedCalls: IList<TMethodCall> read FReceivedCalls;
    property CallBase: Boolean read FCallBase write FCallBase;
  end;

  TSetup<T> = class(TInterfacedObject, ISetup<T>)
  private
    FMock: IMock<T>;
    FInterceptor: TMockInterceptor;
    FProxy: T;
  public
    constructor Create(const AMock: IMock<T>; AInterceptor: TMockInterceptor; const AProxy: T);
    function Returns(const Value: TValue): IWhen<T>; overload;
    function Returns(const Values: TArray<TValue>): IWhen<T>; overload;
    function ReturnsInSequence(const Values: TArray<TValue>): IWhen<T>; overload;
    function ReturnsInSequence(const Values: TArray<Integer>): IWhen<T>; overload;
    function ReturnsInSequence(const Values: TArray<string>): IWhen<T>; overload;
    function ReturnsInSequence(const Values: TArray<Boolean>): IWhen<T>; overload;
    function Returns(Value: Integer): IWhen<T>; overload;
    function Returns(const Value: string): IWhen<T>; overload;
    function Returns(Value: Boolean): IWhen<T>; overload;
    function Returns(Value: Double): IWhen<T>; overload;
    function Returns(Value: Int64): IWhen<T>; overload;
    function Throws(ExceptionClass: ExceptClass; const Msg: string = ''): IWhen<T>;
    function Executes(const Action: TProc<IInvocation>): IWhen<T>;
    function Callback(const Action: TProc<TArray<TValue>>): IWhen<T>;
  end;

  TWhen<T> = class(TInterfacedObject, IWhen<T>)
  private
    FMock: IMock<T>;
    FProxyRef: IInterface;
    FProxy: T;
  public
    constructor Create(const AMock: IMock<T>; const AProxy: T);
    function When: T;
  end;

  TMock<T> = class(TInterfacedObject, IMock, IMock<T>)
  private
    FInterceptorObj: TMockInterceptor;
    FInterceptor: IInterceptor;
    FInstance: T;
    FClassProxy: TClassProxy;
    FOwnsProxy: Boolean;
  public
    constructor Create(ABehavior: TMockBehavior); overload;
    constructor Create(AInterceptor: TMockInterceptor); overload;
    constructor Create(AInterceptor: TMockInterceptor; AClassProxy: TClassProxy; AOwnsProxy: Boolean); overload;
    destructor Destroy; override;

    // IMock
    function GetInstanceValue: TValue;
    procedure Verify;
    procedure VerifyNoOtherCalls;
    procedure Reset;

    // IMock<T>
    function GetInstance: T;
    function GetBehavior: TMockBehavior;
    procedure SetBehavior(Value: TMockBehavior);
    function Setup: ISetup<T>;
    function Received: T; overload;
    function Received(const ATimes: Times): T; overload;
    function DidNotReceive: T;
    procedure SetCallBase(Value: Boolean);

    property Instance: T read GetInstance;
  end;

implementation

uses
  Dext.Mocks.Matching,
  Dext.Interception.Proxy;

{ TMethodSetup }

constructor TMethodSetup.Create(const AName: string);
begin
  inherited Create;
  FName := AName;
  FCurrentValueIndex := 0;
end;

function DextTValueEquals(const V1, V2: TValue): Boolean;
begin
  if V1.TypeInfo <> V2.TypeInfo then 
  begin
    if V1.IsEmpty and V2.IsEmpty then Exit(True);
    if (V1.Kind in [tkChar, tkWChar, tkString, tkWString, tkLString, tkUString]) and
       (V2.Kind in [tkChar, tkWChar, tkString, tkWString, tkLString, tkUString]) then
      Exit(V1.AsString = V2.AsString);
    Exit(False);
  end;
  if V1.IsEmpty then Exit(V2.IsEmpty);
  if V2.IsEmpty then Exit(False);
  case V1.Kind of
    tkInteger, tkInt64, tkEnumeration: Result := V1.AsOrdinal = V2.AsOrdinal;
    tkFloat: Result := V1.AsExtended = V2.AsExtended;
    tkString, tkLString, tkWString, tkUString: Result := V1.AsString = V2.AsString;
    tkVariant: Result := V1.AsVariant = V2.AsVariant;
    tkClass: Result := V1.AsObject = V2.AsObject;
    tkInterface: Result := V1.AsInterface = V2.AsInterface;
    else Result := V1.ToString = V2.ToString;
  end;
end;

function IsDefaultValue(const V: TValue): Boolean;
var
  P: PByte;
  I: Integer;
begin
  if V.IsEmpty then Exit(True);
  P := V.GetReferenceToRawData;
  if P = nil then Exit(True);
  for I := 0 to V.DataSize - 1 do
    if P[I] <> 0 then Exit(False);
  Result := True;
end;

function IsMatcherCompatible(const Matcher: TArgMatcher; ParamType: PTypeInfo): Boolean;
const
  StringKinds = [tkChar, tkWChar, tkString, tkWString, tkLString, tkUString];
begin
  if (Matcher.TypeInfo = nil) or (ParamType = nil) then Exit(True);
  if Matcher.TypeInfo = ParamType then Exit(True);
  if (Matcher.TypeInfo.Kind in StringKinds) and (ParamType.Kind in StringKinds) then Exit(True);
  Result := (Matcher.TypeInfo.Kind = ParamType.Kind) and
    SameText(string(Matcher.TypeInfo.Name), string(ParamType.Name));
end;

function FormatArgument(const V: TValue): string;
begin
  if V.IsEmpty then Exit('nil');
  case V.Kind of
    tkChar, tkWChar, tkString, tkWString, tkLString, tkUString:
      Result := QuotedStr(V.AsString);
    tkClass:
      if V.AsObject = nil then Result := 'nil' else Result := V.AsObject.ClassName;
    tkInterface:
      if V.AsInterface = nil then Result := 'nil' else Result := '<interface>';
  else
    try
      Result := V.ToString;
    except
      Result := '?';
    end;
  end;
end;

function FormatCall(const AMethodName: string; const Args: TArray<TValue>): string;
var
  I: Integer;
begin
  Result := AMethodName + '(';
  for I := 0 to High(Args) do
  begin
    if I > 0 then Result := Result + ', ';
    Result := Result + FormatArgument(Args[I]);
  end;
  Result := Result + ')';
end;

/// <summary>
///   Builds one predicate per parameter. Arg.* matchers are placed on the
///   parameters that received their placeholder (the default value of the
///   matcher type); every other parameter must equal the literal passed.
///   Raises when more than one placement is possible, so a literal default
///   value (0, '', nil) never silently swallows a matcher.
/// </summary>
function ResolveArgumentMatchers(const Method: TRttiMethod; const Args: TArray<TValue>;
  const Entries: TArray<TArgMatcher>; out Description: string): TArray<TPredicate<TValue>>;
var
  Params: TArray<TRttiParameter>;
  ParamTypes: TArray<PTypeInfo>;
  Ways: TArray<TArray<Integer>>;
  Assigned_: TArray<Integer>;
  ArgCount, MatcherCount, I, K: Integer;
  MethodName, Part: string;

  function CanTake(AMatcher, AArg: Integer): Boolean;
  begin
    Result := IsDefaultValue(Args[AArg]) and IsMatcherCompatible(Entries[AMatcher], ParamTypes[AArg]);
  end;

  function MakeLiteral(const Expected: TValue): TPredicate<TValue>;
  begin
    Result := function(Actual: TValue): Boolean
      begin
        Result := DextTValueEquals(Actual, Expected);
      end;
  end;

begin
  ArgCount := Length(Args);
  MatcherCount := Length(Entries);
  if Method <> nil then MethodName := Method.Name else MethodName := '?';

  SetLength(ParamTypes, ArgCount);
  if Method <> nil then
  begin
    Params := Method.GetParameters;
    if Length(Params) = ArgCount then
      for I := 0 to ArgCount - 1 do
        if Params[I].ParamType <> nil then
          ParamTypes[I] := Params[I].ParamType.Handle;
  end;

  if MatcherCount > ArgCount then
    raise EMockException.CreateFmt(
      '%s received %d argument matchers for %d parameters. An Arg.* call was made outside a Setup or Received expression.',
      [MethodName, MatcherCount, ArgCount]);

  SetLength(Assigned_, ArgCount);
  for I := 0 to ArgCount - 1 do
    Assigned_[I] := -1;

  if MatcherCount = ArgCount then
  begin
    for I := 0 to ArgCount - 1 do
      Assigned_[I] := I;
  end
  else if MatcherCount > 0 then
  begin
    // Ways[K][I] = number of placements of matchers K.. on arguments I.., capped at 2
    SetLength(Ways, MatcherCount + 1);
    for K := 0 to MatcherCount do
      SetLength(Ways[K], ArgCount + 1);
    for I := 0 to ArgCount do
      Ways[MatcherCount][I] := 1;
    for K := MatcherCount - 1 downto 0 do
    begin
      Ways[K][ArgCount] := 0;
      for I := ArgCount - 1 downto 0 do
      begin
        Ways[K][I] := Ways[K][I + 1];
        if CanTake(K, I) then
          Ways[K][I] := Ways[K][I] + Ways[K + 1][I + 1];
        if Ways[K][I] > 2 then Ways[K][I] := 2;
      end;
    end;

    if Ways[0][0] = 0 then
      raise EMockException.CreateFmt(
        'Could not place %d argument matcher(s) on the parameters of %s. Use an Arg.* matcher for every parameter.',
        [MatcherCount, MethodName]);
    if Ways[0][0] > 1 then
      raise EMockException.CreateFmt(
        'Ambiguous argument matchers for %s: a literal default value (0, '''', nil) sits next to an Arg.* matcher of the same type. ' +
        'Use Arg.IsEqual for that literal, or an Arg.* matcher for every parameter.',
        [MethodName]);

    K := 0;
    I := 0;
    while K < MatcherCount do
    begin
      if CanTake(K, I) and (Ways[K + 1][I + 1] > 0) then
      begin
        Assigned_[I] := K;
        Inc(K);
      end;
      Inc(I);
    end;
  end;

  SetLength(Result, ArgCount);
  Description := MethodName + '(';
  for I := 0 to ArgCount - 1 do
  begin
    if Assigned_[I] >= 0 then
    begin
      Result[I] := Entries[Assigned_[I]].Predicate;
      Part := '<matcher>';
    end
    else
    begin
      Result[I] := MakeLiteral(Args[I]);
      Part := FormatArgument(Args[I]);
    end;
    if I > 0 then Description := Description + ', ';
    Description := Description + Part;
  end;
  Description := Description + ')';
end;

function MatchesAll(const Matchers: TArray<TPredicate<TValue>>; const Args: TArray<TValue>): Boolean;
var
  I: Integer;
begin
  if Length(Args) <> Length(Matchers) then Exit(False);
  for I := 0 to High(Args) do
    if Assigned(Matchers[I]) and not Matchers[I](Args[I]) then Exit(False);
  Result := True;
end;

function TMethodSetup.MatchesArguments(const Args: TArray<TValue>): Boolean;
var
  I: Integer;
begin
  if Length(FArgumentMatchers) = 0 then
  begin
    if Length(Args) <> Length(FSetupArguments) then Exit(False);
    for I := 0 to High(Args) do
       if not DextTValueEquals(Args[I], FSetupArguments[I]) then Exit(False);
    Exit(True);
  end;
  
  Result := MatchesAll(FArgumentMatchers, Args);
end;

function TMethodSetup.GetNextReturnValue: TValue;
begin
  if Length(FReturnValues) = 0 then Exit(TValue.Empty);
  Result := FReturnValues[FCurrentValueIndex];
  if FCurrentValueIndex < High(FReturnValues) then Inc(FCurrentValueIndex);
end;

{ TMethodCall }

constructor TMethodCall.Create(const AName: string; const AArguments: TArray<TValue>);
begin
  inherited Create;
  FName := AName;
  FArguments := AArguments;
  FVerified := False;
end;

{ TMockInterceptor }

constructor TMockInterceptor.Create(ABehavior: TMockBehavior);
begin
  inherited Create;
  FBehavior := ABehavior;
  FState := TMockState.Acting;
  FSetups := TCollections.CreateObjectList<TMethodSetup>(True);
  FReceivedCalls := TCollections.CreateObjectList<TMethodCall>(True);
end;

destructor TMockInterceptor.Destroy;
begin
  // Lists are ARC
  inherited;
end;

procedure TMockInterceptor.Intercept(const Invocation: IInvocation);
var
  MethodName, Description: string;
  Setup: TMethodSetup;
  I: Integer;
  MatchingCall: TMethodCall;
  CallCount: Integer;
  Matchers: TArray<TPredicate<TValue>>;
  CallBase: IInvocationCallBase;
begin
  MethodName := Invocation.Method.Name;
  case FState of
    TMockState.Arranging:
    begin
      FState := TMockState.Acting;
      Setup := FPendingSetup;
      FPendingSetup := nil;
      if Assigned(Setup) then
      begin
        try
          Setup.FName := MethodName;
          Setup.FSetupArguments := Copy(Invocation.Arguments);
          Setup.FArgumentMatchers := ResolveArgumentMatchers(Invocation.Method,
            Invocation.Arguments, TMatcherFactory.GetMatcherEntries, Setup.FDescription);
        except
          Setup.Free;
          raise;
        end;
        FSetups.Add(Setup);
      end;
    end;
    TMockState.Acting:
    begin
      FReceivedCalls.Add(TMethodCall.Create(MethodName, Copy(Invocation.Arguments)));
      for I := FSetups.Count - 1 downto 0 do
      begin
        Setup := FSetups[I];
        if SameText(Setup.Name, MethodName) and Setup.MatchesArguments(Invocation.Arguments) then
        begin
          if Assigned(Setup.Action) then Setup.Action(Invocation);
          if Setup.ExceptionClass <> nil then raise Setup.ExceptionClass.Create(Setup.ExceptionMessage);
          
          // Only overwrite result if ReturnValues were explicitly set
          if Length(Setup.ReturnValues) > 0 then
            Invocation.Result := Setup.GetNextReturnValue;
          Exit;
        end;
      end;
      if FCallBase and Supports(Invocation, IInvocationCallBase, CallBase) then
      begin
        CallBase.RequestCallBase;
        Exit;
      end;
      if FBehavior = TMockBehavior.Strict then
        raise EMockException.CreateFmt('Unexpected call to %s',
          [FormatCall(MethodName, Invocation.Arguments)]);
    end;
    TMockState.Asserting:
    begin
      FState := TMockState.Acting;
      Matchers := ResolveArgumentMatchers(Invocation.Method, Invocation.Arguments,
        TMatcherFactory.GetMatcherEntries, Description);
      CallCount := 0;
      for MatchingCall in FReceivedCalls do
      begin
        if SameText(MatchingCall.Name, MethodName) and MatchesAll(Matchers, MatchingCall.Arguments) then
        begin
          Inc(CallCount);
          MatchingCall.Verified := True;
        end;
      end;
      if not FVerifyTimes.Matches(CallCount) then
        raise EMockException.Create(FVerifyTimes.ToString(CallCount) + ' for ' + Description +
          DescribeReceivedCalls(MethodName));
    end;
  end;
end;

function TMockInterceptor.DescribeReceivedCalls(const AMethodName: string): string;
var
  Call: TMethodCall;
begin
  Result := '';
  for Call in FReceivedCalls do
    if SameText(Call.Name, AMethodName) then
      Result := Result + sLineBreak + '    ' + FormatCall(Call.Name, Call.Arguments);
  if Result = '' then
    Result := '. No calls to ' + AMethodName + ' were received.'
  else
    Result := '. Received calls:' + Result;
end;

procedure TMockInterceptor.Verify;
var
  Setup: TMethodSetup;
  Call: TMethodCall;
  Exercised: Boolean;
  Missing: string;
begin
  Missing := '';
  for Setup in FSetups do
  begin
    Exercised := False;
    for Call in FReceivedCalls do
      if SameText(Call.Name, Setup.Name) and Setup.MatchesArguments(Call.Arguments) then
      begin
        Exercised := True;
        Break;
      end;
    if not Exercised then
      Missing := Missing + sLineBreak + '    ' + Setup.Description;
  end;
  if Missing <> '' then
    raise EMockException.Create('Expected every setup to be called, but these were never called:' + Missing);
end;

procedure TMockInterceptor.BeginSetup(ASetup: TMethodSetup);
begin
  FPendingSetup := ASetup;
  FState := TMockState.Arranging;
end;

procedure TMockInterceptor.BeginVerify(const ATimes: Times);
begin
  FVerifyTimes := ATimes;
  FState := TMockState.Asserting;
end;

procedure TMockInterceptor.VerifyNoOtherCalls;
var
  Call: TMethodCall;
begin
  for Call in FReceivedCalls do
    if not Call.Verified then raise EMockException.CreateFmt('Unverified call to %s', [Call.Name]);
end;

procedure TMockInterceptor.Reset;
begin
  FSetups.Clear;
  FReceivedCalls.Clear;
  FPendingSetup := nil;
  FState := TMockState.Acting;
end;

procedure TMockInterceptor.ClearInterceptors;
begin
  FSetups.Clear;
  FReceivedCalls.Clear;
  FPendingSetup := nil;
end;

{ TSetup<T> }

constructor TSetup<T>.Create(const AMock: IMock<T>; AInterceptor: TMockInterceptor; const AProxy: T);
begin
  inherited Create;
  FMock := AMock;
  FInterceptor := AInterceptor;
  FProxy := AProxy;
end;

function TSetup<T>.Returns(const Value: TValue): IWhen<T>;
var
  S: TMethodSetup;
begin
  S := TMethodSetup.Create('');
  S.ReturnValues := [Value];
  FInterceptor.BeginSetup(S);
  Result := TWhen<T>.Create(FMock, FProxy);
end;

function TSetup<T>.Returns(const Values: TArray<TValue>): IWhen<T>;
var
  S: TMethodSetup;
begin
  S := TMethodSetup.Create('');
  S.ReturnValues := Values;
  FInterceptor.BeginSetup(S);
  Result := TWhen<T>.Create(FMock, FProxy);
end;

function TSetup<T>.Returns(Value: Integer): IWhen<T>;
begin
  Result := Returns(TValue.From<Integer>(Value));
end;

function TSetup<T>.Returns(const Value: string): IWhen<T>;
begin
  Result := Returns(TValue.From<string>(Value));
end;

function TSetup<T>.Returns(Value: Boolean): IWhen<T>;
begin
  Result := Returns(TValue.From<Boolean>(Value));
end;

function TSetup<T>.Returns(Value: Double): IWhen<T>;
begin
  Result := Returns(TValue.From<Double>(Value));
end;

function TSetup<T>.Returns(Value: Int64): IWhen<T>;
begin
  Result := Returns(TValue.From<Int64>(Value));
end;

function TSetup<T>.Throws(ExceptionClass: ExceptClass; const Msg: string): IWhen<T>;
var
  S: TMethodSetup;
begin
  S := TMethodSetup.Create('');
  S.ExceptionClass := ExceptionClass;
  S.ExceptionMessage := Msg;
  FInterceptor.BeginSetup(S);
  Result := TWhen<T>.Create(FMock, FProxy);
end;

function TSetup<T>.Executes(const Action: TProc<IInvocation>): IWhen<T>;
var
  S: TMethodSetup;
begin
  S := TMethodSetup.Create('');
  S.Action := Action;
  FInterceptor.BeginSetup(S);
  Result := TWhen<T>.Create(FMock, FProxy);
end;

function TSetup<T>.ReturnsInSequence(const Values: TArray<TValue>): IWhen<T>; begin Result := Returns(Values); end;

function TSetup<T>.ReturnsInSequence(const Values: TArray<Integer>): IWhen<T>;
var
  V: TArray<TValue>;
  I: Integer;
begin
  SetLength(V, Length(Values));
  for I := 0 to High(Values) do V[I] := TValue.From<Integer>(Values[I]);
  Result := Returns(V);
end;

function TSetup<T>.ReturnsInSequence(const Values: TArray<string>): IWhen<T>;
var
  V: TArray<TValue>;
  I: Integer;
begin
  SetLength(V, Length(Values));
  for I := 0 to High(Values) do V[I] := TValue.From<string>(Values[I]);
  Result := Returns(V);
end;

function TSetup<T>.ReturnsInSequence(const Values: TArray<Boolean>): IWhen<T>;
var
  V: TArray<TValue>;
  I: Integer;
begin
  SetLength(V, Length(Values));
  for I := 0 to High(Values) do V[I] := TValue.From<Boolean>(Values[I]);
  Result := Returns(V);
end;

function TSetup<T>.Callback(const Action: TProc<TArray<TValue>>): IWhen<T>;
begin
  Result := Executes(procedure(Inv: IInvocation)
    begin
      if Assigned(Action) then Action(Inv.Arguments);
    end);
end;

{ TWhen<T> }

constructor TWhen<T>.Create(const AMock: IMock<T>; const AProxy: T);
begin
  inherited Create;
  FMock := AMock;
  FProxy := AProxy;
  if GetTypeKind(T) = tkInterface then FProxyRef := IInterface(PPointer(@AProxy)^) else FProxyRef := nil;
end;

function TWhen<T>.When: T; begin Result := FProxy; end;

{ TMock<T> }

constructor TMock<T>.Create(ABehavior: TMockBehavior);
var
  Info: PTypeInfo;
  Proxy: TClassProxy;
begin
  inherited Create;
  FInterceptorObj := TMockInterceptor.Create(ABehavior);
  FInterceptor := FInterceptorObj;
  Info := TypeInfo(T);
  FOwnsProxy := True;
  if Info.Kind = tkInterface then
    FInstance := TProxy.CreateInterface<T>(FInterceptor)
  else if Info.Kind = tkClass then
  begin
    Proxy := TClassProxy.Create(Info.TypeData.ClassType, [FInterceptor]);
    FClassProxy := Proxy;
    FInstance := TValue.From(Proxy.Instance).AsType<T>;
  end
  else
    raise Exception.Create('Mock<T> only supports interfaces and classes');
end;

constructor TMock<T>.Create(AInterceptor: TMockInterceptor);
var
  Info: PTypeInfo;
  Proxy: TClassProxy;
begin
  inherited Create;
  FInterceptorObj := AInterceptor;
  FInterceptor := FInterceptorObj;
  Info := TypeInfo(T);
  FOwnsProxy := True;
  if Info.Kind = tkInterface then
    FInstance := TProxy.CreateInterface<T>(FInterceptor)
  else if Info.Kind = tkClass then
  begin
    Proxy := TClassProxy.Create(Info.TypeData.ClassType, [FInterceptor]);
    FClassProxy := Proxy;
    FInstance := TValue.From(Proxy.Instance).AsType<T>;
  end;
end;

constructor TMock<T>.Create(AInterceptor: TMockInterceptor; AClassProxy: TClassProxy; AOwnsProxy: Boolean);
begin
  inherited Create;
  FInterceptorObj := AInterceptor;
  FInterceptor := FInterceptorObj;
  FClassProxy := AClassProxy;
  FOwnsProxy := AOwnsProxy;
  FInstance := TValue.From(FClassProxy.Instance).AsType<T>;
end;

destructor TMock<T>.Destroy;
begin
  if FOwnsProxy then 
    FreeAndNil(FClassProxy);
  inherited;
end;


function TMock<T>.GetInstanceValue: TValue;
begin
  Result := TValue.From<T>(FInstance);
end;

procedure TMock<T>.Verify;
begin
  FInterceptorObj.Verify;
end;

procedure TMock<T>.VerifyNoOtherCalls;
begin
  FInterceptorObj.VerifyNoOtherCalls;
end;

procedure TMock<T>.Reset;
begin
  FInterceptorObj.Reset;
end;

function TMock<T>.GetInstance: T;
begin
  Result := FInstance;
end;

function TMock<T>.GetBehavior: TMockBehavior;
begin
  Result := FInterceptorObj.Behavior;
end;

procedure TMock<T>.SetBehavior(Value: TMockBehavior);
begin
  FInterceptorObj.Behavior := Value;
end;

function TMock<T>.Setup: ISetup<T>;
begin
  Result := TSetup<T>.Create(Self, FInterceptorObj, FInstance);
end;

function TMock<T>.Received: T;
begin
  Result := Received(Times.AtLeastOnce);
end;

function TMock<T>.Received(const ATimes: Times): T;
begin
  FInterceptorObj.BeginVerify(ATimes);
  Result := FInstance;
end;

function TMock<T>.DidNotReceive: T;
begin
  Result := Received(Times.Never);
end;

procedure TMock<T>.SetCallBase(Value: Boolean);
begin
  FInterceptorObj.CallBase := Value;
end;

end.
