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
unit Dext.Web.ModelBinding;

interface

uses
  System.Classes,
  System.Rtti,
  System.SysUtils,
  System.TypInfo,
  Dext.Collections,
  Dext.Collections.Dict,
  Dext.DI.Interfaces,
  Dext.Json,
  Dext.Json.Types,
  Dext.Types.UUID,
  Dext.Web.Interfaces,
  Dext.Utils;

type
  EBindingException = class(Exception);

  /// <summary>
  ///   Defines the source from where a model or parameter should be bound.
  /// </summary>
  TBindingSource = (
    bsBody,     // JSON body
    bsQuery,    // Query string
    bsRoute,    // Route parameters
    bsHeader,   // HTTP headers
    bsServices, // DI Container
    bsForm      // Form data (future)
  );

  /// <summary>
  ///   Base class for binding attributes.
  /// </summary>
  BindingAttribute = class abstract(TCustomAttribute)
  private
    FSource: TBindingSource;
  public
    constructor Create(ASource: TBindingSource);
    /// <summary>Data source (Body, Query, Route, Header, etc.).</summary>
    property Source: TBindingSource read FSource;
  end;

  /// <summary>Attribute to bind a parameter from the request body (JSON).</summary>
  FromBodyAttribute = class(BindingAttribute)
  public
    constructor Create; overload;
  end;

  /// <summary>Attribute to bind a parameter from the query string.</summary>
  FromQueryAttribute = class(BindingAttribute)
  private
    FName: string;
  public
    constructor Create; overload;
    constructor Create(const AName: string); overload;
    property Name: string read FName;
  end;

  /// <summary>Attribute to bind a parameter from route data ({id}).</summary>
  FromRouteAttribute = class(BindingAttribute)
  private
    FName: string;
  public
    constructor Create; overload;
    constructor Create(const AName: string); overload;
    property Name: string read FName;
  end;

  /// <summary>Attribute to bind a parameter from HTTP headers.</summary>
  FromHeaderAttribute = class(BindingAttribute)
  private
    FName: string;
  public
    constructor Create; overload;
    constructor Create(const AName: string); overload;
    property Name: string read FName;
  end;

  /// <summary>Attribute to inject a service directly from the DI container into the handler parameter.</summary>
  FromServicesAttribute = class(BindingAttribute)
  public
    constructor Create; overload;
  end;

  /// <summary>
  ///   Defines the contract for model binding.
  /// </summary>
  IModelBinder = interface
    ['{6CDDAA4C-EB6B-42F0-A138-614FFBA931A5}']
    /// <summary>Binds a model from the request body (JSON).</summary>
    function BindBody(AType: PTypeInfo; Context: IHttpContext): TValue;
    
    /// <summary>Binds a model from the query string.</summary>
    function BindQuery(AType: PTypeInfo; Context: IHttpContext): TValue;
    
    /// <summary>Binds a model from route parameters.</summary>
    function BindRoute(AType: PTypeInfo; Context: IHttpContext): TValue;
    
    /// <summary>Binds a model from HTTP headers.</summary>
    function BindHeader(AType: PTypeInfo; Context: IHttpContext): TValue;
    
    /// <summary>Injects a dependency from the service container.</summary>
    function BindServices(AType: PTypeInfo; Context: IHttpContext): TValue;

    /// <summary>Binds all parameters of a controller/handler method.</summary>
    procedure BindMethodParameters(AMethod: TRttiMethod; AContext: IHttpContext; var AValues: TArray<TValue>);
    
    /// <summary>Binds a single parameter, applying inference rules if necessary.</summary>
    function BindParameter(AParam: TRttiParameter; AContext: IHttpContext): TValue;

    /// <summary>
    ///   Performs hybrid binding of a Record. 
    ///   Fields can come from different sources based on meta-informative attributes.
    /// </summary>
    function BindRecordHybrid(AType: PTypeInfo; Context: IHttpContext): TValue;

    /// <summary>Converts a raw string value to the specified native type via RTTI.</summary>
    function BindValue(const AValue: string; AType: PTypeInfo): TValue;
  end;

  /// <summary>
  ///   Dext Model Binding mechanism.
  ///   Converts data from various HTTP sources to native Delphi types using RTTI.
  /// </summary>
  TModelBinder = class(TInterfacedObject, IModelBinder)
  private
    class var FDefault: IModelBinder;
    function BindBodyPrimitive(AParam: TRttiParameter; Context: IHttpContext): TValue;
  public
    class constructor Create;
    class destructor Destroy;
    constructor Create;
    destructor Destroy; override;
    /// <summary>Returns the immutable stateless binder shared by execution plans.</summary>
    class function Default: IModelBinder; static;

    // Interface methods
    function BindBody(AType: PTypeInfo; Context: IHttpContext): TValue; overload;
    function BindQuery(AType: PTypeInfo; Context: IHttpContext): TValue; overload;
    function BindRoute(AType: PTypeInfo; Context: IHttpContext): TValue; overload;
    function BindHeader(AType: PTypeInfo; Context: IHttpContext): TValue;
    function BindServices(AType: PTypeInfo; Context: IHttpContext): TValue;

    // Helper methods with generics
    /// <summary>Binds and deserializes the request body to type T.</summary>
    function BindBody<T>(Context: IHttpContext): T; overload;
    /// <summary>Binds the query string to type T (record or class).</summary>
    function BindQuery<T>(Context: IHttpContext): T; overload;
    /// <summary>Binds route parameters to type T.</summary>
    function BindRoute<T>(Context: IHttpContext): T; overload;

    procedure BindMethodParameters(AMethod: TRttiMethod; AContext: IHttpContext; var AValues: TArray<TValue>);
    function BindParameter(AParam: TRttiParameter; AContext: IHttpContext): TValue;

    /// <summary>
    ///   Performs hybrid binding: record properties can come from different sources 
    ///   based on attributes (Header, Query, Route, Body).
    /// </summary>
    function BindRecordHybrid(AType: PTypeInfo; Context: IHttpContext): TValue;

    function BindValue(const AValue: string; AType: PTypeInfo): TValue;
  end;

  TModelBinderHelper = class
  public
    class function BindQuery<T>(ABinder: IModelBinder; Context: IHttpContext): T; static;
    class function BindBody<T>(ABinder: IModelBinder; Context: IHttpContext): T; static;
    class function BindRoute<T>(ABinder: IModelBinder; Context: IHttpContext): T; static;
  end;

  // BINDING PROVIDER
  IBindingSourceProvider = interface
    ['{8D4F3A7C-1E4A-4B8D-B0E7-9F3A8C5D2B1E}']
    function GetBindingSource(Param: TRttiParameter): TBindingSource;
    function GetBindingName(Param: TRttiParameter): string;
  end;

  TBindingSourceProvider = class(TInterfacedObject, IBindingSourceProvider)
  public
    function GetBindingSource(Field: TRttiField): TBindingSource; overload;
    function GetBindingName(Field: TRttiField): string; overload;

    function GetBindingSource(Param: TRttiParameter): TBindingSource; overload;
    function GetBindingName(Param: TRttiParameter): string; overload;
  end;


implementation

uses
  System.NetEncoding,
  System.Variants,
  Dext.Core.DateUtils,
  Dext.Core.Span,
  Dext.Entity.Attributes,
  Dext.Json.Utf8.Serializer,
  Dext.Core.Activator,
  Dext.Core.Reflection,
  Dext.Codecs.Registry;

function SameAsciiTextAt(const AValue, AText: string; AStart: Integer): Boolean;
var
  i: Integer;
  C1: Char;
  C2: Char;
begin
  if (AStart < 1) or (AStart + Length(AText) - 1 > Length(AValue)) then
    Exit(False);

  for i := 1 to Length(AText) do
  begin
    C1 := AValue[AStart + i - 1];
    C2 := AText[i];
    if (C1 >= 'A') and (C1 <= 'Z') then
      C1 := Chr(Ord(C1) + 32);
    if (C2 >= 'A') and (C2 <= 'Z') then
      C2 := Chr(Ord(C2) + 32);
    if C1 <> C2 then
      Exit(False);
  end;
  Result := True;
