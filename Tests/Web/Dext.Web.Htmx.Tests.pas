unit Dext.Web.Htmx.Tests;

interface

uses
  System.SysUtils,
  Dext.Testing.Attributes,
  Dext.Assertions,
  Dext.Testing.WebApplicationFactory,
  Dext.Web,
  Dext.Web.Interfaces,
  Dext.Web.Results,
  Dext.Web.Htmx,
  Dext.Web.Mocks,
  Dext.Collections.Dict,
  Dext.Collections;

type
  [TestFixture('HTMX Fluent Response Tests (S23)')]
  THtmxResponseTests = class
  public
    [Test('Should set HX-Trigger header')]
    procedure TestTrigger;

    [Test('Should set HX-Retarget header')]
    procedure TestRetarget;

    [Test('Should set HX-Reswap header')]
    procedure TestReswap;

    [Test('Should set HX-Redirect header')]
    procedure TestRedirect;

    [Test('Should set HX-Refresh header')]
    procedure TestRefresh;

    [Test('Should set HX-Push-Url header')]
    procedure TestPushUrl;

    [Test('Should set HX-Replace-Url header')]
    procedure TestReplaceUrl;

    [Test('Should set HX-Location header')]
    procedure TestLocation;

    [Test('Should allow chaining multiple HTMX headers')]
    procedure TestChaining;

    [Test('Should inspect HTMX 4 partial request headers')]
    procedure TestHtmx4PartialRequest;

    [Test('Should inspect HTMX 4 full request headers case-insensitively')]
    procedure TestHtmx4FullRequest;

    [Test('Should inspect HTMX 4 partial request with mixed-case header values')]
    procedure TestHtmx4PartialRequestMixedCase;

    [Test('Should treat regular requests as non-HTMX')]
    procedure TestHtmx4RegularRequest;

    [Test('Should build multiple HTMX 4 partial tags')]
    procedure TestHtmx4Partials;

    [Test('Should escape HTMX 4 partial attributes')]
    procedure TestHtmx4PartialAttributeEscaping;

    [Test('Should return a Dext HTML result with all partial tags (integration)')]
    procedure TestHtmx4AsResultIntegration;
  end;

implementation

{ THtmxResponseTests }

procedure THtmxResponseTests.TestTrigger;
var
  Response: IHttpResponse;
begin
  Response := TMockHttpResponse.Create;

  Response.Htmx.Trigger('myEvent');

  Should(Response.Headers['HX-Trigger']).Be('myEvent');
end;

procedure THtmxResponseTests.TestRetarget;
var
  Response: IHttpResponse;
begin
  Response := TMockHttpResponse.Create;

  Response.Htmx.Retarget('#target');

  Should(Response.Headers['HX-Retarget']).Be('#target');
end;

procedure THtmxResponseTests.TestReswap;
var
  Response: IHttpResponse;
begin
  Response := TMockHttpResponse.Create;

  Response.Htmx.Reswap('outerHTML');

  Should(Response.Headers['HX-Reswap']).Be('outerHTML');
end;

procedure THtmxResponseTests.TestRedirect;
var
  Response: IHttpResponse;
begin
  Response := TMockHttpResponse.Create;

  Response.Htmx.Redirect('/new-path');

  Should(Response.Headers['HX-Redirect']).Be('/new-path');
end;

procedure THtmxResponseTests.TestRefresh;
var
  Response: IHttpResponse;
begin
  Response := TMockHttpResponse.Create;

  Response.Htmx.Refresh;

  Should(Response.Headers['HX-Refresh']).Be('true');
end;

procedure THtmxResponseTests.TestPushUrl;
var
  Response: IHttpResponse;
begin
  Response := TMockHttpResponse.Create;

  Response.Htmx.PushUrl('/new-url');

  Should(Response.Headers['HX-Push-Url']).Be('/new-url');
end;

procedure THtmxResponseTests.TestReplaceUrl;
var
  Response: IHttpResponse;
