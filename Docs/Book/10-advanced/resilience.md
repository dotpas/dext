# Resilience Pipeline & Fault Handling

Dext provides a decoupled, thread-safe resilience framework (`Dext.Resilience`) inspired by .NET's Polly. It allows developers to define execution policies (Retry, Circuit Breaker, Fallback, Timeout) and apply them to any I/O or CPU-bound operation using a fluent API.

---

## 1. Getting Started

To use the resilience pipeline, add `Dext.Resilience` to your uses clause:

```pascal
uses
  System.SysUtils,
  Dext.Resilience;
```

You configure a pipeline using `TResiliencePipeline.Create` and chain policies together. A pipeline is configured once and then shared: `Execute` may be called by many threads at the same time, and callers never wait for each other. The first policy added is the outermost one (`AddRetry` then `AddTimeout` retries the whole timed operation).

```pascal
var Pipeline := TResiliencePipeline.Create
  .AddRetry(3, 100)               // 3 retries, 100ms base delay
  .AddCircuitBreaker(5, 30000)   // trip breaker after 5 errors, wait 30s
  .AddTimeout(5000);             // timeout after 5s
```

---

## 2. Core Policies

### A. Retry Policy (`TRetryPolicy`)
The Retry Policy automatically retries failed operations with exponential backoff (the wait doubles on every attempt, up to an optional cap) and optional full jitter, to prevent "thundering herd" problems on downstream services.

```pascal
// Retry 3 times, waiting 50ms, 100ms, 200ms
var Pipeline := TResiliencePipeline.Create.AddRetry(3, 50);

// Full control: cap, jitter and an exception filter
var Opt := TRetryOptions.Create(5, 100);
Opt.MaxDelayMs := 2000;
Opt.Jitter := True;
Opt.ShouldRetry := function(const E: Exception): Boolean
  begin
    Result := E is EIOException;
  end;
var Pipeline2 := TResiliencePipeline.Create.AddRetry(Opt);
```

Without a filter everything is retried except a cancellation (`EOperationCancelled`) and an open circuit (`ECircuitBrokenException`). When a token is passed to `Execute`, the back-off wait wakes up as soon as the token is cancelled.

### B. Circuit Breaker Policy (`TCircuitBreakerPolicy`)
The Circuit Breaker prevents an application from repeatedly trying an operation that is likely to fail.
- **Closed**: Normal execution. Failures increment the counter of *consecutive* failures; a success resets it.
- **Open**: The circuit trips when the failure threshold is reached. Subsequent calls fail fast immediately, throwing `ECircuitBrokenException`.
- **Half-Open**: Once the break duration expires, exactly one call (the probe) is let through; concurrent calls get `ECircuitBrokenException`. If the probe succeeds the circuit closes; if it fails the circuit reopens. A cancelled probe gives no verdict, and the next call probes again.

An optional callback reports every transition (`AddCircuitBreaker(5, 30000, procedure(AOld, ANew: TCircuitBreakerState) begin ... end)`); it runs outside the internal lock.

```pascal
// Trip breaker after 2 consecutive failures; keep it open for 1000ms
var Pipeline := TResiliencePipeline.Create.AddCircuitBreaker(2, 1000);
```

### C. Fallback Policy (`TFallbackPolicy`)
The Fallback Policy intercepts exceptions and executes an alternative block or returns a default value, ensuring the system degrades gracefully. A value fallback used in a procedure call discards the value; a procedure fallback used in a value-returning call handles the failure and the call yields `Default(T)`. A cancellation is never replaced by a fallback.

```pascal
var Pipeline := TResiliencePipeline.Create
  .AddFallback<string>(function: string
    begin
      Result := 'default-value';
    end);

var Value := Pipeline.Execute<string>(function: string
  begin
    raise Exception.Create('Primary service error');
  end); // Returns 'default-value'
```

### D. Timeout Policy (`TTimeoutPolicy`)
The Timeout Policy enforces a maximum duration on execution. It runs the operation in a task and throws `ETimeoutException` if the time limit is exceeded. On expiry the token handed to the action is cancelled; the action stops only if it observes that token (use the `Execute` overloads that take an `ICancellationToken`). An exception raised by the action is re-raised with its own class and message.

```pascal
var Pipeline := TResiliencePipeline.Create.AddTimeout(100);

try
  Pipeline.Execute(procedure
    begin
      Sleep(200); // Exceeds timeout
    end);
except
  on E: ETimeoutException do
    // Handle timeout
end;
```

---

## 3. Executing the Pipeline

The pipeline supports synchronous actions (procedures and functions) using strongly-typed generic execute overloads:

### A. Executing Procedures (No Return Value)
```pascal
Pipeline.Execute(procedure
  begin
    // Do work
  end);
```

### B. Executing Functions (With Return Value)
```pascal
var Res: Integer := Pipeline.Execute<Integer>(function: Integer
  begin
    Result := PerformCalculation();
  end);
```

---

## 4. Integration with RestClient

Dext's `TRestClient` natively integrates this resilience pipeline. The client-level `.Retry()` and `.Timeout()` methods configure this engine under the hood. You can also assign a custom pre-configured pipeline directly:

```pascal
var CustomPipeline := TResiliencePipeline.Create
  .AddRetry(3)
  .AddFallback<IRestResponse>(function: IRestResponse
    begin
      Result := TMockResponse.Create(503, 'Service Temporarily Unavailable');
    end);

var Resp := RestClient('https://api.example.com')
  .ResiliencePipeline(CustomPipeline)
  .Get('/data')
  .Await;
```
