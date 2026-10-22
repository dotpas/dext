{***************************************************************************}
{                                                                           }
{           Dext Framework                                                  }
{                                                                           }
{           Copyright (C) 2026 Cesar Romero & Dext Contributors             }
{                                                                           }
{           Licensed under the Apache License, Version 2.0 (the "License"); }
{           you may not use this file except in compliance with the License. }
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
unit Dext.Codecs.S54.Tests;

interface

uses
  System.Classes,
  System.IOUtils,
  System.Rtti,
  System.SysUtils,
  Dext.Collections,
  Dext.Core.Activator,
  Dext.Core.DirectAccess,
  Dext.Core.TypeModel,
  Dext.Core.ValueConverters,
  Dext.Codecs.Registry,
  Dext.Types.UUID,
  Dext.Entity.Dialects,
  Dext.Entity.TypeConverters,
  Dext.Json,
  Dext.Serialization.Protobuf,
  Dext.Grpc.Attributes,
  Dext.Hosting.CLI.Args,
  Dext.Hosting.CLI.Commands.Codecs,
  Dext.Testing;

type
  [GrpcMessage]
  TCodecChild = class
  private
    FName: string;
  public
    [ProtoMember(1)]
    property Name: string read FName write FName;
  end;

  [GrpcMessage]
  TCodecRoot = class
  private
    FId: Integer;
    FName: string;
    FItems: IList<TCodecChild>;
  public
    constructor Create;
    destructor Destroy; override;
    [ProtoMember(1)]
    property Id: Integer read FId write FId;
    [ProtoMember(2)]
    property Name: string read FName write FName;
    [ProtoMember(3)]
    property Items: IList<TCodecChild> read FItems write FItems;
  end;

  [GrpcMessage]
  TCodecScalarListRoot = class
  private
    FValues: IList<Integer>;
  public
    constructor Create;
    destructor Destroy; override;
    [ProtoMember(1)]
    property Values: IList<Integer> read FValues write FValues;
  end;

  [GrpcMessage]
  TCodecNestedRoot = class
  private
    FChild: TCodecChild;
    FItems: IList<TCodecChild>;
  public
    constructor Create;
    destructor Destroy; override;
    [ProtoMember(1)]
    property Child: TCodecChild read FChild write FChild;
    [ProtoMember(2)]
    property Items: IList<TCodecChild> read FItems write FItems;
  end;


  TUuidTarget = class
  private
    FGuid: TGUID;
    FUuid: TUUID;
  public
    property GuidValue: TGUID read FGuid write FGuid;
    property UuidValue: TUUID read FUuid write FUuid;
  end;

  TDirectTarget = class
  private
    FCount: Integer;
    FName: string;
    FActive: Boolean;
  public
    property Count: Integer read FCount write FCount;
    property Name: string read FName write FName;
    property Active: Boolean read FActive write FActive;
  end;

  [TestFixture('S54 - TypeModel')]
  TTypeModelTests = class
  public
    [Test]
    procedure ShouldBuildPlansForDirectAndListFields;
    [Test]
    procedure ShouldClassifyNativeKinds;
    [Test]
    procedure ShouldRoundtripGuidAndUuidAcrossDirectPaths;
  end;

  [TestFixture('S54 - DirectAccess')]
  TDirectAccessTests = class
  public
    [Test]
    procedure ShouldReadAndWriteFieldsByOffset;
    [Test]
    procedure ShouldConvertDatabaseValuesToBoolean;
    [Test]
    procedure ShouldRoundtripGuidAndUuidAcrossDirectPaths;
  end;

  [TestFixture('S54 - ArrayConverter')]
  TArrayConverterTests = class
  public
    [Test]
    procedure ShouldDeserializeJsonArrayIntoTypedArray;
  end;

  [TestFixture('S54 - TypeConverterRegistry')]
  TTypeConverterRegistryTests = class
  public
    [Test]
    procedure ShouldResolveArrayConverterAutomatically;
  end;

  [TestFixture('S54 - CLI Codecs')]
  TCodecsCommandTests = class
  public
    [Test]
    procedure ShouldGenerateProtoAndStaticCodecsForNestedLists;
    [Test]
    procedure ShouldSerializeAndDeserializeNestedObjectWithDirectCodec;
    [Test]
    procedure ShouldRoundtripNestedObjectThroughDirectJsonCodec;
    [Test]
    procedure ShouldMatchRttiDirectAndGeneratedProtobufBytes;
    [Test]
    procedure ShouldGenerateGrpcInvokersForServices;
    [Test]
    procedure ShouldGenerateCodecsForNullableAndNestedListEdgeCases;
    [Test]
    procedure ShouldGenerateCodecsForGuidAndUuidFields;
    [Test]
    procedure ShouldRoundtripNestedJsonColumnThroughConverter;
  end;

