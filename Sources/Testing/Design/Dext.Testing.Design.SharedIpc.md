# Shared IPC (Delphi ↔ C++Builder)

MVP: **um** BPL (`Dext.Testing.Design`) nas duas personalidades. Protocolo JSON sobre o Winsock em `Dext.Testing.Design.Server`.

## Keep in Design package

- `Dext.Testing.Design.Server` — TCP accept + JSON body  
- Presenter/Model result parsing (System.JSON)  
- Tree DTOs / `TTestLocation` em Design.AST  

## Personality differences (após discovery)

| Delphi | C++ (hipótese) |
|--------|----------------|
| Já instalado | Mesmo BPL + `CPlusPlusBuilder.Personality` |
| dcc32 / `.dproj` | msbuild / `.cbproj` / clang vs classic (TBD) |
| DUnit* / DUnitX no EXE | DUnit smoke agora; GTest/Catch2 depois |

## Extração futura (só se precisar)

1. `Dext.Testing.Design.Protocol.pas` sem ToolsAPI — se o package crescer demais.  
2. Não criar segundo BPL só por personalidade.
