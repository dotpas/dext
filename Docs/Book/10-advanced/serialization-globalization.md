# Serialization & Globalization

The Dext Framework is designed to be "safe by default" when handling data exchange across different locales and systems. This chapter covers how Dext manages format settings, JSON serialization, and date parsing.

## Invariant Culture by Default

Delphi's standard `FloatToStr` and `StrToFloat` functions use the OS's regional settings (e.g., using a comma `,` as a decimal separator in Brazil or Germany). This can break JSON payloads and database queries that expect a dot `.` separator.

Dext forces the use of `TFormatSettings.Invariant` in all core serialization units:

- **JSON Serialization**: `Dext.Json` and `Dext.Json.Utf8` always use `.` for numbers.
- **Web Headers**: Quality values (`q=0.8`) and cookie expiry dates are formatted using invariant settings.
- **Database Conversions**: Internal type converters prioritize invariant parsing to avoid "Invalid float" errors on servers.

## Date & Time Parsing

Dext provides a robust utility for parsing dates from various sources (HTTP headers, JSON strings, CSV files) via the `Dext.Core.DateUtils` unit.

### `TryParseCommonDate`

The `TryParseCommonDate` function attempts to parse a string using a sequence of formats:
1. **ISO 8601** (e.g., `2025-12-25T10:00:00Z`)
2. **System Default** (Current OS format)
3. **Common Formats** (`dd/mm/yyyy`, `mm/dd/yyyy`, `yyyy-mm-dd`)

```pascal
uses Dext.Core.DateUtils;

var
  LDate: TDateTime;
begin
  // ISO 8601
  if TryParseCommonDate('2025-12-25T15:30:00', LDate) then ...
  
  // Locale-specific (dd/mm/yyyy or mm/dd/yyyy depending on OS)
  if TryParseCommonDate('25/12/2025', LDate) then ...
end;
```

### Overloading with FormatSettings

Since Version 1.1, you can pass specific `TFormatSettings` to the parser if you are handling data from a specific known source:

```pascal
var
  GermanFS: TFormatSettings;
begin
  GermanFS := TFormatSettings.Create('de-DE');
  if TryParseCommonDate('25.12.2025', LDate, GermanFS) then
    Log('Parsed German date!');
end;
```

## JSON Hydration and Dates

In the `TEntityDataSet` and JSON mapping system, Dext automatically handles date conversions from JSON strings. It uses `TryParseISODateTime` internally, ensuring that:

- `TDateTime` properties get the full timestamp.
- `TDate` properties get the truncated date part.
- `TTime` properties get the fractional time part.

### The format of dates in JSON

Every serializer (`TDextJson`, the UTF-8 writer `TUtf8JsonWriter`, the record deserializer used by body binding, DbSet projections) writes and reads dates the same way, the ISO 8601 / RFC 3339 standard:

| Type | JSON text |
|---|---|
| `TDateTime` | `"2026-07-15T10:30:00.000+02:00"`: the **local** time with its offset from UTC (`Z` when the offset is zero) |
| `TDate` | `"2026-07-15"`: the calendar day |
| `TTime` | `"10:30:00.000"`: the wall clock |

The digits are the local wall clock, so a client that ignores the offset still shows 10:30; a client that honours it (JavaScript `new Date()`, Java, .NET) gets the right instant, also in the hour that repeats when daylight saving time ends.

Reading accepts `yyyy-mm-dd`, `yyyy-mm-ddThh:nn[:ss[.fff]]` (also with a space) and a zone: `Z` or an offset (`+02:00`, `+0200`, `+02`) is **converted to the local time** of the server; a value without a zone is local time already. Other formats `TryParseCommonDate` knows are still accepted.

The functions are public in `Dext.Core.DateUtils`: `FormatJsonDateTime`, `FormatJsonDate`, `FormatJsonTime`, `TryParseJsonDateTime`, `TryParseJsonTime`. The UTC offset is computed in whole minutes and kept per calendar day, so the system is asked about once per day rather than once per value.

