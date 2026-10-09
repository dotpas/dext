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
unit Dext.Web.Routing;

{$I Dext.inc}

interface

uses
  System.SysUtils,
  System.StrUtils,
  System.RegularExpressions,
  Dext.Collections,
  Dext.Collections.Dict,
  Dext.Web.Interfaces;
  // Note: We don't import Versioning here to avoid circular dep if possible, 
  // or we define IApiVersionReader in Interfaces? 
  // For now, let's assume simple string matching or header reading inside logic if we pass Context.
  // Actually, we can just extract version in Middleware and pass it?
  // No, the interface change allows passing Context.
  
type
  // Forward delcaration if needed, but IApiVersionReader is in another unit.
  // Let's rely on manually checking context headers/query for now to minimize dependencies,
  // OR assume the Caller (Middleware) passes the Version string?
  // Ideally: FindMatchingRoute(Context).

  TRouteSegment = record
  public
    IsLiteral: Boolean;
    Text: string;
  end;

  /// <summary>
  ///   Represents a compiled route pattern. Analyzes and stores literal segments
  ///   and parameter names extracted from the route definition (e.g., /users/{id}).
  /// </summary>
  TRoutePattern = class
  private
    FPattern: string;
    FSegments: TArray<TRouteSegment>;
    FParameterNames: TArray<string>;
    procedure ParseSegments(const APattern: string);
  public
    constructor Create(const APattern: string);
    /// <summary>
    ///   Tries to match a real path against this pattern.
    ///   Extracts the resulting parameters into the AParams dictionary on success.
    /// </summary>
    function Match(const APath: string; out AParams: TRouteValueDictionary): Boolean;
    /// <summary>Original route pattern (e.g., /api/{controller}/{id}).</summary>
    property Pattern: string read FPattern;
    /// <summary>Parameter names found in the pattern.</summary>
    property ParameterNames: TArray<string> read FParameterNames;
  end;

  /// <summary>
  ///   Represents a single route definition linked to a handler and metadata.
  /// </summary>
  TRouteDefinition = class
  private
    FMethod: string;
    FPath: string;
    FHandler: TRequestDelegate;
    FPattern: TRoutePattern;
    FMetadata: TEndpointMetadata;
  public
    constructor Create(const AMethod, APath: string; AHandler: TRequestDelegate);
    destructor Destroy; override;
    property Method: string read FMethod;
    property Path: string read FPath;
    property Handler: TRequestDelegate read FHandler;
    property Pattern: TRoutePattern read FPattern;
    property Metadata: TEndpointMetadata read FMetadata write FMetadata;
  end;

  /// <summary>
  ///   Interface for the engine that finds routes matching a request.
  /// </summary>
  IRouteMatcher = interface
    ['{A1B2C3D4-E5F6-4A7B-8C9D-0E1F2A3B4C5D}']
    function FindMatchingRoute(const AContext: IHttpContext;
      out AHandler: TRequestDelegate;
      out ARouteParams: TRouteValueDictionary;
      out AMetadata: TEndpointMetadata): Boolean;
  end;

  /// <summary>
  ///   Default implementation of the route matcher.
  ///   Manages API versioning and prioritizes literal (exact) routes over parameterized routes.
  /// </summary>
  /// <summary>
  ///   Represents a leaf node in the routing tree, representing a configured endpoint.
  /// </summary>
  TRouteLeaf = class
  public
    /// <summary>HTTP method/verb (e.g. GET, POST) of the route.</summary>
    Method: string;
    /// <summary>The delegate handler invoked when the route is matched.</summary>
    Handler: TRequestDelegate;
    /// <summary>Endpoint metadata (authorization, CORS, etc.) for this route.</summary>
    Metadata: TEndpointMetadata;
    /// <summary>Initializes a new route leaf.</summary>
    constructor Create(
      const AMethod: string;
      AHandler: TRequestDelegate;
      const AMetadata: TEndpointMetadata
    );
  end;

  /// <summary>
  ///   Represents a segment node in the Radix routing tree.
  /// </summary>
  TRouteNode = class
  public
    /// <summary>The path segment string represented by this node.</summary>
    Segment: string;
    /// <summary>Indicates if this node is a route parameter (e.g. {id}).</summary>
    IsParameter: Boolean;
    /// <summary>The name of the parameter if IsParameter is True.</summary>
    ParameterName: string;
    /// <summary>List of child nodes branch-off from this path segment.</summary>
    Children: IList<TRouteNode>;
    /// <summary>First parameter child, if any, for fast fallback without scanning all literals again.</summary>
    ParameterChild: TRouteNode;
    /// <summary>List of configured endpoint leaves at this path level.</summary>
    Leaves: IList<TRouteLeaf>;
    /// <summary>Initializes a new route node with a segment name.</summary>
    constructor Create(const ASegment: string);
    /// <summary>Cleans up child nodes and leaves lists.</summary>
    destructor Destroy; override;
  end;

  TDextCompiledRouteLeaf = record
    Method: string;
    MethodMask: Cardinal;
    MethodHash: Cardinal;
    Handler: TRequestDelegate;
    Metadata: TEndpointMetadata;
    Plan: Pointer;
  end;

  TDextCompiledRouteNode = record
  public
    Segment: string;
    IsParameter: Boolean;
    ParameterName: string;
    Children: TArray<TDextCompiledRouteNode>;
    ParameterChildIndex: Integer;
    Leaves: TArray<TDextCompiledRouteLeaf>;
    AllowedMethodsMask: Cardinal;
    HasCustomMethods: Boolean;
    OptionsHandler: TRequestDelegate;
    MethodNotAllowedHandler: TRequestDelegate;
    OptionsMetadata: TEndpointMetadata;
  end;
  PDextCompiledRouteNode = ^TDextCompiledRouteNode;

  TRouteMatcher = class(TInterfacedObject, IRouteMatcher)
  private
    FRoutes: IList<TRouteDefinition>;
    FRoot: TRouteNode;
    FCompiledRoot: TDextCompiledRouteNode;
    FExactRoutes: IDictionary<string, IDictionary<string, TRouteLeaf>>;
    // True if at least one route declares API versions. Without any, the
    // requested version never changes the match (an empty list matches every
    // version), so FindMatchingRoute does not read it.
    FHasVersionedRoutes: Boolean;
    procedure AddRouteToTree(const ARoute: TRouteDefinition);
    function GetRequestedApiVersion(const AContext: IHttpContext): string;
    function IsVersionMatch(
      const RequestedVersion: string;
      const SupportedVersions: TArray<string>
    ): Boolean;
    function MatchNodePath(
      Node: TRouteNode;
      const APath: string;
      AStartPos, AEndPos: Integer;
      const AMethod, AVersion: string;
      out ALeaf: TRouteLeaf;
      var AParams: TRouteValueDictionary
    ): Boolean;
  public
    constructor Create(const ARoutes: IList<TRouteDefinition>);
    destructor Destroy; override;
    function FindMatchingRoute(const AContext: IHttpContext;
      out AHandler: TRequestDelegate;
      out ARouteParams: TRouteValueDictionary;
      out AMetadata: TEndpointMetadata): Boolean;
  end;

  ERouteException = class(Exception);

