# Cap18b sample — LegacyCobrancaTests (DUnitX + Explorer)

Minimal DUnitX host that registers `Dext.Testing.DUnitX` so the **Dext Test Explorer** can run the suite without rewriting asserts to `[Fact]`.

## Prerequisites

- Dext sources: search path already includes `Sources/Common`.
- **DUnitX** on the IDE Library path (GetIt package or your own clone). This repo does not vendor DUnitX.

Full steps: [Docs/Plans/Dext-Testing-Cap18b-Explorer-Demo.md](../../../Docs/Plans/Dext-Testing-Cap18b-Explorer-Demo.md)
