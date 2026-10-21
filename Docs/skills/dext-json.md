---
name: dext-json
description: Perform JSON serialization, deserialization, and DOM traversal using the high-performance Dext JSON engine. Use instead of System.JSON.
---

# Dext JSON Engine

High-performance, zero-allocation serialization, deserialization, and DOM parsing using `Dext.Json` instead of the slower `System.JSON` from the RTL.

## Core Imports

```pascal
uses
  Dext.Json,       // TDextJson, TJsonSettings, JsonSettings
  Dext.Json.Types; // IDextJsonNode, IDextJsonObject, IDextJsonArray, TDextJsonNodeType
```

## Basic Serialization & Deserialization

```pascal
// 1. Serialize an object or record to JSON string
var JsonStr := TDextJson.Serialize(User);

// 2. Deserialize a JSON string to an object/record
var User := TDextJson.Deserialize<TUser>(JsonStr);
```

### Fluent Settings Configuration

Configure serialization styling dynamically using fluent `TJsonSettings`:

```pascal
var Settings := JsonSettings
  .CamelCase
  .IgnoreNullValues
  .EnumAsString
  .MaxDepth(64); // Default is 64; use UNLIMITED_JSON_DEPTH (-1) to disable

var CustomJson := TDextJson.Serialize(User, Settings);
```

### Security: Recursion Depth Limit (`MaxDepth`)

To protect against Denial-of-Service (DoS) attacks via deeply nested payloads, Dext JSON parsers enforce a maximum nesting depth (`DEFAULT_MAX_JSON_DEPTH = 64`). Exceeding this limit raises `EJsonParserException` safely without causing an uncatchable stack overflow crash.

```pascal
// Catch parser exceptions:
try
  var Node := TDextJson.Provider.Parse(Payload);
except
  on E: EJsonParserException do
    Writeln('Invalid JSON or depth exceeded: ', E.Message);
end;
```

## JSON DOM Parsing & Traversal

Use the DOM interfaces to parse, traverse, and query JSON payload. All DOM nodes (`IDextJsonNode`, `IDextJsonObject`, `IDextJsonArray`) are reference-counted interfaces. **NEVER call `.Free` on them.**

```pascal
var JO: IDextJsonObject;
var ResourceLogs: IDextJsonArray;
var Resource: IDextJsonObject;
begin
  // Parse returns IDextJsonNode, cast to object or array as needed
  JO := TDextJson.Provider.Parse(ReceivedPayload) as IDextJsonObject;
  
  // Checking interface values (use Should(X).NotBeNil in tests)
  if (JO <> nil) and JO.Contains('resourceLogs') then
  begin
    ResourceLogs := JO.GetArray('resourceLogs');
    
    // Access array elements by index (0-based)
    Resource := ResourceLogs.GetObject(0).GetObject('resource');
    
    // Access typed fields
    var ServiceName := Resource.GetString('service.name');
    var Count := ResourceLogs.Count;
  end;
end;
```

### Traversal Methods

| Method / Interface | Return Type | Description |
| ------------------ | ----------- | ----------- |
| **`IDextJsonObject`** | | |
| `Contains(Name)` | `Boolean` | Checks if the key exists |
| `GetNode(Name)` | `IDextJsonNode` | Returns generic node |
| `GetString(Name)` | `string` | Returns string value |
| `GetInteger(Name)`| `Integer` | Returns integer value |
| `GetBoolean(Name)`| `Boolean` | Returns boolean value |
| `GetObject(Name)` | `IDextJsonObject`| Returns child object |
| `GetArray(Name)` | `IDextJsonArray` | Returns child array |
| **`IDextJsonArray`** | | |
| `Count` | `NativeInt` | Gets length of array |
| `GetObject(Index)` | `IDextJsonObject`| Returns child object at index |
| `GetArray(Index)` | `IDextJsonArray` | Returns child array at index |
| `GetString(Index)` | `string` | Returns string value at index |

## Why Dext JSON Instead of `System.JSON`?

- **Automatic Lifecycle Management**: Interfaces are ARC-managed; zero risk of memory leaks. No `try..finally JO.Free; end;` blocks needed.
- **High Performance**: Designed with open-addressing caching and optimized string building for high-throughput REST APIs.
- **Fluent & Inline-Friendly**: Fluent settings builder and type-safe properties avoid nested constructor initialization.

## Common Mistakes

| Wrong | Correct |
|-------|---------|
| `var JO: TJSONObject` | `var JO: IDextJsonObject` |
| `TJSONObject.ParseJSONValue(...)` | `TDextJson.Provider.Parse(...)` |
| `JO.Free` | Do not call `Free` on JSON interfaces |
| `JO.Values['name'].Value` | `JO.GetString('name')` |
| `JO.AddPair('name', 'value')` | `JO.SetString('name', 'value')` |
## S54 Direct Codec Plan

`TDextJson` can reuse the S54 shared type model for supported DTOs and entities. When working on JSON hot paths:

- Prefer field-backed properties with native types, `string`, `TGUID`, `TUUID`, nested objects, and Dext `IList<T>`.
- Keep calculated properties, custom getters/setters, unsupported wrappers, and custom converters on fallback paths.
- Do not raw-copy managed values. Direct field assignment must go through `TDextDirectAccess` helpers so string/interface reference counts remain correct.
- Generated JSON codecs are not the current public contract; the implemented S54 win is shared direct planning and fewer RTTI/TValue operations.