implementation

constructor TCodecRoot.Create;
begin
  inherited Create;
  FItems := TCollections.CreateList<TCodecChild>(True);
end;

destructor TCodecRoot.Destroy;
begin
  FItems := nil;
  inherited;
end;

constructor TCodecScalarListRoot.Create;
begin
  inherited Create;
  FValues := TCollections.CreateList<Integer>;
end;

destructor TCodecScalarListRoot.Destroy;
begin
  FValues := nil;
  inherited;
end;

constructor TCodecNestedRoot.Create;
begin
  inherited Create;
  FChild := TCodecChild.Create;
  FItems := TCollections.CreateList<TCodecChild>(True);
end;

destructor TCodecNestedRoot.Destroy;
begin
  FChild.Free;
  FItems := nil;
  inherited;
end;

procedure WriteCodecChild(AWriter: TObject; AObj: TObject);
begin
  TProtobufWriter(AWriter).WriteString(1, TCodecChild(AObj).Name);
end;

procedure ReadCodecChild(AReader: TObject; AObj: TObject);
var
  Reader: TProtobufReader;
begin
  Reader := TProtobufReader(AReader);
  while Reader.ReadField do
    case Reader.Tag of
      1: TCodecChild(AObj).Name := Reader.ReadString;
    else
      Reader.SkipField;
    end;
end;

function BytesEqual(const Left, Right: TBytes): Boolean;
var
  i: Integer;
begin
  if Length(Left) <> Length(Right) then
    Exit(False);
  for i := 0 to High(Left) do
    if Left[i] <> Right[i] then
      Exit(False);
  Result := True;
end;

procedure TTypeModelTests.ShouldBuildPlansForDirectAndListFields;
var
  Plan: IDextTypeCodecPlan;
  Field: TDextFieldPlan;
begin
  Plan := TDextTypeModel.GetPlan(TypeInfo(TCodecRoot));
  Should(Plan <> nil).BeTrue;
  Should(Plan.HasDirectAccess).BeTrue;
  Should(Plan.HasGeneratedCodec).BeFalse;
  Should(Length(Plan.GetFields)).Be(3);
  Should(Plan.TryGetFieldByProtoTag(1, Field)).BeTrue;
  Should(Field.Name).Be('Id');
  Should(Field.NativeKind).Be(nkInt32);
  Should(Field.AccessMode).Be(amDirectField);
  Should(Plan.TryGetFieldByProtoTag(3, Field)).BeTrue;
  Should(Field.IsList).BeTrue;
  Should(Field.ElementType = TypeInfo(TCodecChild)).BeTrue;
end;

procedure TTypeModelTests.ShouldClassifyNativeKinds;
begin
  Should(TDextTypeModel.NativeKindOf(TypeInfo(Integer))).Be(nkInt32);
  Should(TDextTypeModel.NativeKindOf(TypeInfo(Boolean))).Be(nkBoolean);
  Should(TDextTypeModel.NativeKindOf(TypeInfo(TDateTime))).Be(nkDateTime);
  Should(TDextTypeModel.NativeKindOf(TypeInfo(string))).Be(nkString);
end;

procedure TTypeModelTests.ShouldRoundtripGuidAndUuidAcrossDirectPaths;
var
  Plan: IDextTypeCodecPlan;
begin
  Should(TDextTypeModel.NativeKindOf(TypeInfo(TGUID))).Be(nkGuid);
  Should(TDextTypeModel.NativeKindOf(TypeInfo(TUUID))).Be(nkUuid);
  Plan := TDextTypeModel.GetPlan(TypeInfo(TUuidTarget));
  Should(Plan <> nil).BeTrue;
end;

procedure TDirectAccessTests.ShouldReadAndWriteFieldsByOffset;
var
  Target: TDirectTarget;
  RttiContext: TRttiContext;
  RttiType: TRttiType;
  FieldCount: TRttiField;
  FieldName: TRttiField;
  FieldActive: TRttiField;
begin
  Target := TDirectTarget.Create;
  try
    RttiContext := TRttiContext.Create;
    RttiType := RttiContext.GetType(TypeInfo(TDirectTarget));
    FieldCount := RttiType.GetField('FCount');
    FieldName := RttiType.GetField('FName');
    FieldActive := RttiType.GetField('FActive');

    TDextDirectAccess.WriteInt32(Target, FieldCount.Offset, 42);
    TDextDirectAccess.WriteString(Target, FieldName.Offset, 'Dext');
    TDextDirectAccess.WriteBoolean(Target, FieldActive.Offset, True);

    Should(TDextDirectAccess.ReadInt32(Target, FieldCount.Offset)).Be(42);
    Should(TDextDirectAccess.ReadString(Target, FieldName.Offset)).Be('Dext');
    Should(TDextDirectAccess.ReadBoolean(Target, FieldActive.Offset)).BeTrue;
  finally
    Target.Free;
  end;