To keep the previous text (local time without a zone), set a custom format: `TJsonSettings.Default.CustomDateFormat('yyyy-mm-dd"T"hh":"nn":"ss.zzz')`.

## Memory Management (FastMM5)

For high-performance applications, Dext includes native support for **FastMM5**. It is enabled by default in the `Dext.Core` package to ensure optimal performance with multi-threaded web requests and large JSON processing.

To check or toggle this setting, see `Dext.MM.pas`:

```pascal
{$DEFINE DEXT_USE_FASTMM5} // Enabled for production-grade memory management
```

---

## JSON Performance: Architectural Profiles

Dext features two distinct JSON architectures designed for different performance profiles. Understanding the trade-offs is key to choosing the right tool for your scenario.

### 1. Dext DOM (IDextJsonNode)
This is the default engine used by `TDextJson.Serialize/Deserialize`. It constructs an in-memory tree (DOM) of the JSON structure.

*   **Best For**: 99% of applications, including REST APIs, configuration files, and complex object manipulation.
*   **Strengths**: High-speed random access, intuitive object-oriented API, and exceptional performance in finding properties within deeply nested structures.
*   **Memory Usage**: Proportional to the size of the JSON document.

### 2. Dext UTF-8 (Low-Level Streaming)
This is a high-performance streaming API found in the `Dext.Json.Utf8` namespace. It operates directly on raw memory slices (`TByteSpan`).

*   **Best For**: Big Data scenarios, exporting/importing millions of records, or processing multi-gigabyte files.
*   **Strengths**: **Zero-allocation** processing. It can process massive volumes of data with a constant and minimal memory footprint, regardless of the file size.
*   **Trade-offs**: As a streaming parser, it does not index the document. Finding a specific property requires sequential scanning from the start of the buffer, which can be slower for random-access benchmarks but is irrelevant for sequential throughput.

---

## JSON Mapping Conventions (CoC)

Dext follows a **Convention over Configuration** approach for JSON serialization, specifically optimized to handle Delphi's RTTI limitations.

### Record Serialization
Delphi's RTTI does not consistently handle properties in records during dynamic memory manipulation. To ensure reliable serialization and deserialization:

1.  **Public Fields**: Use `public` fields for record members.
    
```pascal
type
  TUserDTO = record
  public
    id: Integer;
    name: string;
    roles: IList<string>;
  end;
```

2.  **Explicit Mapping**: Use the `[JsonName]` attribute to decouple your Delphi naming convention from the JSON schema.

```pascal
type
  TUserDTO = record
  public
    [JsonName('id')] Id: Integer;
    [JsonName('full_name')] Name: string;
    [JsonName('roles')] Roles: IList<string>;
  end;
```

> [!IMPORTANT]
> **Avoid properties in Records** for serialization. While Delphi supports them, RTTI-based `SetValue` calls often operate on temporary copies of the record, causing the original instance to remain unpopulated. Use public fields instead.

### Handling Generic Collections (IList<T>)
When Dext encounters an interface type like `IList<T>` or `IReadOnlyList<T>`, it needs a strategy to instantiate the concrete implementation.

#### 1. Registration via TActivator
Register the mapping between the interface and its concrete implementation (usually `TList<T>` or `TSmartList<T>`).

```pascal
initialization
  TActivator.RegisterDefault<IList<TUserDTO>, TList<TUserDTO>>;
```

#### 2. Pre-instantiation (Hydration)
If a field or property already holds an instance (e.g., created in a constructor or via a factory), Dext will **detect and reuse** it instead of attempting to create a new one.

```pascal
constructor TMyClass.Create;
begin
  // Dext will populate this existing list during deserialization
  FItems := TCollections.CreateList<TItem>; 
end;
```

