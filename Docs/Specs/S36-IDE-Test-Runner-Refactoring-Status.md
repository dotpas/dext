# S36 Expert Refactoring — Status (Fase 1)

Updated as part of the Dext Testing product track.

**Living backlog (Plans):** [Dext-Testing-Explorer-Plan.md](../Plans/Dext-Testing-Explorer-Plan.md) — melhorias + refactor restantes do `Dext.Testing.Design`.

## Done

| Item | Status |
|------|--------|
| Package decoupling (`requires Dext.Testing.Core`, not full `Dext.Testing`) | Done in `.dpk`; `DCC_UsePackage` cleaned in Design `.dproj` files |
| MVP Presenter / Model / View | Present (`Dext.Testing.Design.Presenter.pas`) |
| Winsock client socket close on Stop | Done (`CloseAllClientSockets`) |
| Async compile + run (`TTask.Run`) | Done |
| Cancel / Stop interruptible wait | Done (`FCancelRequested` + polled `WaitForSingleObject`) |
| OTA platform/config resolved on UI thread | Done (`ResolveActivePlatformConfig`) |
| Console callbacks marshaled to main thread | Done (`SafeConsole`) |

## Follow-ups

- Further Passive View migration of remaining DockableForm compile paths that still bypass the Presenter (Execution Plan **E1.9**).
- Coverage v1 shipped (Collect + aba + gutter column); richer DCC line emission is a separate investigation.
- Console ListView shipped (E1.7); filters All/Errors/Analytics remain optional polish.