end;

function ContainsAsciiText(const AValue, AText: string): Boolean;
var
  i: Integer;
begin
  if AText = '' then
    Exit(True);
  if Length(AValue) < Length(AText) then
    Exit(False);

  for i := 1 to Length(AValue) - Length(AText) + 1 do
    if SameAsciiTextAt(AValue, AText, i) then
      Exit(True);
  Result := False;
end;

{ BindingAttribute }

constructor BindingAttribute.Create(ASource: TBindingSource);
begin
  inherited Create;
  FSource := ASource;
end;

{ FromBodyAttribute }

constructor FromBodyAttribute.Create;
begin
  inherited Create(bsBody);
end;

{ FromQueryAttribute }

constructor FromQueryAttribute.Create;
begin
  inherited Create(bsQuery);
end;

constructor FromQueryAttribute.Create(const AName: string);
begin
  inherited Create(bsQuery);
  FName := AName;
end;

{ FromRouteAttribute }

constructor FromRouteAttribute.Create;
begin
  inherited Create(bsRoute);
end;

constructor FromRouteAttribute.Create(const AName: string);
begin
  inherited Create(bsRoute);
  FName := AName;
end;

{ FromHeaderAttribute }

constructor FromHeaderAttribute.Create;
begin
  inherited Create(bsHeader);
end;

constructor FromHeaderAttribute.Create(const AName: string);
begin
  inherited Create(bsHeader);
  FName := AName;
end;

{ FromServicesAttribute }

constructor FromServicesAttribute.Create;
begin
  inherited Create(bsServices);
end;

{ TModelBinder }

class constructor TModelBinder.Create;
begin
  FDefault := TModelBinder.Create;
end;

class destructor TModelBinder.Destroy;
begin
  FDefault := nil;
end;

constructor TModelBinder.Create;
begin
  inherited Create;
end;

class function TModelBinder.Default: IModelBinder;
begin
  Result := FDefault;
end;

destructor TModelBinder.Destroy;
begin

  inherited;
end;

function TModelBinder.BindBodyPrimitive(AParam: TRttiParameter; Context: IHttpContext): TValue;
var
  Stream: TStream;
  Bytes: TBytes;
  BodyLen: Integer;
  BodyJsonStr: string;
  JsonNode: IDextJsonNode;
  JsonObj: IDextJsonObject;
  NodeVal: IDextJsonNode;
begin
  Stream := Context.Request.Body;
  if (Stream = nil) or (Stream.Size = 0) then
    Exit(TReflection.GetDefaultValue(nil, AParam.ParamType.Handle));

  BodyLen := Integer(Stream.Size);
  Stream.Position := 0;
  if Stream is TBytesStream then
    Bytes := TBytesStream(Stream).Bytes
  else
  begin
    SetLength(Bytes, BodyLen);
    if BodyLen > 0 then
      Stream.ReadBuffer(Bytes[0], BodyLen);
  end;
  BodyJsonStr := TEncoding.UTF8.GetString(Bytes, 0, BodyLen);

  if BodyJsonStr <> '' then
  begin
    try
      JsonNode := TDextJson.Provider.Parse(BodyJsonStr);
      if (JsonNode <> nil) then
      begin
        if (JsonNode.GetNodeType = jntObject) then
        begin
          JsonObj := JsonNode as IDextJsonObject;
          if JsonObj.Contains(AParam.Name) then
          begin
            NodeVal := JsonObj.GetNode(AParam.Name);
            if (NodeVal <> nil) and not NodeVal.IsNull then
            begin
              if AParam.ParamType.Handle.Kind = tkDynArray then
              begin
                Result := TDextJson.Deserialize(AParam.ParamType.Handle, NodeVal.ToJson());
              end
              else
              begin
                case NodeVal.GetNodeType of
                  jntString: Result := TReflection.CastFromString(NodeVal.AsString, AParam.ParamType.Handle);
                  jntNumber: Result := TReflection.CastFromString(NodeVal.AsString, AParam.ParamType.Handle);
                  jntBoolean: Result := TValue.From<Boolean>(NodeVal.AsBoolean);
                  jntNull: Result := TReflection.GetDefaultValue(AParam, AParam.ParamType.Handle);
                else
                  Result := TReflection.CastFromString(NodeVal.AsString, AParam.ParamType.Handle);
                end;
              end;
            end
            else
              Result := TReflection.GetDefaultValue(AParam, AParam.ParamType.Handle);
          end
          else
            Result := TReflection.GetDefaultValue(AParam, AParam.ParamType.Handle);
          Exit;
        end;

        case JsonNode.GetNodeType of
          jntString: Result := TReflection.CastFromString(JsonNode.AsString, AParam.ParamType.Handle);
          jntNumber: Result := TReflection.CastFromString(JsonNode.AsString, AParam.ParamType.Handle);
          jntBoolean: Result := TValue.From<Boolean>(JsonNode.AsBoolean);
          jntNull: Result := TReflection.GetDefaultValue(nil, AParam.ParamType.Handle);
        else
          if AParam.ParamType.Handle.Kind = tkDynArray then
            Result := TDextJson.Deserialize(AParam.ParamType.Handle, BodyJsonStr)
          else if (Length(BodyJsonStr) >= 2) and (BodyJsonStr[1] = '"') and (BodyJsonStr[Length(BodyJsonStr)] = '"') then
            Result := TReflection.CastFromString(Copy(BodyJsonStr, 2, Length(BodyJsonStr) - 2), AParam.ParamType.Handle)
          else
            Result := TReflection.CastFromString(BodyJsonStr, AParam.ParamType.Handle);
        end;
      end
      else
        Result := TReflection.GetDefaultValue(nil, AParam.ParamType.Handle);
    except
      on E: Exception do
      begin
        if AParam.ParamType.Handle.Kind = tkDynArray then
          raise EBindingException.CreateFmt('Error binding parameter "%s": %s', [AParam.Name, E.Message])
        else if (Length(BodyJsonStr) >= 2) and (BodyJsonStr[1] = '"') and (BodyJsonStr[Length(BodyJsonStr)] = '"') then
          Result := TReflection.CastFromString(Copy(BodyJsonStr, 2, Length(BodyJsonStr) - 2), AParam.ParamType.Handle)
        else
          Result := TReflection.CastFromString(BodyJsonStr, AParam.ParamType.Handle);
      end;
    end;
  end
  else
    Result := TReflection.GetDefaultValue(nil, AParam.ParamType.Handle);
end;

function TModelBinder.BindBody(AType: PTypeInfo; Context: IHttpContext): TValue;
var
  Stream: TStream;
  JsonString: string;
  Settings: TJsonSettings;
  Bytes: TBytes;
  Span: TByteSpan;
  BodyLen: Integer;