end;

procedure TDirectAccessTests.ShouldRoundtripGuidAndUuidAcrossDirectPaths;
var
  Target: TUuidTarget;
  RttiContext: TRttiContext;
  RttiType: TRttiType;
  GuidField: TRttiField;
  UuidField: TRttiField;
  GuidValue: TGUID;
  UuidValue: TUUID;
begin
  Target := TUuidTarget.Create;
  try
    RttiContext := TRttiContext.Create;
    RttiType := RttiContext.GetType(TypeInfo(TUuidTarget));
    GuidField := RttiType.GetField('FGuid');
    UuidField := RttiType.GetField('FUuid');

    GuidValue := StringToGUID('{6F9619FF-8B86-D011-B42D-00C04FC964FF}');
    UuidValue := TUUID.FromString('6f9619ff-8b86-d011-b42d-00c04fc964ff');

    TDextDirectAccess.WriteGUID(Target, GuidField.Offset, GuidValue);
    TDextDirectAccess.WriteUUID(Target, UuidField.Offset, UuidValue);

    Should(TDextDirectAccess.ReadGUID(Target, GuidField.Offset)).Be(GuidValue);
    Should(TDextDirectAccess.ReadUUID(Target, UuidField.Offset)).Be(UuidValue);
  finally
    Target.Free;
  end;
end;

procedure TDirectAccessTests.ShouldConvertDatabaseValuesToBoolean;
var
  IntegerValue: TValue;
  StringValue: TValue;
  Converted: TValue;
begin
  IntegerValue := TValue.From<Integer>(1);
  StringValue := TValue.From<string>('False');

  Converted := TValueConverter.Convert(IntegerValue, TypeInfo(Boolean));
  Should(Converted.AsBoolean).BeTrue;

  Converted := TValueConverter.Convert(StringValue, TypeInfo(Boolean));
  Should(Converted.AsBoolean).BeFalse;
end;

procedure TTypeConverterRegistryTests.ShouldResolveArrayConverterAutomatically;
var
  Converter: ITypeConverter;
  InputValue: TValue;
  OutputValue: TValue;
  Data: TArray<string>;
begin
  Converter := TTypeConverterRegistry.Instance.GetConverter(TypeInfo(TArray<string>));
  Should(Converter <> nil).BeTrue;
  Should(Converter is TArrayConverter).BeTrue;

  SetLength(Data, 2);
  Data[0] := 'alpha';
  Data[1] := 'beta';

  InputValue := TValue.From<TArray<string>>(Data);
  OutputValue := Converter.ToDatabase(InputValue, ddSQLite);
  Should(OutputValue.IsEmpty).BeFalse;

  OutputValue := Converter.FromDatabase(OutputValue, TypeInfo(TArray<string>));
  Data := OutputValue.AsType<TArray<string>>;
  Should(Length(Data)).Be(2);
  Should(Data[0]).Be('alpha');
  Should(Data[1]).Be('beta');
end;

procedure TArrayConverterTests.ShouldDeserializeJsonArrayIntoTypedArray;
var
  Converter: TArrayConverter;
  Value: TValue;
  Data: TArray<string>;
begin
  Converter := TArrayConverter.Create;
  try
    Value := Converter.FromDatabase(TValue.From<string>('["alpha","beta"]'), TypeInfo(TArray<string>));
    Should(Value.IsEmpty).BeFalse;

    Data := Value.AsType<TArray<string>>;
    Should(Length(Data)).Be(2);
    Should(Data[0]).Be('alpha');
    Should(Data[1]).Be('beta');
  finally
    Converter.Free;
  end;
end;

procedure TCodecsCommandTests.ShouldMatchRttiDirectAndGeneratedProtobufBytes;
var
  Source: TCodecChild;
  Target: TCodecChild;
  AutoBytes: TBytes;
  RttiBytes: TBytes;
  DirectBytes: TBytes;
  GeneratedBytes: TBytes;
begin
  TDextCodecRegistry.RegisterProtobuf<TCodecChild>(WriteCodecChild, ReadCodecChild);

  Source := TCodecChild.Create;
  Target := TCodecChild.Create;
  try
    Source.Name := 'Nested';

    RttiBytes := TProtobufSerializer.Serialize(Source, pcmRtti);
    DirectBytes := TProtobufSerializer.Serialize(Source, pcmDirect);
    GeneratedBytes := TProtobufSerializer.Serialize(Source, pcmGenerated);
    AutoBytes := TProtobufSerializer.Serialize(Source, pcmAuto);

    Should(BytesEqual(RttiBytes, DirectBytes)).BeTrue;
    Should(BytesEqual(RttiBytes, GeneratedBytes)).BeTrue;
    Should(BytesEqual(DirectBytes, GeneratedBytes)).BeTrue;
    Should(BytesEqual(GeneratedBytes, AutoBytes)).BeTrue;

    TProtobufSerializer.Deserialize(GeneratedBytes, Target, pcmDirect);
    Should(Target.Name).Be('Nested');
  finally
    Target.Free;
    Source.Free;
  end;
