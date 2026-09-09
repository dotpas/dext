# Web.Htmx4Demo — HTMX 4 multi-target partials

Dext + HTMX 4 (`Dext.Web.Htmx`) demo served by the native server engine.

## Run

```text
dot: build Examples\07-UseCases\Web.Htmx4Demo\Web.Htmx4Demo.dproj (Win32) and run
URL: http://localhost:5299/
```

## What it shows

- `GET /` — dashboard page loading htmx 4 from the CDN (SRI-pinned).
- `GET /invoices` — branches on `Htmx.Request(Context).IsPartial`:
  - **partial** (default element target): one response with two `<hx-partial>`
    elements — `hx-target="#invoice-grid"` and the `id="invoice-count"` shorthand.
    Both targets update from a single response.
  - **full** (`hx-target="body"` sends `HX-Request-Type: full`): the whole page.
- `GET /invoices/append` — appends a row with `hx-swap="beforeend"` and refreshes
  the counter, again with two partials in one response.

Sources: [HTMX 4 docs](https://four.htmx.org/docs/), [HX-Request-Type](https://four.htmx.org/reference/headers/HX-Request-Type).