begin
  if (AType.Kind <> tkRecord) and (AType.Kind <> tkClass) then
    raise EBindingException.Create('BindBody currently only supports records and classes');

  Stream := Context.Request.Body;
  if (Stream = nil) or (Stream.Size = 0) then
  begin
     // For Classes, might be valid to return nil, but generally body is expected.
     raise EBindingException.Create('Request body is empty');
  end;

  // OPTIMIZATION: Check if we can use Zero-Allocation UTF8 Serializer
  // Currently we just read bytes to avoid String conversion. 
  // In future we can get Span directly from Request if driver supports it.
  
  try
    // Read Body as Bytes (One copy stream -> bytes, but avoids bytes -> string -> TJsonDOM)
    BodyLen := Integer(Stream.Size);
    if Stream is TBytesStream then
      Bytes := TBytesStream(Stream).Bytes
    else
    begin
      Stream.Position := 0;
      SetLength(Bytes, BodyLen);
      if BodyLen > 0 then
        Stream.ReadBuffer(Bytes[0], BodyLen);
    end;
    
    if BodyLen = 0 then
         raise EBindingException.Create('Request body is empty');

    Span := TByteSpan.Create(@Bytes[0], BodyLen);

    // Call Generic Deserialize<T> dynamically? 
    // TUtf8JsonSerializer.Deserialize<T> is static generic.
    // We have AType (PTypeInfo).
    // The current signature of BindBody returns TValue.
    // We need to invoke Deserialize via RTTI or use the non-generic version if we expose one.
    // However, TUtf8JsonSerializer currently exposes `Deserialize<T>`.
    // Let's use RTTI to invoke it for now, or just fallback to String for this specific non-generic call 
    // IF we are not called via generic BindBody<T>. 
    // BUT BindBody<T> calls this BindBody(PTypeInfo).
    
    // To truly use the new serializer efficiently without heavy generic invoking:
    // We should refactor BindBody<T> to call the serializer directly.
    // But for now, let's keep the architecture:
    
    // We'll read as string for THIS method (legacy path) unless we refactor BindBody<T>.
    // Wait, the user wants "Zero-Allocation". 
    // Reading stream to Bytes is fine.
    
    // Let's modify BindBody<T> below to use the new serializer, and keep this for compat/dynamic calls.
    // OR we change this method to try to dispatch to Utf8Serializer if possible.
    
    // Fallback to legacy string based for now in the non-generic untyped method
    JsonString := TEncoding.UTF8.GetString(Bytes, 0, BodyLen);
    Settings := TJsonSettings.Default.CaseInsensitive.ServiceProvider(Context.Services);
    
    Result := TDextJson.Deserialize(AType, JsonString, Settings);
  except
    on E: Exception do
      raise EBindingException.Create('Error binding body: ' + E.Message);
  end;
end;

// Optimized Generic Version
function TModelBinder.BindBody<T>(Context: IHttpContext): T;
var
  Stream: TStream;
  Bytes: TBytes;
  Span: TByteSpan;
  Value: TValue;
  BodyLen: Integer;
  WriteProc: TDextJsonWriteProc;
  ReadProc: TDextJsonReadProc;
  Instance: TObject;
begin
  // Check direct generated JSON codec registry first
  if TDextCodecRegistry.TryGetJson(TypeInfo(T), WriteProc, ReadProc) and
     Assigned(ReadProc) then
  begin
    Stream := Context.Request.Body;
    if (Stream = nil) or (Stream.Size = 0) then
      raise EBindingException.Create('Request body is empty');

    BodyLen := Integer(Stream.Size);
    if Stream is TBytesStream then
    begin
       Bytes := TBytesStream(Stream).Bytes;
    end
    else
    begin
      Stream.Position := 0;
      SetLength(Bytes, BodyLen);
      if BodyLen > 0 then
        Stream.ReadBuffer(Bytes[0], BodyLen);
    end;

    Span := TByteSpan.Create(@Bytes[0], BodyLen);
    
    if PTypeInfo(System.TypeInfo(T)).Kind = tkClass then
    begin
      Instance := TActivator.CreateInstance(nil,
        GetTypeData(System.TypeInfo(T)).ClassType);
      try
        ReadProc(Span, Instance);
        PPointer(@Result)^ := Instance;
        Exit;
      except
        on E: Exception do
        begin
          Instance.Free;
          raise EBindingException.Create('Error parsing JSON body: ' +
            E.Message);
        end;
      end;
    end;
  end;

  // Only for Records for now
  if PTypeInfo(System.TypeInfo(T)).Kind = tkRecord then
  begin
      Stream := Context.Request.Body;
      if (Stream = nil) or (Stream.Size = 0) then
        raise EBindingException.Create('Request body is empty');

      // Read RAW BYTES (Zero String Allocation)
      // Ideally Context.Request would expose a Span/Bytes directly.
      BodyLen := Integer(Stream.Size);
      if Stream is TBytesStream then
      begin
         Bytes := TBytesStream(Stream).Bytes;
         // Note: TBytesStream.Bytes returns the internal array usually - Zero copy? 
         // System.Classes TBytesStream properties expose raw TBytes. Good.
      end
      else
      begin
        Stream.Position := 0;
        SetLength(Bytes, BodyLen);
        if BodyLen > 0 then
          Stream.ReadBuffer(Bytes[0], BodyLen);
      end;
      
      try
        Span := TByteSpan.Create(@Bytes[0], BodyLen);
        // FAST PATH: UTF8 Zero-Allocation Deserialization
        Result := TUtf8JsonSerializer.Deserialize<T>(Span);
        Exit;
      except
        // Fallback or re-raise
        on E: EUtf8SerializationException do
           raise EBindingException.Create('Error parsing JSON body: ' + E.Message);
      end;
  end;

  // Fallback for Classes/Other types (Legacy)
  Value := BindBody(TypeInfo(T), Context);
  Result := Value.AsType<T>;
end;

function TModelBinder.BindQuery(AType: PTypeInfo; Context: IHttpContext): TValue;
var
  RttiType: TRttiType;
  QueryParams: IStringDictionary;
  FieldName: string;
  FieldValue: string;
  Field: TRttiField;
  Prop: TRttiProperty;
  Attr: TCustomAttribute;
  M: TRttiMethod;
  MetaClass: TClass;
  FoundCreate: Boolean;
  SourceProvider: TBindingSourceProvider;
begin
  if (AType.Kind <> tkRecord) and (AType.Kind <> tkClass) then
    raise EBindingException.Create('BindQuery currently only supports records and classes');

  RttiType := TReflection.Context.GetType(AType);
  QueryParams := Context.Request.Query;

  // 1. Initialize Result
  if AType.Kind = tkClass then
  begin
    MetaClass := (RttiType as TRttiInstanceType).MetaclassType;
    FoundCreate := False;
    
    // Robustly searching for parameterless constructor
    for M in RttiType.GetMethods do
    begin
      if (SameText(M.Name, 'Create')) and (M.MethodKind = mkConstructor) and (Length(M.GetParameters) = 0) then
      begin
        Result := M.Invoke(MetaClass, []);
        FoundCreate := True;
        Break;
      end;
    end;
    
    if not FoundCreate then
      raise EBindingException.CreateFmt('Cannot find parameterless constructor "Create" for %s in BindQuery.', [AType.Name]);
  end
  else
  begin
    TValue.Make(nil, AType, Result);
  end;

  // 2. Bind Fields (Records)
  if AType.Kind = tkRecord then
  begin
    SourceProvider := TBindingSourceProvider.Create;
    try
      for Field in RttiType.GetFields do
      begin
        FieldName := SourceProvider.GetBindingName(Field);

        if QueryParams.TryGetValue(FieldName, FieldValue) then
          Field.SetValue(Result.GetReferenceToRawData, TReflection.CastFromString(FieldValue, Field.FieldType.Handle))
        else
          Field.SetValue(Result.GetReferenceToRawData, TReflection.GetDefaultValue(Field, Field.FieldType.Handle));
      end;
    finally
      SourceProvider.Free;
    end;
  end
  // 3. Bind Properties (Classes)
  else if AType.Kind = tkClass then
  begin
    for Prop in RttiType.GetProperties do
    begin
      if not Prop.IsWritable then Continue;
      
      FieldName := Prop.Name;
      for Attr in Prop.GetAttributes do
      begin
        if Attr is FromQueryAttribute then
        begin
          if FromQueryAttribute(Attr).Name <> '' then FieldName := FromQueryAttribute(Attr).Name;
        end;
      end;

      if QueryParams.TryGetValue(FieldName, FieldValue) then
        Prop.SetValue(Result.AsObject, TReflection.CastFromString(FieldValue, Prop.PropertyType.Handle))
      else
        Prop.SetValue(Result.AsObject, TReflection.GetDefaultValue(Prop, Prop.PropertyType.Handle));
    end;
  end;
end;

function TModelBinder.BindQuery<T>(Context: IHttpContext): T;
var
  Value: TValue;
begin
  Value := BindQuery(TypeInfo(T), Context);
  Result := Value.AsType<T>;
