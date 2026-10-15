# Non-Dext projects

You can run **DUnit**, **DUnitX**, or **DUnit2** suites in the **Dext Test Explorer** without rewriting asserts to Dext Testing `[Fact]`: add the matching integration adapter to the test project.

## Sample in this repository

[`Tests/Samples/Cap18b.LegacyDUnitX`](../../../Tests/Samples/Cap18b.LegacyDUnitX/) — `LegacyCobrancaTests` (classic DUnitX) + `Dext.Testing.DUnitX` adapter.

Step-by-step (IDE): [Cap18b Explorer Demo](../../Plans/Dext-Testing-Cap18b-Explorer-Demo.md).

## Idea

1. Keep the legacy assert framework you already use.  
2. Reference the matching Dext Testing integration unit (DUnit / DUnitX / DUnit2).  
3. The Explorer discovers, builds, and shows PASS/FAIL like Dext suites.
