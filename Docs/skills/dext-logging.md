---
name: dext-logging
description: Use logging and structured telemetry sinks (Console, File, Seq, OpenTelemetry) in Dext applications.
---

# Dext Logging & Telemetry Sinks

Idiomatic patterns for registering, configuring, and using logging and APM sinks in Dext.

## Core Imports

```pascal
uses
  Dext.Logging,             // Base log interfaces and builder
  Dext.Logging.Extensions,  // AddConsole, AddFile, AddSeq, AddOpenTelemetry
  Dext.Logging.Sinks.APM;   // TBatchOptions
```

## Basic Logger Configuration (Startup)

Logging is registered in `ConfigureServices` via the fluent builder:

```pascal
procedure TStartup.ConfigureServices(const Services: TDextServices; const Configuration: IConfiguration);
begin
  Services.AddLogging(
    procedure(Builder: ILoggingBuilder)
    begin
      Builder
        .SetMinimumLevel(TLogLevel.Information)
        .AddConsole
        .AddFile('logs/app.log', 10, True); // File path, MaxSize MB, Rolling daily
    end);
end;
```

## APM & Telemetry Sinks

To use Seq or OpenTelemetry (OTLP), you must reference the `Dext.Net` package, where network and REST clients reside.

### 1. Seq (CLEF Format)

Seq receives raw JSON lines formatted in Serilog CLEF:

```pascal
Builder.AddSeq(
  'http://localhost:5341', 
  'your-api-key', 
  TBatchOptions.Default.BatchSize(100).FlushInterval(5000)
);
```

### 2. OpenTelemetry (OTLP/HTTP)

OTLP sink exports logs in JSON format to OpenTelemetry Collectors (e.g. SigNoz, Datadog):

```pascal
Builder.AddOpenTelemetry(
  'http://localhost:4318', 
  'my-service-name', 
  'Production',
  True, // Export Logs
  False, // Export Traces
  TBatchOptions.Default.BatchSize(100).FlushInterval(5000)
);
```

### 3. Batch Options (`TBatchOptions`)

Buffered APM sinks are asynchronous and do not block the hot-path threads. Configure them with `TBatchOptions`:
- `BatchSize(Integer)`: Buffers up to N entries before sending.
- `FlushInterval(Integer)`: Transmits logs every N milliseconds even if the batch is not full.

## Using the Logger

Inject `ILogger` into your class constructor or resolve it via `IServiceProvider`:

```pascal
type
  TMyService = class
  private
    FLogger: ILogger;
  public
    constructor Create(const ALogger: ILogger);
    procedure DoWork;
  end;

procedure TMyService.DoWork;
begin
  // Standard logging levels
  FLogger.Trace('Detailed tracing step');
  FLogger.Debug('Debugging variable value: {Val}', [SomeValue]);
  FLogger.Information('Process started');
  FLogger.Warning('Execution delayed');
  FLogger.Error('Failed to process order {Id}', [OrderId]);
  FLogger.Critical('Database connection lost!');
end;
```

## Async Logging (High Performance)

For high-throughput logging using lock-free RingBuffers (avoiding I/O blocks on the caller thread):

```pascal
Builder
  .AddAsync
  .AddConsole
  .AddFile('logs/app.log');
```

### Async pipeline rules (also the global `Log`)

- Entries below the minimum level are dropped **before formatting**. Default level: `Information`. Global logger: `Log.SetMinimumLevel(TLogLevel.Debug)`.
- No sink registered → `ILogger.IsEnabled` is `False` and log calls return at once (test runs have no console sink).
- The consumer thread sleeps on an event (no polling); entries reach sinks in tens of microseconds.
- A full queue (65,536 entries) drops and counts: sinks get a `Warning` from category `Dext.Logging` ("N log entries dropped...") and `TAsyncLoggerFactory.Dropped` holds the total. Logging never blocks the caller.
- `TLogEntry.Category` carries the logger category for custom `ILogSink` implementations; `Emit` runs on the consumer thread.
- The Sidecar sink is **off by default**; enable it only with `DEXT_SIDECAR_ENABLED=true` or `TSidecarOptions.Enabled`. Never rely on auto-detection.
