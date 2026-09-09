# HTMX 4 with Dext

`Dext.Web.Htmx` adds the HTMX 4 features that need server awareness without replacing Dext's existing `IHttpResponse.Htmx` response-header API.

## Request inspection

HTMX 4 sends `HX-Request: true` for requests it owns. It also sends `HX-Request-Type` as `partial` or `full`, together with `HX-Source`, `HX-Target`, `HX-Current-URL`, `HX-Boosted`, and (when applicable) `HX-History-Restore-Request`.

```pascal
uses
  Dext.Web.Htmx;

var
  Hx: THtmxRequest;
begin
  Hx := Htmx.Request(Context);

  if Hx.IsPartial then
    Exit(Results.Html(RenderCustomerRows));

  Result := Results.View('customers');
end;
```

`IsPartial` and `IsFull` require both `HX-Request: true` and their matching request-type value. Ordinary browser requests and malformed/unknown request types resolve to `hrtNone`.

The HTMX 4 request type determines whether the client is replacing one target or requesting a full document. If the same URL renders differently for those two cases, configure any HTTP cache to vary appropriately, for example with `Vary: HX-Request-Type`.

## Existing response helpers

The established response API remains the right choice for HTMX response headers:

```pascal
Context.Response.Htmx
  .Trigger('invoice-saved')
  .Retarget('#invoice-grid')
  .Reswap('innerHTML')
  .PushUrl('/invoices/42');
```

## HTMX 4 partial tags

`<hx-partial>` is HTMX 4's native way to update several targets in one response. `Htmx.Partials` returns a reference-counted `IHtmxPartials` builder; return its ordinary Dext `IResult` with no manual `Free`:

```pascal
begin
  Result := Htmx.Partials
    .Target('#invoice-grid', RenderInvoiceRow(Invoice), 'beforeend')
    .Target('#invoice-count', RenderInvoiceCount)
    .Id('toast-area', RenderSuccessToast, 'beforeend')
    .AsResult;
end;
```

That produces markup equivalent to:

```html
<hx-partial hx-target="#invoice-grid" hx-swap="beforeend">...</hx-partial>
<hx-partial hx-target="#invoice-count">...</hx-partial>
<hx-partial id="toast-area" hx-swap="beforeend">...</hx-partial>
```

`Target` emits `hx-target`; `Id` emits HTMX 4's shorthand `id`. The supplied HTML is deliberately passed through as markup, while target and swap attribute values are HTML-escaped in a single pass.

## Streaming

This package does not introduce a new SSE, WebSocket, or multipart transport. Dext's existing SSE and WebSocket capabilities continue to supply the transport; HTMX 4's `hx-sse`, `hx-ws`, and `hx-multipart` extensions consume the server's HTML fragments.

Sources: [HTMX 4 documentation](https://four.htmx.org/docs/), [request headers](https://four.htmx.org/reference/headers/HX-Request-Type).