end;

function TModelBinder.BindRoute(AType: PTypeInfo; Context: IHttpContext): TValue;
var
  RttiType: TRttiType;
  RouteParams: TRouteValueDictionary;
  Field: TRttiField;
  FieldName: string;
  FieldValue: string;
  SingleParamValue: string;
  IntValue: Int64;
  SourceProvider: TBindingSourceProvider;
begin
  // ✅ SUPPORT FOR PRIMITIVES (Single Route Param Inference)
  if (AType.Kind in [tkInteger, tkInt64, tkFloat, tkString, tkLString, tkWString, tkUString, tkEnumeration]) or
     ((AType.Kind = tkRecord) and ((AType = TypeInfo(TGUID)) or (AType = TypeInfo(TUUID)))) then
  begin
    RouteParams := Context.Request.RouteParams;
    
    if RouteParams.Count = 1 then
    begin
      SingleParamValue := RouteParams.GetValueByIndex(0);
      
      // CastFromString turns a value that is not a number into 0: the handler
      // would then run with 0 for /items/abc. A route segment that does not
      // convert is a binding failure.
      if (AType.Kind in [tkInteger, tkInt64]) and (SingleParamValue <> '') and
        not TryStrToInt64(TNetEncoding.URL.Decode(SingleParamValue), IntValue) then
        raise EBindingException.CreateFmt('Error converting route param "%s" to %s: not an integer',
          [SingleParamValue, AType.Name]);

      try
        Result := TReflection.CastFromString(SingleParamValue, AType);
        Exit;
      except
        on E: Exception do
          raise EBindingException.CreateFmt('Error converting route param "%s" to %s: %s', [SingleParamValue, AType.Name, E.Message]);
      end;
    end
    else if RouteParams.Count > 1 then
      raise EBindingException.CreateFmt('Ambiguous binding for type %s. Found %d route parameters. Use a Record.', [AType.Name, RouteParams.Count]);
  end;

  if AType.Kind <> tkRecord then
    raise EBindingException.Create('BindRoute currently only supports records or single primitive inference');

  TValue.Make(nil, AType, Result);

  RttiType := TReflection.Context.GetType(AType);
  RouteParams := Context.Request.RouteParams;

  SourceProvider := TBindingSourceProvider.Create;
  try
    for Field in RttiType.GetFields do
    begin
      // Obter nome do campo (com suporte a atributos [FromRoute])
      FieldName := SourceProvider.GetBindingName(Field);

      // Buscar valor do route parameter
      if RouteParams.TryGetValue(FieldName, FieldValue) then
        Field.SetValue(Result.GetReferenceToRawData, TReflection.CastFromString(FieldValue, Field.FieldType.Handle))
      else
        Field.SetValue(Result.GetReferenceToRawData, TReflection.GetDefaultValue(Field, Field.FieldType.Handle));
    end; // for each field
  finally
    SourceProvider.Free;
  end;
end;

function TModelBinder.BindRoute<T>(Context: IHttpContext): T;
var
  Value: TValue;
begin
  Value := BindRoute(TypeInfo(T), Context);
  Result := Value.AsType<T>;
end;

function TModelBinder.BindHeader(AType: PTypeInfo; Context: IHttpContext): TValue;
var
  RttiType: TRttiType;
  Headers: IStringDictionary;
  Field: TRttiField;
  FieldName: string;
  FieldValue: string;
  Val: TValue;
  SourceProvider: TBindingSourceProvider;
begin
  if AType.Kind <> tkRecord then
    raise EBindingException.Create('BindHeader currently only supports records');

  TValue.Make(nil, AType, Result);

  RttiType := TReflection.Context.GetType(AType);
  Headers := Context.Request.Headers;

  SourceProvider := TBindingSourceProvider.Create;
  try
    for Field in RttiType.GetFields do
    begin
      // Obter nome do campo (com suporte a atributos [FromHeader])
      FieldName := SourceProvider.GetBindingName(Field);

      // Get header value (case-insensitive via GetHeader)
      FieldValue := Context.Request.GetHeader(FieldName);
      if FieldValue <> '' then
      begin
        // USE ROBUST CONVERSION
        try
          Val := TReflection.CastFromString(FieldValue, Field.FieldType.Handle);
          Field.SetValue(Result.GetReferenceToRawData, Val);
        except
          on E: Exception do
          begin
            SafeWriteln(Format('⚠️ BindHeader warning: Error converting field "%s" value "%s": %s',
              [FieldName, FieldValue, E.Message]));
          end;
        end; // try
      end; // if header exists
    end; // for each field
  finally
    SourceProvider.Free;
  end;
end;

procedure TModelBinder.BindMethodParameters(AMethod: TRttiMethod;
  AContext: IHttpContext; var AValues: TArray<TValue>);
var
  I: Integer;
  Params: TArray<TRttiParameter>;
begin
  Params := AMethod.GetParameters;
  if Length(AValues) <> Length(Params) then
    SetLength(AValues, Length(Params));

  for I := 0 to High(Params) do
    AValues[I] := BindParameter(Params[I], AContext);
end;

function TModelBinder.BindParameter(AParam: TRttiParameter;
  AContext: IHttpContext): TValue;
var
  Attr: TCustomAttribute;
  A: TCustomAttribute;
  ParamName: string;
  QueryParams: IStringDictionary;
  QueryValue: string;
  RouteParams: TRouteValueDictionary;
  RouteValue: string;
  HeaderValue: string;
  FoundDefault: Boolean;
  IsService: Boolean;