begin
  Response := TMockHttpResponse.Create;

  Response.Htmx.ReplaceUrl('/replaced-url');

  Should(Response.Headers['HX-Replace-Url']).Be('/replaced-url');
end;

procedure THtmxResponseTests.TestLocation;
var
  Response: IHttpResponse;
begin
  Response := TMockHttpResponse.Create;

  Response.Htmx.Location('/location');

  Should(Response.Headers['HX-Location']).Be('/location');
end;

procedure THtmxResponseTests.TestChaining;
var
  Response: IHttpResponse;
begin
  Response := TMockHttpResponse.Create;

  Response.Htmx
    .Trigger('event1')
    .Retarget('#div1')
    .Reswap('innerHTML');

  Should(Response.Headers['HX-Trigger']).Be('event1');
  Should(Response.Headers['HX-Retarget']).Be('#div1');
  Should(Response.Headers['HX-Reswap']).Be('innerHTML');
end;

procedure THtmxResponseTests.TestHtmx4PartialRequest;
var
  Context: IHttpContext;
  Headers: IStringDictionary;
  Request: THtmxRequest;
begin
  Headers := TCollections.CreateStringDictionary(True);
  Headers.AddOrSetValue('HX-Request', 'true');
  Headers.AddOrSetValue('HX-Request-Type', 'partial');
  Headers.AddOrSetValue('HX-Source', 'button#save');
  Headers.AddOrSetValue('HX-Target', 'div#invoice-grid');
  Headers.AddOrSetValue('HX-Current-URL', 'https://example.test/invoices/42');
  Headers.AddOrSetValue('HX-Boosted', 'true');
  Headers.AddOrSetValue('HX-History-Restore-Request', 'true');
  Context := TMockFactory.CreateHttpContextWithHeaders('', Headers);

  Request := Htmx.Request(Context);

  Should(Request.IsHtmx).BeTrue;
  Should(Request.IsPartial).BeTrue;
  Should(Request.IsFull).BeFalse;
  Should(Request.RequestType = hrtPartial).BeTrue;
  Should(Request.Source).Be('button#save');
  Should(Request.Target).Be('div#invoice-grid');
  Should(Request.CurrentUrl).Be('https://example.test/invoices/42');
  Should(Request.IsBoosted).BeTrue;
  Should(Request.IsHistoryRestore).BeTrue;
end;

procedure THtmxResponseTests.TestHtmx4FullRequest;
var
  Context: IHttpContext;
  Headers: IStringDictionary;
  Request: THtmxRequest;
begin
  Headers := TCollections.CreateStringDictionary(True);
  Headers.AddOrSetValue('hx-request', 'TRUE');
  Headers.AddOrSetValue('hx-request-type', 'FULL');
  Context := TMockFactory.CreateHttpContextWithHeaders('', Headers);

  Request := Htmx.Request(Context);

  Should(Request.IsHtmx).BeTrue;
  Should(Request.IsPartial).BeFalse;
  Should(Request.IsFull).BeTrue;
  Should(Request.RequestType = hrtFull).BeTrue;
end;

procedure THtmxResponseTests.TestHtmx4RegularRequest;
var
  Context: IHttpContext;
  Headers: IStringDictionary;
  Request: THtmxRequest;
begin
  Headers := TCollections.CreateStringDictionary(True);
  Headers.AddOrSetValue('HX-Request-Type', 'partial');
  Context := TMockFactory.CreateHttpContextWithHeaders('', Headers);

  Request := Htmx.Request(Context);

  Should(Request.IsHtmx).BeFalse;
  Should(Request.IsPartial).BeFalse;
  Should(Request.IsFull).BeFalse;
  Should(Request.RequestType = hrtNone).BeTrue;
end;

procedure THtmxResponseTests.TestHtmx4Partials;
var
  Partials: IHtmxPartials;
  Html: string;