### The `[JsonName]` Attribute
Use `[JsonName]` to maintain clean `PascalCase` in your Delphi code while complying with external JSON standards (`camelCase`, `snake_case`, etc.).

```pascal
type
  TConfig = record
  public
    [JsonName('max_threads')] MaxThreads: Integer; // Maps to "max_threads" in JSON
  end;
```

### The `[JsonIgnore]` Attribute
`[JsonIgnore]` keeps a member out of the JSON in both directions: it is not written, and it is not read. Reading matters as much as writing: a class or record bound from a request body never gets an ignored member from the client.

With a `TJsonIgnoreMode` the member is ignored in one direction only:

```pascal
type
  TUser = class
  public
    property Name: string read FName write FName;
    [JsonIgnore]                           // neither written nor read
    property Internal: string read FInternal write FInternal;
    [JsonIgnore(TJsonIgnoreMode.OnWrite)]  // read, never written: comes in, never goes back out
    property Password: string read FPassword write FPassword;
    [JsonIgnore(TJsonIgnoreMode.OnRead)]   // written, never read: decided by the server
    property CreatedAt: TDateTime read FCreatedAt write FCreatedAt;
  end;
```

The same applies to record fields. `[JsonPublishedOnly]` on a class works in both directions too: only published properties are written and read.

### Binary Data (`TBytes`)
JSON has no binary type, and the convention for binary data is a **Base64 string** (RFC 4648; `format: byte` in OpenAPI). A `TBytes`, or any other dynamic array of `Byte`, is written that way: on one line, with padding, in classes, records, arrays, lists, and as the root of the JSON.

```pascal
type
  TDocument = class
  public
    property Name: string read FName write FName;
    property Content: TBytes read FContent write FContent;
  end;

// {"Name":"a.png","Content":"iVBORw0KGgo="}
Json := TDextJson.Serialize(Doc);
```

Reading accepts the forms other systems write: standard Base64, the URL alphabet (`-` and `_`), without the final `=`, with MIME line breaks; and an array of numbers from 0 to 255, so JSON written by earlier versions still reads. A text that is not Base64, a number outside 0..255, or any other value raises an exception that names the field: binary data is never guessed.

To write the array of numbers instead (for a client that expects it): `TJsonSettings.Default.BytesAsBase64(False)`.

### Format Attributes
Four attributes change how one member is written, on class properties and record fields alike, and the same member is read back in that form:

| attribute | on | written as | read |
|---|---|---|---|
| `[JsonFormat('dd/mm/yyyy')]` | `TDateTime`, `TDate`, `TTime` | the format, with the invariant settings (`/` and `:` as written, whatever the locale) | the format; a standard date too |
| `[JsonString]` | integers, floats, `Currency`, `Boolean` | a string: `"9007199254740993"`, `"12.5"`, `"true"` | a string or the normal value |
| `[JsonNumber]` | `string` | a number; empty text is `null`, text that is not a number stays text | a number or a string |
| `[JsonBoolean]` | integers | `true`/`false` (0 is `false`) | a Boolean or a number |

```pascal
type
  TOrder = class
  public
    [JsonString]  // beyond 2^53 a JavaScript number loses digits
    property Id: Int64 read FId write FId;
    [JsonFormat('yyyymmdd')]
    property Day: TDate read FDay write FDay;
  end;

// {"Id":"9007199254740993","Day":"20260715"}
```

`[JsonFormat]` reads back formats made of `yyyy yy mm m dd d hh h nn n ss s zzz z` and fixed text (`TJsonUtils.TryParseDateWithFormat`). A format that cannot be read back (month names, `am/pm`), two of these attributes on one member, or an attribute on a type it cannot change raise `EDextJsonException` when the class or record is first serialized: an attribute that does nothing is never silent.

> [!TIP]
> Use **Dext DOM** for your daily API development. Switch to **Dext UTF-8** only when memory consumption becomes a bottleneck or when processing massive data streams.

---

[← Advanced Topics](README.md)