end;

procedure TCodecsCommandTests.ShouldGenerateGrpcInvokersForServices;
var
  TempDir: string;
  InputFile: string;
  GeneratedUnit: string;
  SourceText: string;
  Args: TCommandLineArgs;
  Command: TCodecsCommand;
  Lines: TStringList;
begin
  TempDir := TPath.Combine(TPath.GetTempPath, 'DextS54GrpcCodecs');
  if not TDirectory.Exists(TempDir) then
    TDirectory.CreateDirectory(TempDir);

  InputFile := TPath.Combine(TempDir, 'GrpcInput.pas');
  GeneratedUnit := TPath.Combine(TempDir, 'GrpcInput.DextCodecs.pas');

  SourceText :=
    'unit GrpcInput;' + sLineBreak + sLineBreak +
    'interface' + sLineBreak + sLineBreak +
    'uses Dext.Grpc.Attributes;' + sLineBreak + sLineBreak +
    'type' + sLineBreak +
    '  [GrpcMessage]' + sLineBreak +
    '  TGrpcRequest = class' + sLineBreak +
    '  private' + sLineBreak +
    '    FId: Integer;' + sLineBreak +
    '  public' + sLineBreak +
    '    [ProtoMember(1)]' + sLineBreak +
    '    property Id: Integer read FId write FId;' + sLineBreak +
    '  end;' + sLineBreak + sLineBreak +
    '  [GrpcService(''dext.test.v1.DummyService'')]' + sLineBreak +
    '  IDummyService = interface(IInvokable)' + sLineBreak +
    '    [''{E8F8B6C7-674A-4835-AB37-A3BA476C55AF}'']' + sLineBreak +
    '    [GrpcMethod(''DummyCall'')]' + sLineBreak +
    '    function DummyCall(const ARequest: TGrpcRequest): TGrpcRequest;' + sLineBreak +
    '  end;' + sLineBreak + sLineBreak +
    'implementation' + sLineBreak + sLineBreak +
    'initialization' + sLineBreak + sLineBreak +
    '  TActivator.RegisterDefault<IList<TCodecChild>, TList<TCodecChild>>;' + sLineBreak +
    '  TActivator.RegisterDefault<IList<Integer>, TList<Integer>>;' + sLineBreak + sLineBreak +
    'end.';
  TFile.WriteAllText(InputFile, SourceText, TEncoding.UTF8);

  Lines := TStringList.Create;
  try
    Args := TCommandLineArgs.Create;
    try
      Command := TCodecsCommand.Create;
      try
        Args.Parse(['codecs', 'generate', '--unit', InputFile, '--out', GeneratedUnit]);
        Command.Execute(Args);
        Should(TFile.Exists(GeneratedUnit)).BeTrue;
        Lines.LoadFromFile(GeneratedUnit, TEncoding.UTF8);
        Should(Lines.Text).Contain('function Invoke_IDummyService_DummyCall(AService: TObject; ARequest: TObject): TObject;');
        Should(Lines.Text).Contain('Result := IDummyService(AService).DummyCall(TGrpcRequest(ARequest));');
        Should(Lines.Text).Contain('TDextCodecRegistry.RegisterGrpcInvoker(''dext.test.v1.DummyService'', ''DummyCall'', Invoke_IDummyService_DummyCall);');
      finally
        Command.Free;
      end;
    finally
      Args.Free;
    end;
  finally
    Lines.Free;
  end;
end;
procedure TCodecsCommandTests.ShouldSerializeAndDeserializeNestedObjectWithDirectCodec;
var
  Source: TCodecChild;
  Target: TCodecChild;
  Bytes: TBytes;
begin
  Source := TCodecChild.Create;
  Target := TCodecChild.Create;
  try
    Source.Name := 'Nested';

    Bytes := TProtobufSerializer.Serialize(Source, pcmDirect);
    TProtobufSerializer.Deserialize(Bytes, Target, pcmDirect);

    Should(Target.Name).Be('Nested');
  finally
    Target.Free;
    Source.Free;
  end;
end;

procedure TCodecsCommandTests.ShouldRoundtripNestedObjectThroughDirectJsonCodec;
var
  Root: TCodecNestedRoot;
  Target: TCodecNestedRoot;
  JsonText: string;