implementation

function NormalizeExactRoutePath(const APath: string): string;
var
  EndPos: Integer;
begin
  EndPos := Length(APath);
  if (EndPos > 1) and (APath[EndPos] = '/') then
    Dec(EndPos);
  if EndPos = Length(APath) then
    Result := APath
  else
    Result := Copy(APath, 1, EndPos);
end;

function SamePathSegmentText(const APath: string; AStartPos, ALen: Integer;
  const ASegment: string): Boolean;
var
  i: Integer;
  C1: Char;
  C2: Char;
begin
  if ALen <> Length(ASegment) then
    Exit(False);

  for i := 1 to ALen do
  begin
    C1 := APath[AStartPos + i - 1];
    C2 := ASegment[i];
    if (Ord(C1) > 127) or (Ord(C2) > 127) then
      Exit(SameText(Copy(APath, AStartPos, ALen), ASegment));
    if (C1 >= 'A') and (C1 <= 'Z') then
      C1 := Chr(Ord(C1) + 32);
    if (C2 >= 'A') and (C2 <= 'Z') then
      C2 := Chr(Ord(C2) + 32);
    if C1 <> C2 then
      Exit(False);
  end;
  Result := True;
end;

function GetMethodMask(const AMethod: string): Cardinal;
begin
  if SameText(AMethod, 'GET') then Exit(1);
  if SameText(AMethod, 'POST') then Exit(2);
  if SameText(AMethod, 'PUT') then Exit(4);
  if SameText(AMethod, 'DELETE') then Exit(8);
  if SameText(AMethod, 'OPTIONS') then Exit(16);
  if SameText(AMethod, 'HEAD') then Exit(32);
  if SameText(AMethod, 'PATCH') then Exit(64);
  Result := 128;
end;

{$OVERFLOWCHECKS OFF}
{$RANGECHECKS OFF}
function GetMethodHash(const AMethod: string): Cardinal;
var
  Character: Char;
  i: Integer;
  H: Cardinal;
begin
  H := 2166136261;
  for i := 1 to Length(AMethod) do
  begin
    Character := AMethod[i];
    if (Character >= 'a') and (Character <= 'z') then
      Character := Chr(Ord(Character) - 32);
    H := (H xor Cardinal(Ord(Character))) * Cardinal(16777619);
  end;
  Result := H;