begin
  // 1. IHttpContext
  if AParam.ParamType.Handle = TypeInfo(IHttpContext) then
  begin
    Result := TValue.From<IHttpContext>(AContext);
    Exit;
  end;

  // 2. Explicit Attributes
  for Attr in AParam.GetAttributes do
  begin
    if Attr is FromQueryAttribute then
    begin
      ParamName := FromQueryAttribute(Attr).Name;
      if ParamName = '' then ParamName := AParam.Name;

      QueryParams := AContext.Request.Query;
      if QueryParams.TryGetValue(ParamName, QueryValue) then
        Result := TReflection.CastFromString(QueryValue, AParam.ParamType.Handle)
      else
      begin
        // 1. Try DefaultValueAttribute
        FoundDefault := False;
        for A in AParam.GetAttributes do
          if A is DefaultValueAttribute then
          begin
             Result := TValue.FromVariant(DefaultValueAttribute(A).Value);
             FoundDefault := True;
             Break;
          end;
        
        // 2. Fallback to standard conversion
        if not FoundDefault then
          Result := TReflection.CastFromString('', AParam.ParamType.Handle);
      end;
      Exit;
    end
    else if Attr is FromRouteAttribute then
    begin
      ParamName := FromRouteAttribute(Attr).Name;
      if ParamName = '' then ParamName := AParam.Name;

      RouteParams := AContext.Request.RouteParams;
      if RouteParams.TryGetValue(ParamName, RouteValue) then
        Result := TReflection.CastFromString(RouteValue, AParam.ParamType.Handle)
      else
        raise EBindingException.CreateFmt('Route parameter not found: %s', [ParamName]);
      Exit;
    end
    else if Attr is FromBodyAttribute then
    begin
      if (AParam.ParamType.Handle.Kind <> tkRecord) and (AParam.ParamType.Handle.Kind <> tkClass) then
        Result := BindBodyPrimitive(AParam, AContext)
      else
        Result := BindBody(AParam.ParamType.Handle, AContext);
      Exit;
    end
    else if Attr is FromServicesAttribute then
    begin
      Result := BindServices(AParam.ParamType.Handle, AContext);
      Exit;
    end
    else if Attr is FromHeaderAttribute then
    begin
      ParamName := FromHeaderAttribute(Attr).Name;
      if ParamName = '' then ParamName := AParam.Name;

      HeaderValue := AContext.Request.GetHeader(ParamName);
      if HeaderValue <> '' then
        Result := TReflection.CastFromString(HeaderValue, AParam.ParamType.Handle)
      else
      begin
        FoundDefault := False;
        for A in AParam.GetAttributes do
          if A is DefaultValueAttribute then
          begin
             Result := TValue.FromVariant(DefaultValueAttribute(A).Value);
             FoundDefault := True;
             Break;
          end;
        if not FoundDefault then
          Result := TReflection.CastFromString('', AParam.ParamType.Handle);
      end;
      Exit;
    end;
  end;

  // 3. Inference
  if (AParam.ParamType.TypeKind = tkRecord) then
  begin
    // Use hybrid binding for records - supports Header, Query, Route, Body
    Result := BindRecordHybrid(AParam.ParamType.Handle, AContext);
  end
  else if (AParam.ParamType.TypeKind = tkClass) then
  begin
     // 1. Try Service Injection First
     IsService := False;
     try
       Result := BindServices(AParam.ParamType.Handle, AContext);
       if not Result.IsEmpty and not Result.AsObject.Equals(nil) then
         IsService := True;
     except
       // Service resolution failed, continue to Model Binding
     end;

     if IsService then Exit;

     // 2. Model Binding (Body vs Query)
     if (AContext.Request.Method = 'POST') or (AContext.Request.Method = 'PUT') or (AContext.Request.Method = 'PATCH') then
         Result := BindBody(AParam.ParamType.Handle, AContext)
     else
         Result := BindQuery(AParam.ParamType.Handle, AContext);
  end
  else if (AParam.ParamType.TypeKind = tkInterface) then
  begin
    if AParam.ParamType.Handle = TypeInfo(IHttpContext) then
      Result := TValue.From<IHttpContext>(AContext)
    else
      Result := BindServices(AParam.ParamType.Handle, AContext);
  end
  else
  begin
    // Primitives: Route -> Query
    ParamName := AParam.Name;
    RouteParams := AContext.Request.RouteParams;
    
    if RouteParams.TryGetValue(ParamName, RouteValue) then
    begin
      Result := TReflection.CastFromString(RouteValue, AParam.ParamType.Handle);
    end
    else
    begin
      QueryParams := AContext.Request.Query;
      if QueryParams.TryGetValue(ParamName, QueryValue) then
        Result := TReflection.CastFromString(QueryValue, AParam.ParamType.Handle)
      else
      begin
        FoundDefault := False;
        for A in AParam.GetAttributes do
          if A is DefaultValueAttribute then
          begin
             Result := TValue.FromVariant(DefaultValueAttribute(A).Value);
             FoundDefault := True;
             Break;
          end;
        if not FoundDefault then
          Result := TReflection.CastFromString('', AParam.ParamType.Handle);
      end;
    end;
  end;
end;

function TModelBinder.BindServices(AType: PTypeInfo; Context: IHttpContext): TValue;
var
  RttiType: TRttiType;
  Services: IServiceProvider;
  Field: TRttiField;
  ServiceInstance: TValue;
  ServiceType: TServiceType;
  Attr: TCustomAttribute;
  HasServicesAttr: Boolean;
  InterfaceInstance: IInterface;
  ClassType: TClass;
  ClassInstance: TObject;
  InterfaceType: TRttiInterfaceType;
begin
  if (AType.Kind <> tkRecord) and (AType.Kind <> tkInterface) and (AType.Kind <> tkClass) then
    raise EBindingException.Create('BindServices currently only supports records, classes or interfaces');

  RttiType := TReflection.Context.GetType(AType);
  Services := Context.GetServices;
  
  // Class Support (Root Level)
  if AType.Kind = tkClass then
  begin
     ClassType := (RttiType as TRttiInstanceType).MetaclassType;
     ServiceType := TServiceType.FromClass(ClassType);
     ClassInstance := Services.GetService(ServiceType);
     
     if Assigned(ClassInstance) then
     begin
       Result := TValue.From(ClassInstance);
       Exit;
     end
     else
        raise EBindingException.CreateFmt('Service not found for class type: %s. Ensure it is registered in DI.', [String(AType.Name)]);
  end;

  // NEW: Direct support for interfaces
  if AType.Kind = tkInterface then
  begin
    InterfaceType := RttiType as TRttiInterfaceType;
    ServiceType := TServiceType.FromInterface(InterfaceType.GUID);
    InterfaceInstance := Services.GetServiceAsInterface(ServiceType);
    
    if Assigned(InterfaceInstance) then
    begin
      TValue.Make(@InterfaceInstance, AType, Result);
      Exit;
    end
    else
      raise EBindingException.CreateFmt('Service not found for interface: %s', [InterfaceType.Name]);
  end;

    TValue.Make(nil, AType, Result);
    // Services already initialized above

    for Field in RttiType.GetFields do
    begin
      // Check if field has [FromServices] attribute
      HasServicesAttr := False;
      for Attr in Field.GetAttributes do
      begin
        if Attr is FromServicesAttribute then
        begin
          HasServicesAttr := True;
          Break;
        end;
      end;

      if HasServicesAttr then
      begin
        try
          case Field.FieldType.TypeKind of
            tkInterface:
              begin
                // For interfaces, use GUID
                InterfaceType := Field.FieldType as TRttiInterfaceType;
                ServiceType := TServiceType.FromInterface(InterfaceType.GUID);

                // Get service from DI container as interface
                InterfaceInstance := Services.GetServiceAsInterface(ServiceType);
                if Assigned(InterfaceInstance) then
                begin
                  // FIX: Create TValue of specific interface type
                  TValue.Make(@InterfaceInstance, Field.FieldType.Handle, ServiceInstance);
                  Field.SetValue(Result.GetReferenceToRawData, ServiceInstance);
                end
                else
                begin
                  // Service not found - could it be optional or required?
                  // For now, leave field as nil
                end;
              end;

            tkClass:
              begin
                // FIX: Use RTTI to get class correctly
                ClassType := (Field.FieldType as TRttiInstanceType).MetaclassType;
                ServiceType := TServiceType.FromClass(ClassType);

                ClassInstance := Services.GetService(ServiceType);
                if Assigned(ClassInstance) then
                begin
                  ServiceInstance := TValue.From(ClassInstance);
                  Field.SetValue(Result.GetReferenceToRawData, ServiceInstance);
                end;
              end;
          else
            raise EBindingException.CreateFmt(
              'FromServices attribute not supported for field type: %s',
              [Field.FieldType.Name]);
          end;
        except
          on E: Exception do
            raise EBindingException.CreateFmt(
              'Error binding service for field %s: %s',
              [Field.Name, E.Message]);
        end;
      end;
    end;
end;

// Strict conversions for BindRecordHybrid.
//
// TReflection.CastFromString never fails: a value that does not convert
// becomes the default (0, an empty GUID, the first member of an enum), and
// the handler then runs with it. The functions below raise EBindingException,
// naming the field, so the client gets a 400 instead.

function FieldError(const AField, AValue, AReason: string): EBindingException;
var
  Shown: string;
begin
  // The value goes back to the client in the problem details: keep it short.
  Shown := AValue;
  if Length(Shown) > 64 then
    Shown := Copy(Shown, 1, 64) + '...';
  Result := EBindingException.CreateFmt('Field "%s": cannot convert "%s": %s',
    [AField, Shown, AReason]);
end;

function StrictInteger(const AText: string; AType: PTypeInfo; const AField: string): TValue;
var
  S: string;
  V: Int64;
  U: UInt64;
  Data: PTypeData;