begin
  Root := TCodecNestedRoot.Create;
  Target := nil;
  try
    Root.Child.Name := 'Nested';
    Root.Items.Add(TCodecChild.Create);
    Root.Items[0].Name := 'Item1';

    JsonText := TDextJson.Serialize<TCodecNestedRoot>(Root);
    Should(JsonText).Contain('Nested');

    Target := TDextJson.Deserialize<TCodecNestedRoot>(JsonText);
    Should(Target <> nil).BeTrue;
    Should(Target.Child <> nil).BeTrue;
    Should(Target.Child.Name).Be('Nested');
    Should(Target.Items.Count).Be(1);
    Should(Target.Items[0].Name).Be('Item1');
  finally
    Target.Free;
    Root.Free;
  end;
end;

[Test]
procedure TCodecsCommandTests.ShouldGenerateCodecsForNullableAndNestedListEdgeCases;
var
  TempDir: string;
  InputFile: string;
  GeneratedUnit: string;
  ProtoFile: string;
  SourceText: string;
  Args: TCommandLineArgs;
  ProtoArgs: TCommandLineArgs;
  Command: TCodecsCommand;
  Lines: TStringList;
  ProtoText: string;
begin
  TempDir := TPath.Combine(TPath.GetTempPath, 'DextS54CodecEdgeCases');
  if not TDirectory.Exists(TempDir) then
    TDirectory.CreateDirectory(TempDir);

  InputFile := TPath.Combine(TempDir, 'CodecInput.pas');
  GeneratedUnit := TPath.Combine(TempDir, 'CodecInput.DextCodecs.pas');
  ProtoFile := TPath.Combine(TempDir, 'CodecInput.proto');

  SourceText :=
    'unit CodecInput;' + sLineBreak + sLineBreak +
    'interface' + sLineBreak + sLineBreak +
    'uses Dext.Grpc.Attributes, Dext.Types.Nullable, Dext.Core.SmartTypes, Dext.Collections, Dext.Types.UUID;' + sLineBreak + sLineBreak +
    'type' + sLineBreak +
    '  [GrpcMessage]' + sLineBreak +
    '  TCodecEdgeChild = class' + sLineBreak +
    '  private' + sLineBreak +
    '    FName: string;' + sLineBreak +
    '  public' + sLineBreak +
    '    [ProtoMember(1)]' + sLineBreak +
    '    property Name: string read FName write FName;' + sLineBreak +
    '  end;' + sLineBreak + sLineBreak +
    '  [GrpcMessage]' + sLineBreak +
    '  TCodecEdgeCase = class' + sLineBreak +
    '  private' + sLineBreak +
    '    FAge: Nullable<Integer>;' + sLineBreak +
    '    FName: Prop<string>;' + sLineBreak +
    '    FTags: IList<Nullable<Integer>>;' + sLineBreak +
    '    FHistory: Nullable<IList<Integer>>;' + sLineBreak +
    '    FMaybeGuid: Nullable<TGUID>;' + sLineBreak +
    '    FMaybeUuid: Prop<TUUID>;' + sLineBreak +
    '    FPropCodes: IList<Prop<string>>;' + sLineBreak +
    '    FOptionalIds: IList<Nullable<TGUID>>;' + sLineBreak +
    '    FOptionalChildren: IList<Nullable<TCodecEdgeChild>>;' + sLineBreak +
    '  public' + sLineBreak +
    '    [ProtoMember(1)]' + sLineBreak +
    '    property Age: Nullable<Integer> read FAge write FAge;' + sLineBreak +
    '    [ProtoMember(2)]' + sLineBreak +
    '    property Name: Prop<string> read FName write FName;' + sLineBreak +
    '    [ProtoMember(3)]' + sLineBreak +
    '    property Tags: IList<Nullable<Integer>> read FTags write FTags;' + sLineBreak +
    '    [ProtoMember(4)]' + sLineBreak +
    '    property History: Nullable<IList<Integer>> read FHistory write FHistory;' + sLineBreak +
    '    [ProtoMember(5)]' + sLineBreak +
    '    property MaybeGuid: Nullable<TGUID> read FMaybeGuid write FMaybeGuid;' + sLineBreak +
    '    [ProtoMember(6)]' + sLineBreak +
    '    property MaybeUuid: Prop<TUUID> read FMaybeUuid write FMaybeUuid;' + sLineBreak +
    '    [ProtoMember(7)]' + sLineBreak +
    '    property PropCodes: IList<Prop<string>> read FPropCodes write FPropCodes;' + sLineBreak +
    '    [ProtoMember(8)]' + sLineBreak +
    '    property OptionalIds: IList<Nullable<TGUID>> read FOptionalIds write FOptionalIds;' + sLineBreak +
    '    [ProtoMember(9)]' + sLineBreak +
    '    property OptionalChildren: IList<Nullable<TCodecEdgeChild>> read FOptionalChildren write FOptionalChildren;' + sLineBreak +
    '  end;' + sLineBreak + sLineBreak +
    'implementation' + sLineBreak + sLineBreak +
    'initialization' + sLineBreak + sLineBreak +
    '  TActivator.RegisterDefault<IList<Nullable<Integer>>, TList<Nullable<Integer>>>;' + sLineBreak +
    '  TActivator.RegisterDefault<IList<Integer>, TList<Integer>>;' + sLineBreak +
    '  TActivator.RegisterDefault<IList<Prop<string>>, TList<Prop<string>>>;' + sLineBreak +
    '  TActivator.RegisterDefault<IList<Nullable<TGUID>>, TList<Nullable<TGUID>>>;' + sLineBreak +
    '  TActivator.RegisterDefault<IList<Nullable<TCodecEdgeChild>>, TList<Nullable<TCodecEdgeChild>>>;' + sLineBreak + sLineBreak +
    'end.';
  TFile.WriteAllText(InputFile, SourceText, TEncoding.UTF8);

  Lines := TStringList.Create;
  try
    Args := TCommandLineArgs.Create;
    try
      Command := TCodecsCommand.Create;
      try
        Args.Parse(['codecs', 'generate', '--unit', InputFile, '--out', GeneratedUnit]);
        Command.Execute(Args);
        Should(TFile.Exists(GeneratedUnit)).BeTrue;
        Lines.LoadFromFile(GeneratedUnit, TEncoding.UTF8);
        Should(Lines.Text).Contain('if Obj.Age.HasValue then');
        Should(Lines.Text).Contain('Writer.WriteInt32(1, Obj.Age.Value);');
        Should(Lines.Text).Contain('Writer.WriteString(2, Obj.Name.Value);');
        Should(Lines.Text).Contain('if Obj.Tags[i].HasValue then');
        Should(Lines.Text).Contain('Writer.WriteInt32(3, Obj.Tags[i].Value);');
        Should(Lines.Text).Contain('if not Obj.History.HasValue then');
        Should(Lines.Text).Contain('Obj.History := TCollections.CreateList<Integer>(False);');
        Should(Lines.Text).Contain('Obj.History.Value.Add(Reader.ReadInt32);');
        Should(Lines.Text).Contain('Obj.Age := Reader.ReadInt32;');
        Should(Lines.Text).Contain('Obj.Tags.Add(Reader.ReadInt32);');
        Should(Lines.Text).Contain('Writer.WriteString(5, GUIDToString(Obj.MaybeGuid.Value));');
        Should(Lines.Text).Contain('Obj.MaybeGuid := StringToGUID(Reader.ReadString);');
        Should(Lines.Text).Contain('Writer.WriteString(6, Obj.MaybeUuid.Value.ToString);');
        Should(Lines.Text).Contain('Obj.MaybeUuid.Value := TUUID.FromString(Reader.ReadString);');
        Should(Lines.Text).Contain('Writer.WriteString(7, Obj.PropCodes[i].Value);');
        Should(Lines.Text).Contain('Obj.PropCodes.Add(Reader.ReadString);');
        Should(Lines.Text).Contain('Writer.WriteString(8, GUIDToString(Obj.OptionalIds[i].Value));');
        Should(Lines.Text).Contain('Obj.OptionalIds.Add(StringToGUID(Reader.ReadString));');
        Should(Lines.Text).Contain('if Assigned(Obj.OptionalChildren[i].Value) then Writer.WriteMessage(9, TProtobufSerializer.Serialize(Obj.OptionalChildren[i].Value, pcmGenerated));');
        Should(Lines.Text).Contain('Obj.OptionalChildren.Add(TCodecEdgeChild(ReadMessageObject(Reader, TCodecEdgeChild.Create)));');

        ProtoArgs := TCommandLineArgs.Create;
        try
          ProtoArgs.Parse(['codecs', 'export-proto', '--unit', InputFile, '--out', ProtoFile]);
          Command.Execute(ProtoArgs);
        finally
          ProtoArgs.Free;
        end;
        Should(TFile.Exists(ProtoFile)).BeTrue;
        ProtoText := TFile.ReadAllText(ProtoFile, TEncoding.UTF8);
        Should(ProtoText).Contain('repeated int32 Tags = 3;');
        Should(ProtoText).Contain('repeated int32 History = 4;');
        Should(ProtoText).Contain('string MaybeGuid = 5;');
        Should(ProtoText).Contain('string MaybeUuid = 6;');
        Should(ProtoText).Contain('repeated string PropCodes = 7;');
        Should(ProtoText).Contain('repeated string OptionalIds = 8;');
        Should(ProtoText).Contain('repeated CodecEdgeChild OptionalChildren = 9;');
      finally
        Command.Free;
      end;
    finally
      Args.Free;
    end;
  finally
    Lines.Free;
  end;