end;

function IsVersionMatchHelper(
  const RequestedVersion: string;
  const SupportedVersions: TArray<string>
): Boolean;
var
  V: string;
begin
  if Length(SupportedVersions) = 0 then
    Exit(True);

  if RequestedVersion = '' then
    Exit(False);

  for V in SupportedVersions do
    if SameText(V, RequestedVersion) then
      Exit(True);

  Result := False;
end;

function CreateOptionsHandler(const AAllowMethods,
  AAcceptQuery: string): TRequestDelegate;
begin
  Result := procedure(Context: IHttpContext)
    begin
      Context.Response.StatusCode := 200;
      Context.Response.AddHeader('Allow', AAllowMethods);
      if AAcceptQuery <> '' then
        Context.Response.AddHeader('Accept-Query', AAcceptQuery);
      Context.Response.Write('');
    end;
end;

function CreateMethodNotAllowedHandler(
  const AAllowMethods: string): TRequestDelegate;
begin
  Result := procedure(Context: IHttpContext)
    begin
      Context.Response.StatusCode := 405;
      Context.Response.AddHeader('Allow', AAllowMethods);
      Context.Response.Write('Method Not Allowed');
    end;
end;

function CompileRouteNode(Source: TRouteNode): TDextCompiledRouteNode;
var
  i: Integer;
  LeafMask: Cardinal;
  AllowMethods: string;
  AcceptQuery: string;
  QueryTypeIndex: Integer;
begin
  Result.Segment := Source.Segment;
  Result.IsParameter := Source.IsParameter;
  Result.ParameterName := Source.ParameterName;
  Result.AllowedMethodsMask := 0;
  Result.HasCustomMethods := False;
  Result.OptionsHandler := nil;
  Result.MethodNotAllowedHandler := nil;
  Result.OptionsMetadata := Default(TEndpointMetadata);

  // Compile Children
  SetLength(Result.Children, Source.Children.Count);
  for i := 0 to Source.Children.Count - 1 do
  begin
    Result.Children[i] := CompileRouteNode(Source.Children[i]);
    Result.AllowedMethodsMask := Result.AllowedMethodsMask or
      Result.Children[i].AllowedMethodsMask;
    Result.HasCustomMethods := Result.HasCustomMethods or
      Result.Children[i].HasCustomMethods;
  end;

  // Compile ParameterChild
  Result.ParameterChildIndex := -1;
  if Source.ParameterChild <> nil then
  begin
    for i := 0 to High(Result.Children) do
    begin
      if Result.Children[i].Segment = Source.ParameterChild.Segment then
      begin
        Result.ParameterChildIndex := i;
        Break;
      end;
    end;
  end;

  // Compile Leaves
  SetLength(Result.Leaves, Source.Leaves.Count);
  for i := 0 to Source.Leaves.Count - 1 do
  begin
    Result.Leaves[i].Method := Source.Leaves[i].Method;
    Result.Leaves[i].MethodHash := GetMethodHash(Source.Leaves[i].Method);
    Result.Leaves[i].Handler := Source.Leaves[i].Handler;
    Result.Leaves[i].Metadata := Source.Leaves[i].Metadata;
    Result.Leaves[i].Plan := nil;

    LeafMask := GetMethodMask(Source.Leaves[i].Method);
    Result.Leaves[i].MethodMask := LeafMask;
    Result.AllowedMethodsMask := Result.AllowedMethodsMask or LeafMask;
    if LeafMask = 128 then
      Result.HasCustomMethods := True;
  end;

  if Length(Result.Leaves) > 0 then
  begin
    AllowMethods := 'OPTIONS';
    AcceptQuery := '';
    for i := 0 to High(Result.Leaves) do
    begin
      if not AllowMethods.Contains(Result.Leaves[i].Method) then
        AllowMethods := AllowMethods + ', ' + Result.Leaves[i].Method;
      if SameText(Result.Leaves[i].Method, 'QUERY') then
      begin
        if Length(Result.Leaves[i].Metadata.AcceptQueryTypes) > 0 then
        begin
          for QueryTypeIndex := 0 to High(
            Result.Leaves[i].Metadata.AcceptQueryTypes) do
          begin
            if AcceptQuery <> '' then
              AcceptQuery := AcceptQuery + ', ';
            AcceptQuery := AcceptQuery +
              Result.Leaves[i].Metadata.AcceptQueryTypes[QueryTypeIndex];
          end;
        end;
        if AcceptQuery = '' then
          AcceptQuery := 'application/json';
      end;
    end;
    Result.OptionsHandler := CreateOptionsHandler(AllowMethods, AcceptQuery);
    Result.MethodNotAllowedHandler :=
      CreateMethodNotAllowedHandler(AllowMethods);
    Result.OptionsMetadata.Method := 'OPTIONS';
  end;
