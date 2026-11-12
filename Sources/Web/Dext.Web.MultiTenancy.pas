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
{***************************************************************************}
unit Dext.Web.MultiTenancy;

interface

uses
  System.SysUtils, System.Classes, System.Rtti,
  Dext.Web.Interfaces, Dext.DI.Interfaces, Dext.Web.Middleware,
  Dext.Web.Builder, Dext.MultiTenancy;

type
  /// <summary>
  ///   Strategy to resolve the tenant ID from the HTTP context (e.g. Host, Header, Query).
  /// </summary>
  ITenantResolutionStrategy = interface
    ['{C8E9D0A1-B2F3-4C5D-6E7F-8A9B0C1D2E3F}']
    function Resolve(const AContext: IHttpContext): string;
  end;

  /// <summary>
  ///   Tenant metadata repository.
  /// </summary>
  ITenantStore = interface
    ['{631320AF-1279-4684-9075-C66946D58AEB}']
    function GetTenant(const AId: string): ITenant;
  end;

  /// <summary>
  ///   Middleware responsible for identifying the current tenant and injecting it into the pipeline and DI container.
  /// </summary>
  TMultiTenancyMiddleware = class(TMiddleware)
  private
    FStrategy: ITenantResolutionStrategy;
    FStore: ITenantStore;
    FRequireTenant: Boolean;
  public
    constructor Create(const AStrategy: ITenantResolutionStrategy; const AStore: ITenantStore);
    procedure Invoke(AContext: IHttpContext; ANext: TRequestDelegate); override;
    /// <summary>
    ///   When True (the default), a request whose tenant identifier is missing
    ///   is answered with 400, and one whose identifier the store does not know
    ///   with 404, and the pipeline stops there. With False the request goes on
    ///   with no tenant, and the context then applies no tenant filter.
    /// </summary>
    property RequireTenant: Boolean read FRequireTenant write FRequireTenant;
  end;

implementation

uses
  Dext.Web.Results;

{ TMultiTenancyMiddleware }

constructor TMultiTenancyMiddleware.Create(const AStrategy: ITenantResolutionStrategy; const AStore: ITenantStore);
begin
  inherited Create;
  FStrategy := AStrategy;
  FStore := AStore;
  FRequireTenant := True;
end;

procedure TMultiTenancyMiddleware.Invoke(AContext: IHttpContext; ANext: TRequestDelegate);
var
  LTenantId: string;
  LTenant: ITenant;
  LProvider: ITenantProvider;
begin
  LTenant := nil;
  if FStrategy <> nil then
  begin
    LTenantId := FStrategy.Resolve(AContext);
    if (LTenantId <> '') and (FStore <> nil) then
      LTenant := FStore.GetTenant(LTenantId);
  end
  else
    LTenantId := '';

  if LTenant = nil then
  begin
    if FRequireTenant then
    begin
      if LTenantId = '' then
        Results.BadRequest('Tenant identifier is required.').Execute(AContext)
      else
        Results.NotFound('Unknown tenant.').Execute(AContext);
      Exit;
    end;
  end
  else
  begin
    // Store in Context Items for easy access in views/controllers
    AContext.Items.AddOrSetValue('Tenant', TValue.From<ITenant>(LTenant));

    // Populate ITenantProvider if registered (Scoped service)
    if Supports(AContext.Services.GetServiceAsInterface(
      TServiceType.FromInterface(TypeInfo(ITenantProvider))),
      ITenantProvider, LProvider) then
      LProvider.Tenant := LTenant;
  end;

  ANext(AContext);
end;

end.