end;

procedure TCodecsCommandTests.ShouldRoundtripNestedJsonColumnThroughConverter;
var
  Converter: TJsonConverter;
  JsonValue: TValue;
  Root: TCodecNestedRoot;
  Target: TCodecNestedRoot;
  Deserialized: TValue;
begin
  Converter := TJsonConverter.Create(True);
  Root := TCodecNestedRoot.Create;
  Target := nil;
  try
    Root.Child.Name := 'Nested';
    Root.Items.Add(TCodecChild.Create);
    Root.Items[0].Name := 'Item1';

    JsonValue := Converter.ToDatabase(TValue.From<TObject>(Root), ddPostgreSQL);
    Should(JsonValue.IsEmpty).BeFalse;

    Deserialized := Converter.FromDatabase(JsonValue, TypeInfo(TCodecNestedRoot));
    Should(Deserialized.IsEmpty).BeFalse;

    Target := Deserialized.AsObject as TCodecNestedRoot;
    Should(Target <> nil).BeTrue;
    Should(Target.Child <> nil).BeTrue;
    Should(Target.Child.Name).Be('Nested');
    Should(Target.Items.Count).Be(1);
    Should(Target.Items[0].Name).Be('Item1');
  finally
    Target.Free;
    Root.Free;
    Converter.Free;
  end;