end;

{$OVERFLOWCHECKS OFF}
{$RANGECHECKS OFF}
function FindCompiledPathNode(Node: PDextCompiledRouteNode;
  const APath: string; AStartPos, AEndPos: Integer): PDextCompiledRouteNode;
var
  i: Integer;
  Child: PDextCompiledRouteNode;
  SlashPos: Integer;
  SegmentLength: Integer;
  NextPosition: Integer;
begin
  if AStartPos > AEndPos then
    Exit(Node);
  SlashPos := AStartPos;
  while (SlashPos <= AEndPos) and (APath[SlashPos] <> '/') do
    Inc(SlashPos);
  SegmentLength := SlashPos - AStartPos;
  NextPosition := SlashPos + 1;
  if Length(Node^.Children) > 0 then
  begin
    for i := 0 to High(Node^.Children) do
    begin
      Child := @Node^.Children[i];
      if (not Child^.IsParameter) and SamePathSegmentText(APath, AStartPos,
        SegmentLength, Child^.Segment) then
      begin
        Result := FindCompiledPathNode(Child, APath, NextPosition, AEndPos);
        if Result <> nil then
          Exit;
      end;
    end;
  end;
  if Node^.ParameterChildIndex >= 0 then
    Exit(FindCompiledPathNode(@Node^.Children[Node^.ParameterChildIndex], APath, NextPosition,
      AEndPos));
  Result := nil;
end;

{$OVERFLOWCHECKS OFF}
{$RANGECHECKS OFF}
function MatchCompiledNodePath(
  Node: PDextCompiledRouteNode;
  const APath: string;
  AStartPos, AEndPos: Integer;
  const AMethod, AVersion: string;
  var ALeaf: TDextCompiledRouteLeaf;
  var AParams: TRouteValueDictionary
): Boolean;
var
  i: Integer;
  Child: PDextCompiledRouteNode;
  SegmentLen: Integer;
  SlashPos: Integer;
  NextPos: Integer;
  MethodMask: Cardinal;
  MethodHash: Cardinal;
  CatchAllLen: Integer;
  ParamName: string;
begin
  if Node = nil then
    Exit(False);

  MethodMask := GetMethodMask(AMethod);
  MethodHash := GetMethodHash(AMethod);

  if (MethodMask <> 128) and
     ((Node^.AllowedMethodsMask and MethodMask) = 0) then
    Exit(False);
  if (MethodMask = 128) and not Node^.HasCustomMethods then
    Exit(False);

  if AStartPos > AEndPos then
  begin
    if Length(Node^.Leaves) > 0 then
    begin
      for i := 0 to High(Node^.Leaves) do
      begin
        if (Node^.Leaves[i].MethodMask = MethodMask) and
           (Node^.Leaves[i].MethodHash = MethodHash) and
           SameText(Node^.Leaves[i].Method, AMethod) and
           IsVersionMatchHelper(AVersion, Node^.Leaves[i].Metadata.ApiVersions) then
        begin
          ALeaf := Node^.Leaves[i];
          Exit(True);
        end;
      end;

      for i := 0 to High(Node^.Leaves) do
      begin
        if (Node^.Leaves[i].MethodMask = MethodMask) and
           (Node^.Leaves[i].MethodHash = MethodHash) and
           SameText(Node^.Leaves[i].Method, AMethod) and
           (AVersion = '') and
           (Length(Node^.Leaves[i].Metadata.ApiVersions) = 0) then
        begin
          ALeaf := Node^.Leaves[i];
          Exit(True);
        end;
      end;
    end;
    Exit(False);
  end;

  SlashPos := AStartPos;
  while (SlashPos <= AEndPos) and (APath[SlashPos] <> '/') do
    Inc(SlashPos);

  SegmentLen := SlashPos - AStartPos;
  NextPos := SlashPos + 1;

  if Length(Node^.Children) > 0 then
  begin
    for i := 0 to High(Node^.Children) do
    begin
      Child := @Node^.Children[i];
      if (not Child^.IsParameter) and
         SamePathSegmentText(APath, AStartPos, SegmentLen, Child^.Segment) then
      begin
        if MatchCompiledNodePath(
          Child, APath, NextPos, AEndPos, AMethod, AVersion, ALeaf, AParams
        ) then
          Exit(True);
      end;
    end;
  end;

  if Node^.ParameterChildIndex >= 0 then
  begin
    Child := @Node^.Children[Node^.ParameterChildIndex];
    if (Length(Child^.ParameterName) > 0) and (Child^.ParameterName[1] = '*') then
    begin
      // Catch-all parameter: matches everything remaining!
      CatchAllLen := AEndPos - AStartPos + 1;
      if MatchCompiledNodePath(
        Child, APath, AEndPos + 1, AEndPos, AMethod, AVersion, ALeaf, AParams
      ) then
      begin
        ParamName := Copy(Child^.ParameterName, 2, Length(Child^.ParameterName) - 1);
        AParams.AddSlice(ParamName, APath, AStartPos, CatchAllLen);
        Exit(True);
      end;
    end
    else
    begin
      if MatchCompiledNodePath(
        Child, APath, NextPos, AEndPos, AMethod, AVersion, ALeaf, AParams
      ) then
      begin
        AParams.AddSlice(Child^.ParameterName, APath, AStartPos, SegmentLen);
        Exit(True);
      end;
    end;
  end;

  Result := False;
