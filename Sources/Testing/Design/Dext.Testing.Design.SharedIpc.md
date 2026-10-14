# Shared IPC extraction prep (Delphi ↔ C++Builder Experts)

Both personalities should speak the **same** JSON protocol over the Winsock listener in `Dext.Testing.Design.Server`.

## Keep in Design package (no Dext.Testing framework)

- `Dext.Testing.Design.Server` — TCP accept + JSON body
- Presenter/Model result parsing (System.JSON only)
- Tree DTOs mirrored in Design.AST `TTestLocation`

## Personality-specific

| Delphi | C++ |
|--------|-----|
| `Design.Expert` + DockableForm | `Design.Cpp.Registration` + thin UI wrapper |
| dcc32 compile path | msbuild / bcc64x / clang path (from discovery) |
| DUnit* adapters in suite EXE | GTest XML / Catch2 reporter (from discovery) |

## Next extraction step (when C++ beta starts)

1. Move Server + JSON DTOs to `Dext.Testing.Design.Protocol.pas` with **zero** ToolsAPI dependency.
2. Both BPLs `contains` that unit.
3. C++ installer registers only `Dext.Testing.Design.Cpp.bpl`.