end;

procedure TCodecsCommandTests.ShouldGenerateCodecsForGuidAndUuidFields;
var
  TempDir: string;
  InputFile: string;
  GeneratedUnit: string;
  ProtoFile: string;
  SourceText: string;
  Args: TCommandLineArgs;
  Command: TCodecsCommand;
  Lines: TStringList;
  ProtoText: string;
begin
  TempDir := TPath.Combine(TPath.GetTempPath, 'DextS54UuidCodecs');
  if not TDirectory.Exists(TempDir) then
    TDirectory.CreateDirectory(TempDir);

  InputFile := TPath.Combine(TempDir, 'CodecInput.pas');
  GeneratedUnit := TPath.Combine(TempDir, 'CodecInput.DextCodecs.pas');
  ProtoFile := TPath.Combine(TempDir, 'CodecInput.proto');

  SourceText :=
    'unit CodecInput;' + sLineBreak + sLineBreak +
    'interface' + sLineBreak + sLineBreak +
    'uses Dext.Grpc.Attributes, Dext.Types.UUID;' + sLineBreak + sLineBreak +
    'type' + sLineBreak +
    '  [GrpcMessage]' + sLineBreak +
    '  TCodecUuidRoot = class' + sLineBreak +
    '  private' + sLineBreak +
    '    FGuidValue: TGUID;' + sLineBreak +
    '    FUuidValue: TUUID;' + sLineBreak +
    '  public' + sLineBreak +
    '    [ProtoMember(1)]' + sLineBreak +
    '    property GuidValue: TGUID read FGuidValue write FGuidValue;' + sLineBreak +
    '    [ProtoMember(2)]' + sLineBreak +
    '    property UuidValue: TUUID read FUuidValue write FUuidValue;' + sLineBreak +
    '  end;' + sLineBreak + sLineBreak +
    'implementation' + sLineBreak + sLineBreak +
    'end.';
  TFile.WriteAllText(InputFile, SourceText, TEncoding.UTF8);

  Lines := TStringList.Create;
  try
    Args := TCommandLineArgs.Create;
    try
      Command := TCodecsCommand.Create;
      try
        Args.Parse(['codecs', 'generate', '--unit', InputFile, '--out', GeneratedUnit]);
        Command.Execute(Args);
        Should(TFile.Exists(GeneratedUnit)).BeTrue;

        Lines.LoadFromFile(GeneratedUnit, TEncoding.UTF8);
        Should(Lines.Text).Contain('Dext.Types.UUID');
        Should(Lines.Text).Contain('GUIDToString(Obj.GuidValue)');
        Should(Lines.Text).Contain('Obj.UuidValue.ToString');
        Should(Lines.Text).Contain('StringToGUID(Reader.ReadString)');
        Should(Lines.Text).Contain('TUUID.FromString(Reader.ReadString)');
      finally
        Command.Free;
      end;
    finally
      Args.Free;
    end;

    Args := TCommandLineArgs.Create;
    try
      Command := TCodecsCommand.Create;
      try
        Args.Parse(['codecs', 'proto', '--unit', InputFile, '--out', ProtoFile]);
        Command.Execute(Args);
        Should(TFile.Exists(ProtoFile)).BeTrue;
        ProtoText := TFile.ReadAllText(ProtoFile, TEncoding.UTF8);
        Should(ProtoText).Contain('string GuidValue = 1;');
        Should(ProtoText).Contain('string UuidValue = 2;');
      finally
        Command.Free;
      end;
    finally
      Args.Free;
    end;
  finally
    Lines.Free;
  end;