end;

{ TRoutePattern }

constructor TRoutePattern.Create(const APattern: string);
begin
  inherited Create;
  FPattern := APattern;

  if APattern = '' then
    raise ERouteException.Create('Route pattern cannot be empty');

  ParseSegments(APattern);
end;

procedure TRoutePattern.ParseSegments(const APattern: string);
var
  Idx, StartIdx: Integer;
  InParam: Boolean;
begin
  FSegments := nil;
  FParameterNames := nil;
  
  StartIdx := 1;
  InParam := False;
  Idx := 1;
  while Idx <= Length(APattern) do
  begin
    if (not InParam) and (APattern[Idx] = '{') then
    begin
      // Flush literal
      if Idx > StartIdx then
      begin
        SetLength(FSegments, Length(FSegments) + 1);
        FSegments[High(FSegments)].IsLiteral := True;
        FSegments[High(FSegments)].Text := Copy(APattern, StartIdx, Idx - StartIdx);
      end;
      StartIdx := Idx + 1;
      InParam := True;
    end
    else if InParam and (APattern[Idx] = '}') then
    begin
      // Flush param
      if Idx > StartIdx then
      begin
        SetLength(FSegments, Length(FSegments) + 1);
        FSegments[High(FSegments)].IsLiteral := False;
        FSegments[High(FSegments)].Text := Copy(APattern, StartIdx, Idx - StartIdx);
        
        SetLength(FParameterNames, Length(FParameterNames) + 1);
        FParameterNames[High(FParameterNames)] := FSegments[High(FSegments)].Text;
      end;
      StartIdx := Idx + 1;
      InParam := False;
    end;
    Inc(Idx);
  end;
  
  if StartIdx <= Length(APattern) then
  begin
    if InParam then
      raise ERouteException.Create('Unclosed parameter in pattern');
    SetLength(FSegments, Length(FSegments) + 1);
    FSegments[High(FSegments)].IsLiteral := True;
    FSegments[High(FSegments)].Text := Copy(APattern, StartIdx, Length(APattern) - StartIdx + 1);
  end;
end;

function TRoutePattern.Match(const APath: string;
  out AParams: TRouteValueDictionary): Boolean;
var
  I: Integer;
  PathIdx: Integer;
  Seg: TRouteSegment;
  ValueStart, ValueLen: Integer;
begin
  AParams.Clear;
  PathIdx := 1;

  for I := 0 to High(FSegments) do
  begin
    Seg := FSegments[I];
    
    if Seg.IsLiteral then
    begin
      if Length(APath) - PathIdx + 1 < Length(Seg.Text) then
        Exit(False);
        
      if StrLIComp(PChar(APath) + PathIdx - 1, PChar(Seg.Text), Length(Seg.Text)) <> 0 then
        Exit(False);
        
      Inc(PathIdx, Length(Seg.Text));
    end
    else
    begin
      ValueStart := PathIdx;
      
      if I < High(FSegments) then
      begin
        while (PathIdx <= Length(APath)) and (APath[PathIdx] <> '/') do
        begin
          if FSegments[I+1].IsLiteral and (Length(FSegments[I+1].Text) > 0) then
          begin
            if (Length(APath) - PathIdx + 1 >= Length(FSegments[I+1].Text)) and
               (StrLIComp(PChar(APath) + PathIdx - 1, PChar(FSegments[I+1].Text), Length(FSegments[I+1].Text)) = 0) then
              Break;
          end;
          Inc(PathIdx);
        end;
      end
      else
      begin
        while (PathIdx <= Length(APath)) and (APath[PathIdx] <> '/') do
          Inc(PathIdx);
      end;
      
      ValueLen := PathIdx - ValueStart;
      if ValueLen = 0 then
        Exit(False);
        
      AParams.AddSlice(Seg.Text, APath, ValueStart, ValueLen);
    end;
  end;
  
  if PathIdx <= Length(APath) then
    Exit(False);
    
  Result := True;
