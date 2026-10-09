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
unit Dext.Web.Builder;

interface

uses
  System.SysUtils,
  System.Rtti,
  System.TypInfo,
  Dext.DI.Interfaces,
  Dext.Web.HandlerInvoker,
  Dext.Core.Activator,
  Dext.Web.Interfaces,
  Dext.Collections,
  Dext.Collections.Dict,
  Dext.Web.Routing;

type
  /// <summary>
  ///   Internal registration of a middleware in the pipeline.
  /// </summary>
  TMiddlewareRegistration = record
    MiddlewareClass: TClass;
    MiddlewareDelegate: TMiddlewareDelegate;
    MiddlewareInstance: IMiddleware; // Singleton Instance
    Parameters: TArray<TValue>;
    IsDelegate: Boolean;
    IsInstance: Boolean; // Flag for Singleton
  end;

  TAnonymousMiddleware = class(TInterfacedObject, IMiddleware)
  private
    FDelegate: TMiddlewareDelegate;
  public
    constructor Create(ADelegate: TMiddlewareDelegate);
    procedure Invoke(AContext: IHttpContext; ANext: TRequestDelegate);
  end;

  /// <summary>
  ///   Default implementation of the web application builder. 
  ///   Manages middleware registration and the construction of the Request Pipeline.
  /// </summary>
  TApplicationBuilder = class(TInterfacedObject, IApplicationBuilder)
  private
    FMiddlewares: IList<TMiddlewareRegistration>;
    FRoutes: IList<TRouteDefinition>; // Changed to List of Definitions
    FServiceProvider: IServiceProvider;
    FDisposables: IList<TObject>; // Objects to dispose on shutdown

    function CreateMiddlewarePipeline(const ARegistration: TMiddlewareRegistration; ANext: TRequestDelegate): TRequestDelegate;
  public
    constructor Create(AServiceProvider: IServiceProvider);
    destructor Destroy; override;
    function GetServiceProvider: IServiceProvider;

    function UseMiddleware(AMiddleware: TClass): IApplicationBuilder; overload;
    function UseMiddleware(AMiddleware: TClass; const AParam: TValue): IApplicationBuilder; overload;
    function UseMiddleware(AMiddleware: TClass; const AParams: array of TValue): IApplicationBuilder; overload;
    function UseMiddleware(AMiddleware: IMiddleware): IApplicationBuilder; overload; // Singleton
    
    // Functional Middleware
    function Use(AMiddleware: TMiddlewareDelegate): IApplicationBuilder;

    function UseModelBinding: IApplicationBuilder;

    function Map(const APath: string; ADelegate: TRequestDelegate): IApplicationBuilder;
    function MapEndpoint(const AMethod, APath: string; ADelegate: TRequestDelegate): IApplicationBuilder; // NEW
    function MapPost(const Path: string; Handler: TStaticHandler): IApplicationBuilder; overload;
    function MapGet(const Path: string; Handler: TStaticHandler): IApplicationBuilder; overload;
    function MapPut(const Path: string; Handler: TStaticHandler): IApplicationBuilder; overload;
    function MapDelete(const Path: string; Handler: TStaticHandler): IApplicationBuilder; overload;
    function MapQuery(const Path: string; Handler: TStaticHandler): IApplicationBuilder; overload;
    function MapFast(const AMethod, APath: string; AHandler: TDextFastRouteHandler): IApplicationBuilder; overload;
    function MapFast(const APath: string; AHandler: TDextFastRouteHandler): IApplicationBuilder; overload;
    function Build: TRequestDelegate;
    function GetRoutes: TArray<TEndpointMetadata>;
    procedure UpdateLastRouteMetadata(const AMetadata: TEndpointMetadata);
    procedure SetServiceProvider(const AProvider: IServiceProvider);
    procedure RegisterForDisposal(AObject: TObject);
  end;

  /// <summary>
  ///   Base administrative class for creating structured middlewares.
  ///   Implement <see cref="Invoke"/> to add logic to the request flow.
  /// </summary>
  TMiddleware = class(TInterfacedObject, IMiddleware)
  public
    /// <summary>Method executed during the pipeline. Call ANext(AContext) to proceed to the next middleware.</summary>
    procedure Invoke(AContext: IHttpContext; ANext: TRequestDelegate); virtual; abstract;
  end;

implementation

uses
  System.Math,
  System.JSON,
  System.Diagnostics,
  Dext.Logging.Telemetry,
  Dext.Web.ModelBinding,
  Dext.Web.Indy,
  Dext.Web.Pipeline,
  Dext.Web.RoutingMiddleware;

