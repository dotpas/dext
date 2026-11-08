# S77 — Async Logging Pipeline & Test Runner Hot Path

**Status:** ✅ Finalized (November 2026)
**Units:** `Dext.Logging.RingBuffer`, `Dext.Logging.Async`, `Dext.Logging.Global`, `Dext.Testing.Runner`
**Tests:** `Tests\Core\UnitTests\Dext.Logging.Async.Tests.pas` (13 tests, including an 8-producer stress test)

## 1. Problem

Measured on Windows, Win32 Release, before this spec:

| Symptom | Cause |
| --- | --- |
| Every test run reported `Duration: 4,0xx s` for tests of 0 ms | `Log.Initialize` probed `http://localhost:3030` for a Sidecar. A closed loopback port takes ~2 s to refuse per address on Windows (`::1`, then `127.0.0.1`): ~4 s on the first log call of **every** Dext process without a Sidecar. |
| 30 million CPU cycles per 10 s in an idle process (0.3 million without the logger) | The consumer thread polled with `WaitFor(1)`, which sleeps until the next 15.6 ms timer tick: ~64 wake-ups per second, forever. |
| 15 ms median latency from `Log.Info` to the sink | Same timer tick. |
| Possible stale or lost entry under concurrent producers | The consumer trusted an `IsReady` flag that still read `True` from the previous lap until the new producer reset it. |
| Up to 65,536 old messages kept in memory | Slots were never cleared after reading. |
| `SetMinimumLevel` had no effect in async mode | `TAsyncLogger` never received the factory's level; `IsEnabled` only refused `None`. The logger category was also lost. |
| Silent loss under bursts | A full queue dropped entries without counting or reporting them. |
| Test runner re-read RTTI attributes for every test | Six attribute lookups and `GetParameters` per test; `[TestCaseSource]` ran twice per method. |

## 2. Design

### 2.1 Sidecar off by default
No auto-detection. The Sidecar sink starts only with `DEXT_SIDECAR_ENABLED=true` or `TSidecarOptions.Enabled`.

### 2.2 Bounded MPSC queue with per-slot sequence (`TRingBuffer`)
Dmitry Vyukov's bounded queue (the LMAX Disruptor idea), with one consumer:

- Slot `i` starts with `Sequence = i`.
- A producer may take position `p` only when `Slots[p].Sequence = p` (CAS on `Head`); a smaller sequence means the queue is full: the entry is dropped and `Dropped` incremented.
- `Publish(p)` stores `Sequence := p + 1` with a full barrier.
- The consumer reads position `t` only when `Sequence = t + 1`, clears the entry's managed fields and frees the slot with `Sequence := t + Capacity`.
- A slot from the previous lap can never pass for a new one. Positions and sequences are 32-bit and wrap on purpose.
- Sequence reads are plain aligned loads (acquire on x86/x64, explicit barrier on ARM): a locked `CompareExchange` would bounce the cache line between producer and consumer on every entry.

### 2.3 Event-based consumer
- The consumer drains, spins ~50 µs (CPU `pause`), then announces it is asleep (`Exchange(FSleeping, 1)`), checks the queue once more and waits on an auto-reset event (1 s safety timeout).
- A producer signals only when it finds `FSleeping = 1` (CAS to 0): one `SetEvent` per burst, not per entry. Both sides use full barriers, so no wake-up is lost.
- `Stop` sets `Terminated` and signals the same event (no `WaitForMultiple`, works on Linux64).

### 2.4 Level, sinks, category, drops
- `TAsyncLogState` (owned by the factory, shared by its loggers): minimum level and sink count, read without locks.
- `IsEnabled` = level ≥ minimum **and** at least one sink. Disabled calls return before formatting.
- `TLogEntry.Category`; `Log.SetMinimumLevel`; `Log.HasSinks`; `TAsyncLoggerFactory.Dropped`.
- After each drain, new drops are reported to the sinks as one `Warning` (category `Dext.Logging`).

### 2.5 Shutdown of the global `Log`
- The class destructor marks the unit as finalized, stops the consumer, frees the factory and sets `FFactory := nil` (it used to stay dangling, so a late `Log.HasSinks` read freed memory).
- After that, `Log.*` never rebuilds the pipeline: `GetLogger` hands out a null logger (`TNullLogger`, a single instance kept alive and registered as an expected leak), so a log call from the finalization of another unit, or from a thread still running, is ignored instead of touching the freed queue.
- Found while chasing an intermittent `Runtime error 216` at exit in the book's quality gate (1 run; 0 in 320 runs afterwards, including 200 in parallel).

### 2.6 Test runner
- `TTestMethodMeta`, built once per method at discovery: categories (method + fixture ancestors), `[Explicit]`, `[Ignore]`, `[Repeat]`, `[Timeout]`, `[MaxTime]`, `[Priority]`, `[Platform]`, `ITestContext` parameter, test-case presence.
- `[TestCaseSource]` runs once per method (values and names together).
- Log scopes per fixture/test only when `Log.HasSinks`; the logger starts before the clock, so `Duration` measures the tests.

## 3. Results

| Measurement | Before | After |
| --- | ---: | ---: |
| Book Lab03 (6 tests), whole process | 4.05 s | 32 ms |
| Synthetic suite, 5,400 tests, `Duration` | 43–46 ms | 24–28 ms |
| Idle logger, CPU cycles in 10 s | 30.4 M | 0.7 M (baseline 0.3 M) |
| `Log.Info` → sink latency, median / p95 | 15.3 ms / 16.1 ms | 34–58 µs / 106–192 µs |
| Producer cost per entry | ~0.30 µs | ~0.30 µs |
| Consumer, 60,000-entry burst, median of best-of-10 runs | 0.60 µs/entry | 0.60 µs/entry |
| 8 producers × 200,000 entries through 1,024 slots | — | every entry once, in order per producer (20/20 runs) |

## 4. Open decision

Clearing the slot's strings on read (so up to 65,536 old messages are not retained) moves the free to the consumer thread, which costs about 15% of consumer throughput in the burst benchmark (0.60 vs 0.51 µs/entry when the producer frees on overwrite). Kept as is pending review.

## 5. Behaviour changes

- The minimum level is now honoured: `Debug`/`Trace` entries of the global `Log` (default `Information`) are no longer emitted unless the level is lowered.
- `TLogEntry.IsReady` was removed (internal commit flag); `TLogEntry.Category` was added.
- `TRingBuffer.TryWrite` was replaced by `TryReserve` + `Publish`.