end;

{ TRouteDefinition }

constructor TRouteDefinition.Create(const AMethod, APath: string; AHandler: TRequestDelegate);
begin
  inherited Create;
  FMethod := AMethod;
  FPath := APath;
  FHandler := AHandler;
  
  if APath.Contains('{') then
    FPattern := TRoutePattern.Create(APath)
  else
    FPattern := nil;

  FMetadata.Method := AMethod;
  FMetadata.Path := APath;
end;

destructor TRouteDefinition.Destroy;
begin
  if FPattern <> nil then
  begin
    FPattern.Free;
    FPattern := nil;
  end;
  inherited;
end;

{ TRouteLeaf }

constructor TRouteLeaf.Create(
  const AMethod: string;
  AHandler: TRequestDelegate;
  const AMetadata: TEndpointMetadata
);
begin
  inherited Create;
  Method := AMethod;
  Handler := AHandler;
  Metadata := AMetadata;
end;

{ TRouteNode }

constructor TRouteNode.Create(const ASegment: string);
begin
  inherited Create;
  Segment := ASegment;
  IsParameter := (Length(ASegment) >= 2) and
                 (ASegment[1] = '{') and
                 (ASegment[Length(ASegment)] = '}');
  if IsParameter then
    ParameterName := Copy(ASegment, 2, Length(ASegment) - 2)
  else
    ParameterName := '';
  ParameterChild := nil;
  Children := TCollections.CreateList<TRouteNode>(True);
  Leaves := TCollections.CreateList<TRouteLeaf>(True);
end;

destructor TRouteNode.Destroy;
begin
  Children := nil;
  Leaves := nil;
  inherited;
end;

{ TRouteMatcher }

constructor TRouteMatcher.Create(const ARoutes: IList<TRouteDefinition>);
var
  Route: TRouteDefinition;
  NewRoute: TRouteDefinition;
begin
  inherited Create;
  FRoutes := TCollections.CreateList<TRouteDefinition>(True);
  FRoot := TRouteNode.Create('');
  FExactRoutes := TCollections.CreateDictionary<string,
    IDictionary<string, TRouteLeaf>>(8);

  for Route in ARoutes do
  begin
    NewRoute := TRouteDefinition.Create(
      Route.Method, Route.Path, Route.Handler
    );
    NewRoute.Metadata := Route.Metadata;
    if Length(Route.Metadata.ApiVersions) > 0 then
      FHasVersionedRoutes := True;
    FRoutes.Add(NewRoute);
    AddRouteToTree(NewRoute);
  end;

  FCompiledRoot := CompileRouteNode(FRoot);
end;

destructor TRouteMatcher.Destroy;
begin
  FRoot.Free;
  FExactRoutes := nil;
  FRoutes := nil;
  inherited;
end;

procedure TRouteMatcher.AddRouteToTree(const ARoute: TRouteDefinition);
var
  Path: string;
  Segments: TArray<string>;
  CurrNode: TRouteNode;
  i: Integer;
  FoundChild: TRouteNode;
  Child: TRouteNode;
  Leaf: TRouteLeaf;
  MethodRoutes: IDictionary<string, TRouteLeaf>;
  Found: Boolean;
  Segment: string;
begin
  Path := ARoute.Path;
  if (Length(Path) > 1) and (Path[Length(Path)] = '/') then
    Path := Copy(Path, 1, Length(Path) - 1);
  if (Length(Path) > 0) and (Path[1] = '/') then
    Path := Copy(Path, 2, Length(Path) - 1);

  if Path = '' then
    Segments := nil
  else
    Segments := Path.Split(['/']);

  CurrNode := FRoot;
  for Segment in Segments do
  begin
    Found := False;
    FoundChild := nil;
    for i := 0 to CurrNode.Children.Count - 1 do
    begin
      Child := CurrNode.Children[i];
      if SameText(Child.Segment, Segment) then
      begin
        FoundChild := Child;
        Found := True;
        Break;
      end;
    end;

    if not Found then
    begin
      FoundChild := TRouteNode.Create(Segment);
      CurrNode.Children.Add(FoundChild);
      if FoundChild.IsParameter and (CurrNode.ParameterChild = nil) then
        CurrNode.ParameterChild := FoundChild;
    end;
    CurrNode := FoundChild;
  end;

  Leaf := TRouteLeaf.Create(ARoute.Method, ARoute.Handler, ARoute.Metadata);
  CurrNode.Leaves.Add(Leaf);
  if ARoute.Pattern = nil then
  begin
    if not FExactRoutes.TryGetValue(ARoute.Method, MethodRoutes) then
    begin
      MethodRoutes := TCollections.CreateDictionary<string, TRouteLeaf>;
      FExactRoutes.Add(ARoute.Method, MethodRoutes);
    end;
    MethodRoutes.AddOrSetValue(NormalizeExactRoutePath(ARoute.Path), Leaf);
  end;