{ TAnonymousMiddleware }

constructor TAnonymousMiddleware.Create(ADelegate: TMiddlewareDelegate);
begin
  inherited Create;
  FDelegate := ADelegate;
end;

procedure TAnonymousMiddleware.Invoke(AContext: IHttpContext; ANext: TRequestDelegate);
begin
  FDelegate(AContext, ANext);
end;

function TApplicationBuilder.Use(AMiddleware: TMiddlewareDelegate): IApplicationBuilder;
var
  Registration: TMiddlewareRegistration;
begin
  Registration.IsDelegate := True;
  Registration.IsInstance := False; // Initialize explicitly
  Registration.MiddlewareDelegate := AMiddleware;
  Registration.MiddlewareInstance := nil; // Initialize explicitly
  Registration.MiddlewareClass := nil;
  SetLength(Registration.Parameters, 0);
  
  FMiddlewares.Add(Registration);
  Result := Self;
end;

function TApplicationBuilder.CreateMiddlewarePipeline(const ARegistration: TMiddlewareRegistration;
  ANext: TRequestDelegate): TRequestDelegate;
var
  ServiceProvider: IServiceProvider;
  Registration: TMiddlewareRegistration; // Capture copy
begin
  ServiceProvider := FServiceProvider;
  Registration := ARegistration; // Copy record to local var for closure capture

  Result :=
    procedure(AContext: IHttpContext)
    var
      MiddlewareInstance: IMiddleware;
      Obj: TObject;
    begin
      if Registration.IsDelegate then
      begin
        // Handle Anonymous Middleware
        MiddlewareInstance := TAnonymousMiddleware.Create(Registration.MiddlewareDelegate);
      end
      else if Registration.IsInstance then
      begin
        // Handle Singleton Middleware
        MiddlewareInstance := Registration.MiddlewareInstance;
      end
      else
      begin
        // Handle Class Middleware
        Obj := TActivator.CreateInstance(ServiceProvider, Registration.MiddlewareClass, Registration.Parameters);
        try
          if not Supports(Obj, IMiddleware, MiddlewareInstance) then
            raise EArgumentException.Create('Middleware must implement IMiddleware');
        except
          Obj.Free;
          raise;
        end;
      end;

      try
        if MiddlewareInstance = nil then
          raise EAccessViolation.Create('MiddlewareInstance is nil');

        MiddlewareInstance.Invoke(AContext, ANext);
      finally
        // Cleanup
      end;
    end;
end;

{ TApplicationBuilder }

constructor TApplicationBuilder.Create(AServiceProvider: IServiceProvider);
begin
  inherited Create;
  FServiceProvider := AServiceProvider;
  FMiddlewares := TCollections.CreateList<TMiddlewareRegistration>;
  FRoutes := TCollections.CreateList<TRouteDefinition>(True); // Added True to own objects
  FDisposables := TCollections.CreateObjectList<TObject>(True);
end;

destructor TApplicationBuilder.Destroy;
begin
  FDisposables := nil;
  FMiddlewares := nil;
  FRoutes := nil;
  FServiceProvider := nil;

  // Dispose all registered objects handled by ObjectList
  // FDisposables is ARC
  inherited Destroy;
end;

function TApplicationBuilder.GetServiceProvider: IServiceProvider;
begin
  Result := FServiceProvider;
end;

function TApplicationBuilder.UseMiddleware(AMiddleware: TClass; const AParam: TValue): IApplicationBuilder;
var
  Registration: TMiddlewareRegistration;
begin
  if not Supports(AMiddleware, IMiddleware) then
    raise EArgumentException.Create('Middleware must supports IMiddleware');

  Registration.MiddlewareClass := AMiddleware;
  Registration.IsDelegate := False;
  Registration.IsInstance := False; // Initialize explicitly
  Registration.MiddlewareDelegate := nil;
  Registration.MiddlewareInstance := nil; // Initialize explicitly
  SetLength(Registration.Parameters, 1);
  Registration.Parameters[0] := AParam;

  FMiddlewares.Add(Registration);

  Result := Self;
end;

function TApplicationBuilder.UseMiddleware(AMiddleware: TClass; const AParams: array of TValue): IApplicationBuilder;
var
  Registration: TMiddlewareRegistration;
  I: Integer;
begin
  if not AMiddleware.InheritsFrom(TMiddleware) then
    raise EArgumentException.Create('Middleware must inherit from TMiddleware');

  Registration.MiddlewareClass := AMiddleware;
  Registration.IsDelegate := False;
  Registration.IsInstance := False; // Initialize explicitly
  Registration.MiddlewareDelegate := nil;
  Registration.MiddlewareInstance := nil; // Initialize explicitly
  SetLength(Registration.Parameters, Length(AParams));

  for I := 0 to High(AParams) do
    Registration.Parameters[I] := AParams[I];

  FMiddlewares.Add(Registration);
  Result := Self;
