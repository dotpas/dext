# Logging and Diagnostics

Dext features a robust logging system, inspired by the .NET ecosystem, which allows you to record structured messages and direct them to different destinations (Sinks).

## Basic Configuration

Logging is configured in the `ConfigureServices` method of your `Startup` class using the fluent builder:

```pascal
procedure TStartup.ConfigureServices(const Services: TDextServices; const Configuration: IConfiguration);
begin
  Services.AddLogging(
    procedure(Builder: ILoggingBuilder)
    begin
      Builder
        .SetMinimumLevel(TLogLevel.Information)
        .AddConsole
        .AddTelemetry; // Routes telemetry events to the log
    end);
end;
```

## Log Levels

The following levels are available (in order of severity):

| Level | Description |
| :--- | :--- |
| `Trace` | Detailed logs for deep diagnostics. |
| `Debug` | Logs useful during development. |
| `Information` | Normal application flows (startup, requests). |
| `Warning` | Anomalous events that do not interrupt the flow. |
| `Error` | Failures that prevent a specific operation. |
| `Critical` | Critical failures requiring immediate attention. |

## File Logging

Dext includes a native provider for recording logs to files. Files are recorded in **JSON Lines** format by default, making them easy to consume by analysis tools.

```pascal
Builder.AddFile('logs/app.log', 10, True); // Name, Max Size (MB), Daily Rotation
```

### File Rotation (Rolling Files)

Dext's file provider supports two automatic rotation mechanisms to prevent log files from growing indefinitely:

1.  **Daily Rotation (`ARollDaily`)**: When enabled, upon a change in date, the current file (e.g., `app.log`) is renamed to include the date (e.g., `app-2026-05-14.log`) and a new log file is started.
2.  **Size Rotation (`AMaxFileSizeMB`)**: If the file reaches the defined limit in Megabytes, it is rotated with a numeric suffix (e.g., `app.001.log`, `app.002.log`) and a new clean file is created.

You can combine both mechanisms to ensure a robust retention policy.

### Thread-Safety and Concurrency

Dext's logging system is **fully thread-safe**.
- The `TFileSink` uses an internal lock (`TMonitor`) to ensure that multiple threads (such as simultaneous HTTP requests) can log without corrupting the file or the buffer.
- Messages are accumulated in a memory buffer (4KB) before being written to disk, drastically reducing I/O operations.

### High Performance with RingBuffer (Async Logging)

For ultra-high performance applications where response time is critical, Dext offers **Async Logging** mode. It utilizes the native lock-free `RingBuffer` so your application thread never blocks waiting for disk or console I/O.

```pascal
Services.AddLogging(
  procedure(Builder: ILoggingBuilder)
  begin
    Builder
      .AddAsync // Enables high-performance mode
      .SetMinimumLevel(TLogLevel.Information)
      .AddConsole
      .AddFile('logs/app.log', 10, True);
  end);
```

> [!IMPORTANT]
> When enabling `.AddAsync`, Dext automatically manages a buffer pool and a dedicated thread for log dispatching, ensuring that the impact on your application's "Hot Path" is practically zero.

> [!TIP]
> The default synchronous mode is already extremely efficient due to internal 4KB buffering. Async mode is recommended for massive throughput scenarios or where microsecond latencies are important.

## The Async Pipeline and the Global `Log`

`.AddAsync` and the global `Log` (`Log.Info`, `Log.Error`...) are built on the same pipeline, each with its own queue and thread: the caller formats the message and publishes it to a bounded queue (65,536 entries); one background thread hands the entries to the sinks.