end;

function TRouteMatcher.GetRequestedApiVersion(
  const AContext: IHttpContext
): string;
begin
  if AContext.Request.Query.TryGetValue('api-version', Result) then
    Exit;
  if AContext.Request.Headers.TryGetValue('X-Version', Result) then
    Exit;
  Result := '';
end;

function TRouteMatcher.IsVersionMatch(
  const RequestedVersion: string;
  const SupportedVersions: TArray<string>
): Boolean;
var
  V: string;
begin
  if Length(SupportedVersions) = 0 then
    Exit(True);

  if RequestedVersion = '' then
    Exit(False);

  for V in SupportedVersions do
    if SameText(V, RequestedVersion) then
      Exit(True);

  Result := False;
end;

function TRouteMatcher.MatchNodePath(
  Node: TRouteNode;
  const APath: string;
  AStartPos, AEndPos: Integer;
  const AMethod, AVersion: string;
  out ALeaf: TRouteLeaf;
  var AParams: TRouteValueDictionary
): Boolean;
var
  i: Integer;
  Child: TRouteNode;
  SegmentLen: Integer;
  SlashPos: Integer;
  NextPos: Integer;
begin
  if AStartPos > AEndPos then
  begin
    for i := 0 to Node.Leaves.Count - 1 do
    begin
      if (Node.Leaves[i].Method = AMethod) and
         IsVersionMatch(AVersion, Node.Leaves[i].Metadata.ApiVersions) then
      begin
        ALeaf := Node.Leaves[i];
        Exit(True);
      end;
    end;

    for i := 0 to Node.Leaves.Count - 1 do
    begin
      if (Node.Leaves[i].Method = AMethod) and
         (AVersion = '') and
         (Length(Node.Leaves[i].Metadata.ApiVersions) = 0) then
      begin
        ALeaf := Node.Leaves[i];
        Exit(True);
      end;
    end;
    Exit(False);
  end;

  SlashPos := AStartPos;
  while (SlashPos <= AEndPos) and (APath[SlashPos] <> '/') do
    Inc(SlashPos);

  SegmentLen := SlashPos - AStartPos;
  NextPos := SlashPos + 1;

  for i := 0 to Node.Children.Count - 1 do
  begin
    Child := Node.Children[i];
    if (not Child.IsParameter) and
       SamePathSegmentText(APath, AStartPos, SegmentLen, Child.Segment) then
    begin
      if MatchNodePath(
        Child, APath, NextPos, AEndPos, AMethod, AVersion, ALeaf, AParams
      ) then
        Exit(True);
    end;
  end;

  Child := Node.ParameterChild;
  if Child <> nil then
  begin
    if (Length(Child.ParameterName) > 0) and (Child.ParameterName[1] = '*') then
    begin
      // Catch-all parameter: matches everything remaining!
      var CatchAllLen: Integer := AEndPos - AStartPos + 1;
      if MatchNodePath(
        Child, APath, AEndPos + 1, AEndPos, AMethod, AVersion, ALeaf, AParams
      ) then
      begin
        var ParamName: string := Copy(Child.ParameterName, 2, Length(Child.ParameterName) - 1);
        AParams.AddSlice(ParamName, APath, AStartPos, CatchAllLen);
        Exit(True);
      end;
    end
    else
    begin
      if MatchNodePath(
        Child, APath, NextPos, AEndPos, AMethod, AVersion, ALeaf, AParams
      ) then
      begin
        AParams.AddSlice(Child.ParameterName, APath, AStartPos, SegmentLen);
        Exit(True);
      end;
    end;
  end;

  Result := False;
end;

function TRouteMatcher.FindMatchingRoute(
  const AContext: IHttpContext;
  out AHandler: TRequestDelegate;
  out ARouteParams: TRouteValueDictionary;
  out AMetadata: TEndpointMetadata
): Boolean;
var
  Method, Path, RequestVersion: string;
  Leaf: TRouteLeaf;
  StartPos: Integer;
  EndPos: Integer;
  AllowMethods: string;
  AcceptQuery: string;
  ExactPath: string;
  MethodRoutes: IDictionary<string, TRouteLeaf>;
  MatchingRoute: TRouteDefinition;
  i: Integer;
  HasQuery: Boolean;
  CompiledLeaf: TDextCompiledRouteLeaf;
  PathNode: PDextCompiledRouteNode;