end;

function TApplicationBuilder.UseMiddleware(AMiddleware: IMiddleware): IApplicationBuilder;
var
  Registration: TMiddlewareRegistration;
begin
  Registration.MiddlewareClass := nil;
  Registration.IsDelegate := False;
  Registration.IsInstance := True;
  Registration.MiddlewareInstance := AMiddleware;
  Registration.MiddlewareDelegate := nil;
  SetLength(Registration.Parameters, 0);

  FMiddlewares.Add(Registration);
  
  Result := Self;
end;

function TApplicationBuilder.UseModelBinding: IApplicationBuilder;
begin
  // For now just returns self - can add future configs
  // such as binding options, validators, etc.
  Result := Self;
end;



function TApplicationBuilder.UseMiddleware(AMiddleware: TClass): IApplicationBuilder;
var
  Registration: TMiddlewareRegistration;
begin
  if not AMiddleware.InheritsFrom(TMiddleware) then
    raise EArgumentException.Create('Middleware must inherit from TMiddleware');

  // Create registration without parameters
  Registration.MiddlewareClass := AMiddleware;
  Registration.IsDelegate := False;
  Registration.IsInstance := False; // Initialize explicitly
  Registration.MiddlewareDelegate := nil;
  Registration.MiddlewareInstance := nil; // Initialize explicitly
  SetLength(Registration.Parameters, 0); // Empty array

  FMiddlewares.Add(Registration);
  Result := Self;
end;

function TApplicationBuilder.MapEndpoint(const AMethod, APath: string; ADelegate: TRequestDelegate): IApplicationBuilder;
var
  RouteDef: TRouteDefinition;
begin
  RouteDef := TRouteDefinition.Create(AMethod, APath, ADelegate);
  FRoutes.Add(RouteDef);
  Result := Self;
end;

function TApplicationBuilder.Map(const APath: string;
  ADelegate: TRequestDelegate): IApplicationBuilder;
begin
  // Default to GET for legacy Map calls
  Result := MapEndpoint('GET', APath, ADelegate);
end;

function TApplicationBuilder.MapGet(const Path: string; Handler: TStaticHandler): IApplicationBuilder;
begin
  Result := MapEndpoint('GET', Path,
    procedure(Context: IHttpContext)
    begin
      Handler(Context);
    end
  );
end;

function TApplicationBuilder.MapPost(const Path: string; Handler: TStaticHandler): IApplicationBuilder;
begin
  Result := MapEndpoint('POST', Path,
    procedure(Context: IHttpContext)
    begin
      Handler(Context);
    end
  );
end;

function TApplicationBuilder.MapPut(const Path: string; Handler: TStaticHandler): IApplicationBuilder;
begin
  Result := MapEndpoint('PUT', Path,
    procedure(Context: IHttpContext)
    begin
      Handler(Context);
    end
  );
end;

function TApplicationBuilder.MapDelete(const Path: string; Handler: TStaticHandler): IApplicationBuilder;
begin
  Result := MapEndpoint('DELETE', Path,
    procedure(Context: IHttpContext)
    begin
      Handler(Context);
    end
  );
end;

function TApplicationBuilder.MapQuery(const Path: string; Handler: TStaticHandler): IApplicationBuilder;
begin
  Result := MapEndpoint('QUERY', Path,
    procedure(Context: IHttpContext)
    begin
      Handler(Context);
    end
  );
end;

function TApplicationBuilder.MapFast(const AMethod, APath: string; AHandler: TDextFastRouteHandler): IApplicationBuilder;
begin
  Result := MapEndpoint(AMethod, APath,
    procedure(Context: IHttpContext)
    begin
      AHandler(Context.Request, Context.Response);
    end
  );
end;

function TApplicationBuilder.MapFast(const APath: string; AHandler: TDextFastRouteHandler): IApplicationBuilder;
begin
  Result := MapFast('GET', APath, AHandler);
end;

// ---------------------------------------------------------------------------
// Helper Class to avoid Anonymous Method ActRec leaks
type
  IRoutingHandlerHelper = interface
    ['{19A95C1C-5C7F-4B8E-9C3E-8F3E5C7F4B8E}']
    procedure Invoke(Ctx: IHttpContext);
  end;

  TRoutingHandlerHelper = class(TInterfacedObject, IRoutingHandlerHelper)
  private
    FMw: IMiddleware;
    FNext: TRequestDelegate;
  public
    constructor Create(const Mw: IMiddleware; const Next: TRequestDelegate);
    destructor Destroy; override;
    procedure Invoke(Ctx: IHttpContext);
  end;