begin
  Partials := Htmx.Partials;
  Html := Partials
    .Target('#invoice-grid', '<tr><td>INV-42</td></tr>', 'beforeend')
    .Target('#invoice-count', '<span>42</span>')
    .Id('toast-area', '<div>Saved</div>', 'beforeend')
    .Id('inline-note', '<em>synced</em>')
    .ToHtml;

  Should(Html).Be(
    '<hx-partial hx-target="#invoice-grid" hx-swap="beforeend"><tr><td>INV-42</td></tr></hx-partial>' + sLineBreak +
    '<hx-partial hx-target="#invoice-count"><span>42</span></hx-partial>' + sLineBreak +
    '<hx-partial id="toast-area" hx-swap="beforeend"><div>Saved</div></hx-partial>' + sLineBreak +
    '<hx-partial id="inline-note"><em>synced</em></hx-partial>'
  );
  Should(Partials.AsResult <> nil).BeTrue;
end;

procedure THtmxResponseTests.TestHtmx4PartialAttributeEscaping;
begin
  Should(Htmx.Partials.Target('#a&"<>', '<div>safe markup</div>', 'before&"<>').ToHtml).Be(
    '<hx-partial hx-target="#a&amp;&quot;&lt;&gt;" hx-swap="before&amp;&quot;&lt;&gt;"><div>safe markup</div></hx-partial>'
  );
end;

procedure THtmxResponseTests.TestHtmx4PartialRequestMixedCase;
var
  Context: IHttpContext;
  Headers: IStringDictionary;
  Request: THtmxRequest;
begin
  Headers := TCollections.CreateStringDictionary(True);
  Headers.AddOrSetValue('hx-request', 'True');
  Headers.AddOrSetValue('HX-REQUEST-TYPE', 'PARTIAL');
  Context := TMockFactory.CreateHttpContextWithHeaders('', Headers);

  Request := Htmx.Request(Context);

  Should(Request.IsHtmx).BeTrue;
  Should(Request.IsPartial).BeTrue;
  Should(Request.IsFull).BeFalse;
  Should(Request.RequestType = hrtPartial).BeTrue;
end;

procedure THtmxResponseTests.TestHtmx4AsResultIntegration;
var
  Factory: TDextApplicationFactory<TObject>;
  Client: IDextTestHttpClient;
  Response: IDextTestHttpResponse;
begin
  Factory := TDextApplicationFactory<TObject>.Create
    .WithConfigure(
      procedure(App: TWebApplication)
      begin
        App.Builder.MapGet('/htmx4/invoices',
          procedure(Ctx: IHttpContext)
          begin
            if Htmx.Request(Ctx).IsPartial then
            begin
              Htmx.Partials
                .Target('#invoice-grid', '<tr><td>INV-7</td></tr>', 'innerHTML')
                .Id('invoice-count', '<span>7 invoices</span>')
                .AsResult.Execute(Ctx);
              Exit;
            end;

            Results.Html(
              '<!DOCTYPE html><html><body><h1>Invoices</h1></body></html>').Execute(Ctx);
          end);
      end);
  try
    Client := Factory.CreateClient;

    Response := Client
      .Header('HX-Request', 'true')
      .Header('HX-Request-Type', 'partial')
      .Get('/htmx4/invoices');
    Should(Response.StatusCode).Be(200);
    Should(Response.ContentType).Contain('text/html');
    Should(Response.Body).Contain(
      '<hx-partial hx-target="#invoice-grid" hx-swap="innerHTML"><tr><td>INV-7</td></tr></hx-partial>');
    Should(Response.Body).Contain(
      '<hx-partial id="invoice-count"><span>7 invoices</span></hx-partial>');

    Response := Client
      .Header('HX-Request', 'true')
      .Header('HX-Request-Type', 'full')
      .Get('/htmx4/invoices');
    Should(Response.StatusCode).Be(200);
    Should(Response.Body).Contain('<h1>Invoices</h1>');
    Should(Response.Body).NotContain('<hx-partial>');
  finally
    Factory.Free;
  end;
end;

end.
