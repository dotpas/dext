# Concurrency on Windows and Linux

The concurrency building blocks of Dext are portable: they use only the RTL (`TThread`, `TMonitor`, `TEvent`, `TSpinLock`, `TInterlocked`) and compile for Windows (Win32/Win64) and Linux64.

| Area | Units | Windows | Linux64 |
| :--- | :--- | :---: | :---: |
| Cancellation | `Dext.Threading.CancellationToken` | yes | yes |
| Async tasks | `Dext.Threading.Async` | yes | yes |
| Resilience | `Dext.Resilience` | yes | yes |
| Channels, concurrent dictionary | `Dext.Collections.Channels`, `Dext.Collections.Concurrent` | yes | yes |
| Hosting and background services | `Dext.Hosting.*` | yes | yes |
| Background jobs (InMemory, SQLite) | `Dext.BackgroundJobs.*` | yes | yes (SQLite through FireDAC) |
| Event bus | `Dext.Events.*` | yes | yes |
| Bounded executor | `Dext.Server.BoundedExecutor` | yes | yes (used by the Epoll engine) |
| Async logging | `Dext.Logging.RingBuffer`, `Dext.Logging.Async` | yes | yes |

## Windows-only parts

Some parts exist only because of a Windows API. They are marked exclusive, and each has a Linux counterpart:

| Windows-only | What it does | Linux counterpart |
| :--- | :--- | :--- |
| `Dext.Server.Iocp` | HTTP engine on I/O completion ports | `Dext.Server.Epoll` |
| `Dext.Server.HttpSys` | HTTP engine on http.sys | `Dext.Server.Epoll` |
| `Dext.Threading.ProcessorGroups` (group affinity) | Spreads workers over Windows processor groups (more than 64 logical processors) | The Epoll engine pins workers with `pthread_setaffinity_np`. The counting functions of the unit fall back to `CPUCount` |

`GetTickCount64` (exported by `Dext.Resilience`) maps to `TThread.GetTickCount64` outside Windows.

## What is verified

The units above were compiled for Linux64 with `dcclinux64`. The behavior tests (`Dext.Core.UnitTests`, `TestCollections`) run on Windows; they have not been executed on a Linux machine from this repository's tooling. Run them on your Linux target before depending on a specific timing behavior.