constructor TRoutingHandlerHelper.Create(const Mw: IMiddleware; const Next: TRequestDelegate);
begin
  inherited Create;
  FMw := Mw;
  FNext := Next;
end;

destructor TRoutingHandlerHelper.Destroy;
begin
  inherited;
end;

procedure TRoutingHandlerHelper.Invoke(Ctx: IHttpContext);
begin
  FMw.Invoke(Ctx, FNext);
end;

// Helper function to isolate capture scope and avoid ActRec cycles
function CreateRoutingDelegate(const Mw: IMiddleware; const Next: TRequestDelegate): TRequestDelegate;
var
  Helper: IRoutingHandlerHelper;
begin
  Helper := TRoutingHandlerHelper.Create(Mw, Next);
  Result := 
    procedure(Ctx: IHttpContext)
    begin
      Helper.Invoke(Ctx);
    end;
end;

// Helper function to wrap pipeline with telemetry without capturing Build's stack/Self
function CreateTelemetryDelegate(const Pipeline: TRequestDelegate): TRequestDelegate;
begin
  Result := 
    procedure(AContext: IHttpContext)
    var
      Watch: TStopwatch;
      Data: TJSONObject;
    begin
      // Nobody listening (the common case): no event to build. Building it
      // anyway cost two Now calls and a TJSONObject with three pairs --
      // 15 allocations -- on every request, only for Write to free it.
      if not TDiagnosticSource.Instance.IsActive then
      begin
        Pipeline(AContext);
        Exit;
      end;
      Watch := TStopwatch.StartNew;
      try
        Pipeline(AContext);
      finally
        Data := TJSONObject.Create;
        try
          Data.AddPair('Method', AContext.Request.Method);
          Data.AddPair('Path', AContext.Request.Path);
          Data.AddPair('StatusCode', TJSONNumber.Create(AContext.Response.StatusCode));
          
          TDiagnosticSource.Instance.Write('HTTP.Request', Data, 'HTTP', Watch.ElapsedMilliseconds);
        except
          Data.Free;
        end;
      end;
    end;
end;

function TApplicationBuilder.Build: TRequestDelegate;
var
  FinalPipeline: TRequestDelegate;
  RoutingMiddleware: IMiddleware;
  RouteMatcher: IRouteMatcher;
  RoutingHandler: TRequestDelegate;
  I: Integer;
begin
  // Final pipeline - returns 404
  FinalPipeline :=
    procedure(AContext: IHttpContext)
    begin
      AContext.Response.NotFound('Not Found');
    end;

  // Create RouteMatcher (interface - self-managed)
  RouteMatcher := TRouteMatcher.Create(FRoutes);

  // Create RoutingMiddleware with the interface
  RoutingMiddleware := TRoutingMiddleware.Create(RouteMatcher);

  // USE ISOLATED FUNCTION to create the delegate
  // This prevents the delegate from capturing local variables of this Build method
  RoutingHandler := CreateRoutingDelegate(RoutingMiddleware, FinalPipeline);

  // Build pipeline: other middlewares -> routing -> 404
  for I := FMiddlewares.Count - 1 downto 0 do
  begin
    RoutingHandler := CreateMiddlewarePipeline(FMiddlewares[I], RoutingHandler);
  end;

  // Wrap final pipeline with telemetry using isolated function to break Self capture
  Result := CreateTelemetryDelegate(RoutingHandler);
end;


function TApplicationBuilder.GetRoutes: TArray<TEndpointMetadata>;
var
  I: Integer;
begin
  SetLength(Result, FRoutes.Count);
  for I := 0 to FRoutes.Count - 1 do
    Result[I] := FRoutes[I].Metadata;
end;

procedure TApplicationBuilder.UpdateLastRouteMetadata(const AMetadata: TEndpointMetadata);
begin
  if FRoutes.Count > 0 then
  begin
    FRoutes[FRoutes.Count - 1].Metadata := AMetadata;
  end;
end;

procedure TApplicationBuilder.SetServiceProvider(const AProvider: IServiceProvider);
begin
  FServiceProvider := AProvider;
end;

procedure TApplicationBuilder.RegisterForDisposal(AObject: TObject);
begin
  if Assigned(AObject) and (FDisposables.IndexOf(AObject) < 0) then
    FDisposables.Add(AObject);
end;

end.