end;

procedure TCodecsCommandTests.ShouldGenerateProtoAndStaticCodecsForNestedLists;
var
  TempDir: string;
  InputFile: string;
  GeneratedUnit: string;
  ProtoFile: string;
  SourceText: string;
  Args: TCommandLineArgs;
  Command: TCodecsCommand;
  Lines: TStringList;
  ProtoText: string;
begin
  TempDir := TPath.Combine(TPath.GetTempPath, 'DextS54Codecs');
  if not TDirectory.Exists(TempDir) then
    TDirectory.CreateDirectory(TempDir);

  InputFile := TPath.Combine(TempDir, 'CodecInput.pas');
  GeneratedUnit := TPath.Combine(TempDir, 'CodecInput.DextCodecs.pas');
  ProtoFile := TPath.Combine(TempDir, 'CodecInput.proto');

  SourceText :=
    'unit CodecInput;' + sLineBreak + sLineBreak +
    'interface' + sLineBreak + sLineBreak +
    'uses Dext.Collections, Dext.Grpc.Attributes;' + sLineBreak + sLineBreak +
    'type' + sLineBreak +
    '  [GrpcMessage]' + sLineBreak +
    '  TChild = class' + sLineBreak +
    '  private' + sLineBreak +
    '    FName: string;' + sLineBreak +
    '  public' + sLineBreak +
    '    [ProtoMember(1)]' + sLineBreak +
    '    property Name: string read FName write FName;' + sLineBreak +
    '  end;' + sLineBreak + sLineBreak +
    '  [GrpcMessage]' + sLineBreak +
    '  TRoot = class' + sLineBreak +
    '  private' + sLineBreak +
    '    FId: Integer;' + sLineBreak +
    '    FItems: IList<TChild>;' + sLineBreak +
    '  public' + sLineBreak +
    '    constructor Create;' + sLineBreak +
    '    [ProtoMember(1)]' + sLineBreak +
    '    property Id: Integer read FId write FId;' + sLineBreak +
    '    [ProtoMember(2)]' + sLineBreak +
    '    property Items: IList<TChild> read FItems write FItems;' + sLineBreak +
    '  end;' + sLineBreak + sLineBreak +
    'implementation' + sLineBreak + sLineBreak +
    'constructor TRoot.Create;' + sLineBreak +
    'begin' + sLineBreak +
    '  inherited Create;' + sLineBreak +
    '  FItems := TCollections.CreateList<TChild>(True);' + sLineBreak +
    'end;' + sLineBreak + sLineBreak +
    'initialization' + sLineBreak + sLineBreak +
    '  TActivator.RegisterDefault<IList<TCodecChild>, TList<TCodecChild>>;' + sLineBreak +
    '  TActivator.RegisterDefault<IList<Integer>, TList<Integer>>;' + sLineBreak + sLineBreak +
    'end.';

  TFile.WriteAllText(InputFile, SourceText, TEncoding.UTF8);

  Lines := TStringList.Create;
  try
    Args := TCommandLineArgs.Create;
    try
      Command := TCodecsCommand.Create;
      try
        Args.Parse(['codecs', 'generate', '--unit', InputFile, '--out', GeneratedUnit]);
        Command.Execute(Args);
        Should(TFile.Exists(GeneratedUnit)).BeTrue;
        Lines.LoadFromFile(GeneratedUnit, TEncoding.UTF8);
        Should(Lines.Text).Contain('TCollections.CreateList<TChild>(True)');
        Should(Lines.Text).Contain('for i := 0 to Obj.Items.Count - 1 do');
        Should(Lines.Text).Contain('Obj.Items.Add(TChild(ReadMessageObject(Reader, TChild.Create)));');
      finally
        Command.Free;
      end;
    finally
      Args.Free;
    end;

    Args := TCommandLineArgs.Create;
    try
      Command := TCodecsCommand.Create;
      try
        Args.Parse(['codecs', 'proto', '--unit', InputFile, '--out', ProtoFile]);
        Command.Execute(Args);
        Should(TFile.Exists(ProtoFile)).BeTrue;
        ProtoText := TFile.ReadAllText(ProtoFile, TEncoding.UTF8);
        Should(ProtoText).Contain('repeated Child Items = 2;');
      finally
        Command.Free;
      end;
    finally
      Args.Free;
    end;
  finally
    Lines.Free;
  end;
end;

initialization
  TActivator.RegisterDefault<IList<TCodecChild>, TList<TCodecChild>>;

end.


