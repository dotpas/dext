# Analysis of Dext Test Runner Implementation

> **Update 2026-10:** Stale. `TTestRunner.ExecuteProcess` is fire-and-forget with stdout pipe capture and `BroadcastSSE`/`DashboardEvent` fan-out.

## Current State (historical)

The current implementation of the Test Runner in Dext Dashboard suffers from several critical issues preventing real-time feedback and causing UI freezes.

### 1. Blocking Execution Model (The "Freeze")
- **Component**: `Dext.Dashboard.TestRunner.pas` (Method `ExecuteProcess`)
- **Issue**: The execution uses `WaitForSingleObject` with a 30-second timeout on the main HTTP request thread.
- **Result**: When the user clicks "Run", the HTTP request `/api/tests/run` hangs until the test completes or times out. This makes the UI unresponsive or appear "stuck" for long periods.

### 2. Hidden Execution & No Output Capture ( The "Blindness")
- **Component**: `ExecuteProcess`
- **Issue**: The process is spawned with `SW_HIDE` (Hidden Window) and **no pipe redirection** for Standard Output (stdout) or Standard Error (stderr).
- **Result**: 
  - The user cannot see the console output.
  - If the test runner crashes or errors out before writing a result file, the dashboard has zero visibility into why.
  - Real-time progress (e.g., "Running test 1 of 50...") is impossible to display.

### 3. Missing Telemetry Integration (The "Broken Promise")
- **Component**: `Dext.Testing.Runner.pas` and `Dext.Dashboard.Routes.pas`
- **Context**: The Dashboard has an endpoint `/api/telemetry/logs` capable of broadcasting logs via SignalR.
- **Issue**: The `Dext.Testing.Runner` framework **does not import or use `Dext.Telemetry`**. It currently only writes to the Console (`TTestConsole`) or file reports.
- **Result**: Even though the infrastructure for observability exists, the test runner is "mute" and does not send any data to the dashboard during execution.

---

## Architecture Gap

| Feature | Dashboard Expectation | Runner Implementation |
|---------|------------------------|-----------------------|
| **Trigger** | POST `/api/tests/run` | Standalone Executable |
| **Feedback Channel** | SignalR (`LogReceived`) via `/api/telemetry/logs` | `Writeln` to Console (Hidden) |
| **Result Retrieval** | Reads `test-results.json` after exit | Writes JSON file on completion |
| **Async Support** | None (Synchronous Wait) | N/A |

---

## Proposed Solution: Real-Time Feedback with OpenTelemetry

To fix this "properly" and align with the OpenTelemetry (OTEL) patterns previously discussed, we need to implement the following changes:

### Phase 1: Enable Telemetry in Test Runner
1.  **Modify `Dext.Testing.Runner`**:
    -   Add `Dext.Telemetry` dependencies.
    -   Create a new `ITestListener` implementation: `TTelemetryTestListener`.
    -   This listener will send HTTP POST requests to the Dashboard's `/api/telemetry/logs` endpoint (or a dedicated OTEL exporter) for events: `OnTestStart`, `OnTestComplete`, `OnLog`.

2.  **Configure Runner**:
    -   The test runner application (e.g., `TestAttributeRunner`) must be initialized with the Dashboard URL (e.g., via command line arg or environment variable).

### Phase 2: Non-Blocking Dashboard Execution
1.  **Modify `/api/tests/run`**:
    -   Change the endpoint to **spawn** the test process asynchronously and return immediately (or use a Job ID).
    -   Do **not** wait for completion in the API handler.
    -   Let the *Test Runner itself* report its progress back to the Dashboard via the Telemetry channel.

2.  **Dashboard UI**:
    -   Subscribe to the SignalR `LogReceived` event.
    -   Display logs/test progress in real-time as they come in from the runner.

### Phase 3: Detailed Result Collection
-   Once the runner reports "RunComplete" via telemetry, the Dashboard can request the full detailed report (or it can be sent as the final telemetry payload).

## Immediate Action Plan

1.  **Refactor `Dext.Testing.Runner`**: Add `Dext.Telemetry` support.
2.  **Create `TTelemetryTestListener`**: Bridge test events to Telemetry spans/logs.
3.  **Update `TestAttributeRunner`**: Initialize `Telemetry.GlobalLogger` to point to the Dashboard.
4.  **Refactor Dashboard**: Remove `WaitForSingleObject` and rely on the incoming data stream.