begin
  S := AText.Trim;
  Data := GetTypeData(AType);
  if (AType.Kind = tkInt64) and (Data.MinInt64Value > Data.MaxInt64Value) then
  begin
    // UInt64: MinInt64Value = 0 and MaxInt64Value = -1
    if not TryStrToUInt64(S, U) then
      raise FieldError(AField, AText, 'not an unsigned integer');
    TValue.Make(@U, AType, Result);
    Exit;
  end;

  if not TryStrToInt64(S, V) then
    raise FieldError(AField, AText, 'not an integer');

  if AType.Kind = tkInteger then
  begin
    if Data.OrdType = otULong then
    begin
      if (V < 0) or (V > High(Cardinal)) then
        raise FieldError(AField, AText, 'out of range for ' + GetTypeName(AType));
    end
    else if (V < Data.MinValue) or (V > Data.MaxValue) then
      raise FieldError(AField, AText, 'out of range for ' + GetTypeName(AType));
  end
  else if (V < Data.MinInt64Value) or (V > Data.MaxInt64Value) then
    raise FieldError(AField, AText, 'out of range for ' + GetTypeName(AType));

  Result := TValue.FromOrdinal(AType, V);
end;

// The JSON forms first (TryParseJsonDateTime: milliseconds, and a 'Z' or
// an offset converted to local time). Then the ISO forms CastFromString
// reads ('yyyy-mm-dd', optionally followed by 'T' or a space and
// 'hh:nn[:ss]', the rest ignored), checked instead of defaulted; anything
// else goes to TryParseCommonDate.
function TryStrictDateTime(const AText: string; out ADate: TDateTime): Boolean;
var
  S: string;
  Y, M, D, H, N, Sc: Integer;
  T: TDateTime;
begin
  S := AText.Trim;
  if TryParseJsonDateTime(S, ADate) then
    Exit(True);
  if (Length(S) >= 10) and (S[5] = '-') and (S[8] = '-') then
  begin
    Result := False;
    if not (TryStrToInt(Copy(S, 1, 4), Y) and TryStrToInt(Copy(S, 6, 2), M) and
      TryStrToInt(Copy(S, 9, 2), D) and TryEncodeDate(Y, M, D, ADate)) then
      Exit;
    if Length(S) = 10 then
      Exit(True);
    if not CharInSet(S[11], ['T', 't', ' ']) then
      Exit;
    Sc := 0;
    if not ((Length(S) >= 16) and TryStrToInt(Copy(S, 12, 2), H) and (S[14] = ':') and
      TryStrToInt(Copy(S, 15, 2), N)) then
      Exit;
    if (Length(S) >= 19) and (S[17] = ':') and not TryStrToInt(Copy(S, 18, 2), Sc) then
      Exit;
    if not TryEncodeTime(H, N, Sc, 0, T) then
      Exit;
    ADate := ADate + T;
    Exit(True);
  end;
  Result := TryParseCommonDate(S, ADate);
end;

function StrictFloat(const AText: string; AType: PTypeInfo; const AField: string): TValue;
var
  S: string;
  DT: TDateTime;
  Sg: Single;
  Db: Double;
  Ex: Extended;
  Cu: Currency;
  Co: Comp;
  I64: Int64;
begin
  S := AText.Trim;
  if (AType = TypeInfo(TDateTime)) or (AType = TypeInfo(TDate)) or (AType = TypeInfo(TTime)) then
  begin
    if not TryStrictDateTime(S, DT) then
      raise FieldError(AField, AText, 'not a date/time');
    TValue.Make(@DT, AType, Result);
    Exit;
  end;

  case GetTypeData(AType).FloatType of
    ftSingle:
      begin
        if not TryStrToFloat(S, Sg, TFormatSettings.Invariant) then
          raise FieldError(AField, AText, 'not a number');
        TValue.Make(@Sg, AType, Result);
      end;
    ftExtended:
      begin
        if not TryStrToFloat(S, Ex, TFormatSettings.Invariant) then
          raise FieldError(AField, AText, 'not a number');
        TValue.Make(@Ex, AType, Result);
      end;
    ftCurr:
      begin
        if not TryStrToCurr(S, Cu, TFormatSettings.Invariant) then
          raise FieldError(AField, AText, 'not a number');
        TValue.Make(@Cu, AType, Result);
      end;
    ftComp:
      begin
        if not TryStrToInt64(S, I64) then
          raise FieldError(AField, AText, 'not an integer');
        Co := I64;
        TValue.Make(@Co, AType, Result);
      end;
  else
    if not TryStrToFloat(S, Db, TFormatSettings.Invariant) then
      raise FieldError(AField, AText, 'not a number');
    TValue.Make(@Db, AType, Result);
  end;
end;

function StrictEnum(const AText: string; AType: PTypeInfo; const AField: string): TValue;
var
  S: string;
  V: Integer;
  Data: PTypeData;
begin
  S := AText.Trim;
  if AType = TypeInfo(Boolean) then
  begin
    // The words CastFromString reads as True, and their opposites.
    if SameText(S, 'true') or (S = '1') or SameText(S, 'on') or SameText(S, 'yes') then
      Exit(TValue.From<Boolean>(True));
    if SameText(S, 'false') or (S = '0') or SameText(S, 'off') or SameText(S, 'no') then
      Exit(TValue.From<Boolean>(False));
    raise FieldError(AField, AText, 'not a boolean');
  end;

  // By name (case-insensitive) or by ordinal. CastFromString read only the
  // ordinal, so a name became the first member.
  Data := GetTypeData(AType);
  V := GetEnumValue(AType, S);
  if (V < 0) and not TryStrToInt(S, V) then
    raise FieldError(AField, AText, 'not a value of ' + GetTypeName(AType));
  if (V < Data.MinValue) or (V > Data.MaxValue) then
    raise FieldError(AField, AText, 'not a value of ' + GetTypeName(AType));
  Result := TValue.FromOrdinal(AType, V);
end;

/// <summary>Converts the text of a route, query or header value, or of a JSON
///   string, to the field type.</summary>
/// <param name="ADecode">True for route, query and header values, which
///   CastFromString URL-decodes; False for JSON strings, which are already
///   plain text.</param>
function StrictText(const AText: string; AType: PTypeInfo; const AField: string;
  ADecode: Boolean): TValue;
var
  S: string;
  GuidStr: string;
  G: TGUID;
  U: TUUID;
begin
  if AText = '' then
    Exit(TReflection.CastFromString('', AType));

  if ADecode then
    S := TNetEncoding.URL.Decode(AText)
  else
    S := AText;

  case AType.Kind of
    tkInteger, tkInt64:
      Result := StrictInteger(S, AType, AField);
    tkFloat:
      Result := StrictFloat(S, AType, AField);
    tkEnumeration:
      Result := StrictEnum(S, AType, AField);
    tkString, tkLString, tkWString, tkUString:
      Result := TValue.From<string>(S);
    tkRecord:
      begin
        if AType = TypeInfo(TGUID) then
        begin
          GuidStr := S.Trim;
          if not GuidStr.StartsWith('{') then
            GuidStr := '{' + GuidStr + '}';
          try
            G := StringToGUID(GuidStr);
          except
            raise FieldError(AField, AText, 'not a GUID');
          end;
          TValue.Make(@G, AType, Result);
        end
        else if AType = TypeInfo(TUUID) then
        begin
          try
            U := TUUID.FromString(S);
          except
            raise FieldError(AField, AText, 'not a UUID');
          end;
          TValue.Make(@U, AType, Result);
        end
        else
          Result := TReflection.CastFromString(AText, AType);
      end;
  else
    Result := TReflection.CastFromString(AText, AType);
  end;
end;

/// <summary>True for a field that the JSON does not set: [JsonIgnore] or
///   [JsonIgnore(TJsonIgnoreMode.OnRead)].</summary>
function IgnoredOnRead(AField: TRttiField): Boolean;
var
  Attr: TCustomAttribute;
begin
  for Attr in AField.GetAttributes do
    if (Attr is JsonIgnoreAttribute) and JsonIgnoreAttribute(Attr).IgnoresRead then
      Exit(True);
  Result := False;
end;

/// <summary>True for the field types the strict conversions handle. The
///   others (nested records, arrays, Nullable, ...) keep the previous
///   behaviour of this binder.</summary>
function IsStrictKind(AType: PTypeInfo): Boolean;
begin
  case AType.Kind of
    tkInteger, tkInt64, tkFloat, tkEnumeration,
    tkString, tkLString, tkWString, tkUString:
      Result := True;
    tkRecord:
      Result := (AType = TypeInfo(TGUID)) or (AType = TypeInfo(TUUID));
  else
    Result := False;
  end;