begin
  FillChar(ARouteParams, SizeOf(ARouteParams), 0);
  Result := False;
  Method := AContext.Request.Method;
  Path := AContext.Request.Path;
  // Reading the version parses the query string and all the headers into two
  // dictionaries: only worth it when some route is versioned.
  if FHasVersionedRoutes then
    RequestVersion := GetRequestedApiVersion(AContext)
  else
    RequestVersion := '';

  ExactPath := Path;
  if (Length(ExactPath) > 1) and
     (ExactPath[Length(ExactPath)] = '/') then
    ExactPath := Copy(ExactPath, 1, Length(ExactPath) - 1);
  if FExactRoutes.TryGetValue(Method, MethodRoutes) and
     MethodRoutes.TryGetValue(ExactPath, Leaf) and
     IsVersionMatch(RequestVersion, Leaf.Metadata.ApiVersions) then
  begin
    AHandler := Leaf.Handler;
    AMetadata := Leaf.Metadata;
    Result := True;
    Exit;
  end;

  StartPos := 1;
  EndPos := Length(Path);
  if (EndPos > 1) and (Path[EndPos] = '/') then
    Dec(EndPos);
  if (StartPos <= EndPos) and (Path[StartPos] = '/') then
    Inc(StartPos);

  PathNode := FindCompiledPathNode(@FCompiledRoot, Path, StartPos, EndPos);
  if (Method = 'OPTIONS') and (PathNode <> nil) and
     Assigned(PathNode^.OptionsHandler) then
  begin
    AHandler := PathNode^.OptionsHandler;
    AMetadata := PathNode^.OptionsMetadata;
    AMetadata.Path := Path;
    Exit(True);
  end;

  if MatchCompiledNodePath(
    @FCompiledRoot, Path, StartPos, EndPos, Method, RequestVersion,
    CompiledLeaf, ARouteParams
  ) then
  begin
    AHandler := CompiledLeaf.Handler;
    AMetadata := CompiledLeaf.Metadata;
    Result := True;
    Exit;
  end;

  if (PathNode <> nil) and Assigned(PathNode^.MethodNotAllowedHandler) then
  begin
    AHandler := PathNode^.MethodNotAllowedHandler;
    AMetadata := PathNode^.OptionsMetadata;
    AMetadata.Method := Method;
    AMetadata.Path := Path;
    Exit(True);
  end;

  if Method = 'OPTIONS' then
  begin
    AllowMethods := 'OPTIONS';
    AcceptQuery := '';
    HasQuery := False;

    for MatchingRoute in FRoutes do
    begin
      if MatchingRoute.Pattern = nil then
      begin
        if MatchingRoute.Path = AContext.Request.Path then
        begin
          if not AllowMethods.Contains(MatchingRoute.Method) then
            AllowMethods := AllowMethods + ', ' + MatchingRoute.Method;
          if MatchingRoute.Method = 'QUERY' then
          begin
            HasQuery := True;
            if Length(MatchingRoute.Metadata.AcceptQueryTypes) > 0 then
            begin
              for i := 0 to High(MatchingRoute.Metadata.AcceptQueryTypes) do
              begin
                if AcceptQuery <> '' then
                  AcceptQuery := AcceptQuery + ', ';
                AcceptQuery := AcceptQuery +
                  MatchingRoute.Metadata.AcceptQueryTypes[i];
              end;
            end;
          end;
        end;
      end
      else if MatchingRoute.Pattern.Match(Path, ARouteParams) then
      begin
        ARouteParams.Clear;
        if not AllowMethods.Contains(MatchingRoute.Method) then
          AllowMethods := AllowMethods + ', ' + MatchingRoute.Method;
        if MatchingRoute.Method = 'QUERY' then
        begin
          HasQuery := True;
          if Length(MatchingRoute.Metadata.AcceptQueryTypes) > 0 then
          begin
            for i := 0 to High(MatchingRoute.Metadata.AcceptQueryTypes) do
            begin
              if AcceptQuery <> '' then
                AcceptQuery := AcceptQuery + ', ';
              AcceptQuery := AcceptQuery +
                MatchingRoute.Metadata.AcceptQueryTypes[i];
            end;
          end;
        end;
      end;
    end;

    if AllowMethods <> 'OPTIONS' then
    begin
      AHandler := procedure(Ctx: IHttpContext)
        begin
          Ctx.Response.StatusCode := 200;
          Ctx.Response.AddHeader('Allow', AllowMethods);
          if HasQuery then
          begin
            if AcceptQuery = '' then
              AcceptQuery := 'application/json';
            Ctx.Response.AddHeader('Accept-Query', AcceptQuery);
          end;
          Ctx.Response.Write('');
        end;

      AMetadata := Default(TEndpointMetadata);
      AMetadata.Method := 'OPTIONS';
      AMetadata.Path := Path;

      Result := True;
      Exit;
    end;
  end;
end;

end.