- **Minimum level.** Entries below the minimum level are discarded before the message is formatted. The default is `Information`. With `AddLogging` it comes from `Builder.SetMinimumLevel`; for the global logger call `Log.SetMinimumLevel(TLogLevel.Debug)`.
- **No sink, no work.** While no sink is registered, `ILogger.IsEnabled` returns `False` and a log call returns at once. Test runs have no console sink, so framework logging costs nothing there.
- **No polling.** The consumer sleeps on an event while the queue is empty and a producer wakes it only when it finds it asleep: an idle process does not spend CPU on logging, and an entry reaches the sinks in tens of microseconds.
- **Never blocks.** When the queue is full (a slow sink under a burst), the entry is dropped and counted. The sinks then receive a `Warning` from category `Dext.Logging`: "N log entries dropped: the async queue was full". `TAsyncLoggerFactory.Dropped` holds the total.
- **Category.** `TLogEntry.Category` carries the name given to `CreateLogger`, for sinks that route or filter by it.
- **Sidecar.** The Sidecar sink is off by default and only starts when configured (`DEXT_SIDECAR_ENABLED=true` or `TSidecarOptions.Enabled`). See [Dext Dashboard (Sidecar)](../09-cli/dashboard.md).

A custom sink implements `ILogSink`. `Emit` runs on the consumer thread, so keep it short or hand the work on:

```pascal
type
  TCountingSink = class(TInterfacedObject, ILogSink)
  private
    FErrors: Integer;
  public
    procedure Emit(const Entry: TLogEntry);
    procedure Flush;
  end;

procedure TCountingSink.Emit(const Entry: TLogEntry);
begin
  if Entry.Level >= TLogLevel.Error then
    TInterlocked.Increment(FErrors);
end;

procedure TCountingSink.Flush;
begin
end;

// Global logger
Log.AddSink(TCountingSink.Create);
```

## Using ILogger

To record messages, you should request the `ILogger` interface via Dependency Injection in your controllers or services:

```pascal
type
  TMyController = class(TWebController)
  private
    FLogger: ILogger;
  public
    constructor Create(const ALogger: ILogger);
    
    function Get: IWebResponse;
  end;

function TMyController.Get: IWebResponse;
begin
  FLogger.Info('Processing request for {Path}', [Request.Path]);
  // ...
end;
```

### Structured Messages

Dext supports structured messages using the `{}` brace syntax. This allows advanced providers (like the Telemetry Bridge) to capture parameters independently of the formatted message.

```pascal
FLogger.LogInformation('Order {Id} processed successfully in {Duration}ms', [LOrderId, LDuration]);
```

## HTTP Request Logging

To automatically record all HTTP requests (URL, Method, Status Code, Time), add the middleware in the `Configure` method:

```pascal
procedure TStartup.Configure(const App: IWebApplication);
begin
  App.Builder.UseHttpLogging;
  // ...
end;
```

## APM Log Sinks (Seq & OpenTelemetry)

Dext supports sending structured logs and telemetry to modern application performance monitoring (APM) tools. These sinks buffer logs in a thread-safe memory queue and forward them in asynchronous batches on background threads to prevent application performance bottlenecks.

To use APM sinks, make sure your project references the `Dext.Net` package, where the high-performance network clients reside.

### Seq Log Sink (CLEF Format)

Seq is a popular structured log server. Dext can stream logs formatted in the Compact Log Event Format (CLEF) over HTTP to Seq.

```pascal
Builder.AddSeq('http://localhost:5341', 'your-api-key', TBatchOptions.Default.BatchSize(100).FlushInterval(5000));
```

### OpenTelemetry Telemetry Sink (OTLP/HTTP)

For enterprise tracing and log collection (e.g. SigNoz, Datadog, or OpenTelemetry Collector), Dext supports the OTLP/HTTP JSON standard protocol.

```pascal
Builder.AddOpenTelemetry(
  'http://localhost:4318', 
  'my-service-name', 
  'Production',
  True, // Export Logs
  False, // Export Traces
  TBatchOptions.Default.BatchSize(200).FlushInterval(2000)
);
```

### Batch Options Configuration

Both sinks accept a `TBatchOptions` configuration:
- `BatchSize(Integer)`: The maximum number of entries to buffer before a batch transmission is automatically triggered (default: 100).
- `FlushInterval(Integer)`: The maximum duration in milliseconds to wait before transmitting any buffered entries, even if the batch size limit has not been reached (default: 5000ms).

---

[← Telemetry](telemetry.md)