end;

/// <summary>Converts a JSON body value to the field type: a number for a
///   number, a string for a string or a date, true/false for a Boolean. A
///   number written as a string ("7") is accepted; a value that does not
///   convert raises.</summary>
/// <remarks>A number is read from its text as written (AsString). ToJson
///   writes a primitive through a Double, so 9007199254740993 became
///   "9.00719925474099E15" and an Int64 or UInt64 with more than 15 digits
///   was refused; it also built a writer per field. AsInt64 stops at the
///   decimal point and wraps on overflow (7.5 would bind as 7). ToJson stays
///   on the error paths only.</remarks>
function StrictJson(const ANode: IDextJsonNode; AType: PTypeInfo; const AField: string): TValue;
var
  IsDate: Boolean;
begin
  if (ANode = nil) or (ANode.NodeType = jntNull) then
  begin
    TValue.Make(nil, AType, Result);
    Exit;
  end;

  case AType.Kind of
    tkInteger, tkInt64:
      case ANode.NodeType of
        jntNumber: Result := StrictInteger(ANode.AsString, AType, AField);
        jntString: Result := StrictInteger(ANode.AsString, AType, AField);
      else
        raise FieldError(AField, ANode.ToJson, 'expected an integer');
      end;
    tkFloat:
      begin
        IsDate := (AType = TypeInfo(TDateTime)) or (AType = TypeInfo(TDate)) or
          (AType = TypeInfo(TTime));
        if ANode.NodeType = jntString then
          Result := StrictFloat(ANode.AsString, AType, AField)
        else if (ANode.NodeType = jntNumber) and not IsDate then
          Result := StrictFloat(ANode.AsString, AType, AField)
        else if IsDate then
          raise FieldError(AField, ANode.ToJson, 'expected a date/time string')
        else
          raise FieldError(AField, ANode.ToJson, 'expected a number');
      end;
    tkEnumeration:
      case ANode.NodeType of
        jntBoolean:
          if AType = TypeInfo(Boolean) then
            Result := TValue.From<Boolean>(ANode.AsBoolean)
          else
            raise FieldError(AField, ANode.ToJson, 'not a value of ' + GetTypeName(AType));
        jntString: Result := StrictEnum(ANode.AsString, AType, AField);
        jntNumber: Result := StrictEnum(ANode.AsString, AType, AField);
      else
        raise FieldError(AField, ANode.ToJson, 'expected a value of ' + GetTypeName(AType));
      end;
    tkString, tkLString, tkWString, tkUString:
      case ANode.NodeType of
        // As written: no URL decoding of JSON strings.
        jntString: Result := TValue.From<string>(ANode.AsString);
        jntNumber: Result := TValue.From<string>(ANode.AsString);
        // The JSON literal, whatever the driver's AsString gives for it.
        jntBoolean:
          if ANode.AsBoolean then
            Result := TValue.From<string>('true')
          else
            Result := TValue.From<string>('false');
      else
        raise FieldError(AField, ANode.ToJson, 'expected a string');
      end;
  else
    // TGUID / TUUID
    if ANode.NodeType = jntString then
      Result := StrictText(ANode.AsString, AType, AField, False)
    else
      raise FieldError(AField, ANode.ToJson, 'expected a string');
  end;
end;

function TModelBinder.BindRecordHybrid(AType: PTypeInfo; Context: IHttpContext): TValue;
var
  ContextRtti: TRttiContext;
  RttiType: TRttiType;
  Field: TRttiField;
  SourceProvider: TBindingSourceProvider;
  BindingSource: TBindingSource;
  FieldName: string;
  FieldValue: TValue;
  BodyBytes: TBytes;
  BodyLen: Integer;
  Stream: TStream;
  Headers: IStringDictionary;
  RouteParams: TRouteValueDictionary;
  QueryParams: IStringDictionary;
  RouteVal, QueryVal: string;
  BodyJsonObj: IDextJsonObject;
  LMethod, LContentType: string;
  LIsPostLike, LIsJson: Boolean;
  BodyJsonStr: string;
  JsonNode: IDextJsonNode;
  FoundInBody, FieldFound: Boolean;
  JsonFieldName: string;
  HeaderVal: string;
  StrVal: string;
  HasBodyFields: Boolean;
  BodyMissing: Boolean;
  ParseError: string;
