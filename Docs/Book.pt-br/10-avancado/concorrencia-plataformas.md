# Concorrência no Windows e no Linux

Os blocos de concorrência do Dext são portáveis: usam apenas a RTL (`TThread`, `TMonitor`, `TEvent`, `TSpinLock`, `TInterlocked`) e compilam para Windows (Win32/Win64) e Linux64.

| Área | Units | Windows | Linux64 |
| :--- | :--- | :---: | :---: |
| Cancelamento | `Dext.Threading.CancellationToken` | sim | sim |
| Tarefas assíncronas | `Dext.Threading.Async` | sim | sim |
| Resiliência | `Dext.Resilience` | sim | sim |
| Canais, dicionário concorrente | `Dext.Collections.Channels`, `Dext.Collections.Concurrent` | sim | sim |
| Hosting e serviços em segundo plano | `Dext.Hosting.*` | sim | sim |
| Background jobs (InMemory, SQLite) | `Dext.BackgroundJobs.*` | sim | sim (SQLite via FireDAC) |
| Barramento de eventos | `Dext.Events.*` | sim | sim |
| Executor limitado | `Dext.Server.BoundedExecutor` | sim | sim (usado pelo motor Epoll) |
| Log assíncrono | `Dext.Logging.RingBuffer`, `Dext.Logging.Async` | sim | sim |

## Partes exclusivas do Windows

Algumas partes existem por causa de uma API do Windows. Elas estão marcadas como exclusivas, e cada uma tem um equivalente no Linux:

| Exclusivo do Windows | O que faz | Equivalente no Linux |
| :--- | :--- | :--- |
| `Dext.Server.Iocp` | Motor HTTP sobre portas de conclusão de E/S | `Dext.Server.Epoll` |
| `Dext.Server.HttpSys` | Motor HTTP sobre o http.sys | `Dext.Server.Epoll` |
| `Dext.Threading.ProcessorGroups` (afinidade por grupo) | Distribui workers entre grupos de processadores do Windows (mais de 64 processadores lógicos) | O motor Epoll fixa os workers com `pthread_setaffinity_np`. As funções de contagem da unit recorrem a `CPUCount` |

`GetTickCount64` (exportada por `Dext.Resilience`) usa `TThread.GetTickCount64` fora do Windows.

## O que foi verificado

As units acima foram compiladas para Linux64 com o `dcclinux64`. Os testes de comportamento (`Dext.Core.UnitTests`, `TestCollections`) rodam no Windows; não foram executados em uma máquina Linux com as ferramentas deste repositório. Execute-os no seu alvo Linux antes de depender de um comportamento específico de temporização.