begin
  if AType.Kind <> tkRecord then
    raise EBindingException.Create('BindRecordHybrid only supports records');

  TValue.Make(nil, AType, Result);
  BodyJsonObj := nil;

  ContextRtti := TReflection.Context;
  try
    RttiType := ContextRtti.GetType(AType);
  SourceProvider := TBindingSourceProvider.Create;
  try
    // Get request data sources
    Headers := Context.Request.Headers;
    RouteParams := Context.Request.RouteParams;
    QueryParams := Context.Request.Query;

      // Pre-load body JSON once if it's a POST/PUT/PATCH and likely contains JSON
      LMethod := Context.Request.Method;
      LIsPostLike := (LMethod = 'POST') or (LMethod = 'PUT') or (LMethod = 'PATCH') or (LMethod = 'QUERY');
      LContentType := Context.Request.GetHeader('Content-Type');
      LIsJson := ContainsAsciiText(LContentType, 'application/json');

      // Does any field expect the body? Fields without a binding attribute
      // do (bsBody), with route and query as fallbacks.
      HasBodyFields := False;
      for Field in RttiType.GetFields do
        if SourceProvider.GetBindingSource(Field) = bsBody then
        begin
          HasBodyFields := True;
          Break;
        end;

      Stream := Context.Request.Body;
      BodyMissing := LIsPostLike and ((Stream = nil) or (Stream.Size = 0));
      if (Stream <> nil) and (Stream.Size > 0) and (LIsPostLike or LIsJson) then
      begin
        BodyLen := Integer(Stream.Size);
        if Stream is TBytesStream then
          BodyBytes := TBytesStream(Stream).Bytes
        else
        begin
          Stream.Position := 0;
          SetLength(BodyBytes, BodyLen);
          if BodyLen > 0 then
            Stream.ReadBuffer(BodyBytes[0], BodyLen);
        end;
        
        BodyJsonStr := TEncoding.UTF8.GetString(BodyBytes, 0, BodyLen);

        if Trim(BodyJsonStr) = '' then
          BodyMissing := LIsPostLike
        else
        begin
          // A body that does not parse, or is not a JSON object, is a binding
          // failure when a field expects it: before, every field silently
          // kept its default and the handler ran.
          ParseError := '';
          JsonNode := nil;
          try
            JsonNode := TDextJson.Provider.Parse(BodyJsonStr);
          except
            on E: Exception do
              ParseError := E.Message;
          end;
          if (JsonNode <> nil) and (JsonNode.GetNodeType = jntObject) then
            BodyJsonObj := JsonNode as IDextJsonObject
          else if HasBodyFields then
          begin
            if ParseError <> '' then
              raise EBindingException.Create('Error parsing JSON body: ' + ParseError);
            raise EBindingException.Create('The JSON body must be an object');
          end;
        end;
      end;

      for Field in RttiType.GetFields do
      begin
        try
          // 1. Determine binding source from field attributes
          BindingSource := SourceProvider.GetBindingSource(Field);
          FieldName := SourceProvider.GetBindingName(Field);

          // 2. Bind based on source
          case BindingSource of
            bsHeader:
              begin
                // Headers are case-insensitive (GetHeader already handles this)
                HeaderVal := Context.Request.GetHeader(FieldName);
                if HeaderVal <> '' then
                  FieldValue := StrictText(HeaderVal, Field.FieldType.Handle, FieldName, True)
                else
                  FieldValue := TReflection.GetDefaultValue(Field, Field.FieldType.Handle);
              end;

            bsQuery:
              begin
                if QueryParams.TryGetValue(FieldName, QueryVal) then
                   FieldValue := StrictText(QueryVal, Field.FieldType.Handle, FieldName, True)
                else
                   FieldValue := TReflection.GetDefaultValue(Field, Field.FieldType.Handle);
              end;

            bsRoute:
              begin
                if RouteParams.TryGetValue(FieldName, RouteVal) then
                  FieldValue := StrictText(RouteVal, Field.FieldType.Handle, FieldName, True)
                else
                  FieldValue := TReflection.GetDefaultValue(Field, Field.FieldType.Handle);
              end;

            bsServices:
              begin
                // For services, delegate to BindServices for the specific field.
                // A service that cannot be resolved leaves the field empty, as
                // before: that is not a client error.
                try
                  FieldValue := BindServices(Field.FieldType.Handle, Context);
                except
                  FieldValue := TValue.Empty;
                end;
              end;

            bsBody:
              begin
                FoundInBody := False;
                
                // First, try to find in JSON body (not for a field the JSON
                // must not set: [JsonIgnore] / [JsonIgnore(OnRead)])
                if (BodyJsonObj <> nil) and not IgnoredOnRead(Field) then
                begin
                  // Try to find the field (case-insensitive)
                  JsonFieldName := FieldName;
                  FieldFound := BodyJsonObj.Contains(JsonFieldName);
                  
                  // Try lowercase if not found
                  if not FieldFound then
                  begin
                    JsonFieldName := LowerCase(FieldName);
                    FieldFound := BodyJsonObj.Contains(JsonFieldName);
                  end;
                  
                  // Try camelCase if not found
                  if not FieldFound then
                  begin
                    if Length(FieldName) > 0 then
                    begin
                      JsonFieldName := LowerCase(FieldName[1]) + Copy(FieldName, 2, MaxInt);
                      FieldFound := BodyJsonObj.Contains(JsonFieldName);
                    end;
                  end;
                  
                  if FieldFound then
                  begin
                    FoundInBody := True;
                    if IsStrictKind(Field.FieldType.Handle) then
                      FieldValue := StrictJson(BodyJsonObj.GetNode(JsonFieldName),
                        Field.FieldType.Handle, FieldName)
                    else
                    begin
                      // Types this binder does not convert (nested records,
                      // arrays, Nullable, ...): unchanged.
                      try
                        StrVal := BodyJsonObj.GetString(JsonFieldName);
                        FieldValue := TReflection.CastFromString(StrVal, Field.FieldType.Handle);
                      except
                        FieldValue := TValue.Empty;
                      end;
                    end;
                  end;
                end;
                
                // Fallback 1: Try RouteParams (for IDs in URL like /api/products/{id})
                if not FoundInBody then
                begin
                  if RouteParams.TryGetValue(FieldName, RouteVal) then
                  begin
                    FieldValue := StrictText(RouteVal, Field.FieldType.Handle, FieldName, True);
                    FoundInBody := True; // Mark as found
                  end;
                end;
                
                // Fallback 2: Try Query params (for ?param=value)
                if not FoundInBody then
                begin
                  if QueryParams.TryGetValue(FieldName, QueryVal) then
                  begin
                    FieldValue := StrictText(QueryVal, Field.FieldType.Handle, FieldName, True);
                  end
                  else if BodyMissing then
                    // The field expects the body, and there is none: route
                    // and query did not provide it either.
                    raise EBindingException.Create('Request body is empty')
                  else
                    FieldValue := TReflection.GetDefaultValue(Field, Field.FieldType.Handle);
                end;
              end;

            bsForm:
              begin
                // Form data not implemented yet
                FieldValue := TReflection.CastFromString('', Field.FieldType.Handle);
              end;
          end;

          // 3. Set field value
          if not FieldValue.IsEmpty then
            Field.SetValue(Result.GetReferenceToRawData, FieldValue);

        except
          // A field that cannot be bound is a binding failure (400): before,
          // the error was swallowed and the field kept its default.
          on E: EBindingException do
            raise;
          on E: Exception do
            raise EBindingException.CreateFmt('Field "%s": %s', [FieldName, E.Message]);
        end;
      end;
    finally
      SourceProvider.Free;
    end;
  finally
  ;
  end;
end;

function TModelBinder.BindValue(const AValue: string; AType: PTypeInfo): TValue;
begin
  Result := TReflection.CastFromString(AValue, AType);
end;

{ TModelBinderHelper }

class function TModelBinderHelper.BindQuery<T>(ABinder: IModelBinder; Context: IHttpContext): T;
var
  Value: TValue;
begin
  Value := ABinder.BindQuery(TypeInfo(T), Context);
  Result := Value.AsType<T>;
end;

class function TModelBinderHelper.BindBody<T>(ABinder: IModelBinder; Context: IHttpContext): T;
var
  Value: TValue;
begin
  Value := ABinder.BindBody(TypeInfo(T), Context);
  Result := Value.AsType<T>;
end;

class function TModelBinderHelper.BindRoute<T>(ABinder: IModelBinder; Context: IHttpContext): T;
var
  Value: TValue;
  P: Pointer;
begin
  Value := ABinder.BindRoute(TypeInfo(T), Context);
  
  // For records like TUUID/TGUID, AsType<T> fails with "Insufficient RTTI"
  // Always use direct memory copy for records
  if PTypeInfo(TypeInfo(T)).Kind = tkRecord then
  begin
    P := Value.GetReferenceToRawData;
    if P <> nil then
      Move(P^, Result, SizeOf(T))
    else
      Result := Default(T);
  end
  else
    Result := Value.AsType<T>;
end;

{ TBindingSourceProvider }

function TBindingSourceProvider.GetBindingSource(Field: TRttiField): TBindingSource;
var
  Attr: TCustomAttribute;
begin
  for Attr in Field.GetAttributes do
  begin
    if Attr is BindingAttribute then
      Exit(BindingAttribute(Attr).Source);
  end;

  // Default: FromBody for all field types without explicit binding attribute
  // This is the expected behavior for records used in POST/PUT requests
  // Fields that need to come from Query/Route/Header should use explicit attributes
  Result := bsBody;
end;

function TBindingSourceProvider.GetBindingName(Field: TRttiField): string;
var
  Attr: TCustomAttribute;
begin
  for Attr in Field.GetAttributes do
  begin
    if (Attr is FromQueryAttribute) and (FromQueryAttribute(Attr).Name <> '') then
      Exit(FromQueryAttribute(Attr).Name)
    else if (Attr is FromRouteAttribute) and (FromRouteAttribute(Attr).Name <> '') then
      Exit(FromRouteAttribute(Attr).Name)
    else if (Attr is FromHeaderAttribute) and (FromHeaderAttribute(Attr).Name <> '') then
      Exit(FromHeaderAttribute(Attr).Name);
  end;

  Result := Field.Name;
end;

function TBindingSourceProvider.GetBindingSource(Param: TRttiParameter): TBindingSource;
var
  Attr: TCustomAttribute;
begin
  for Attr in Param.GetAttributes do
  begin
    if Attr is BindingAttribute then
      Exit(BindingAttribute(Attr).Source);
  end;

  // Default: FromBody for complex types, FromQuery for simple types
  if Param.ParamType.TypeKind in [tkRecord, tkClass] then
    Result := bsBody
  else
    Result := bsQuery;
end;

function TBindingSourceProvider.GetBindingName(Param: TRttiParameter): string;
var
  Attr: TCustomAttribute;
begin
  for Attr in Param.GetAttributes do
  begin
    if (Attr is FromQueryAttribute) and (FromQueryAttribute(Attr).Name <> '') then
      Exit(FromQueryAttribute(Attr).Name)
    else if (Attr is FromRouteAttribute) and (FromRouteAttribute(Attr).Name <> '') then
      Exit(FromRouteAttribute(Attr).Name)
    else if (Attr is FromHeaderAttribute) and (FromHeaderAttribute(Attr).Name <> '') then
      Exit(FromHeaderAttribute(Attr).Name);
  end;

  Result := Param.Name;
end;

end.
