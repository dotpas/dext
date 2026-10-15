# Projetos não-Dext

Você pode rodar suítes **DUnit**, **DUnitX** ou **DUnit2** no **Dext Test Explorer** sem reescrever asserts em `[Fact]` do Dext Testing: basta o adapter de integração no projeto de teste.

## Sample no repositório

[`Tests/Samples/Cap18b.LegacyDUnitX`](../../../Tests/Samples/Cap18b.LegacyDUnitX/) — projeto `LegacyCobrancaTests` (DUnitX clássico) + adapter `Dext.Testing.DUnitX`.

Roteiro passo a passo (IDE): [Cap18b Explorer Demo](../../Plans/Dext-Testing-Cap18b-Explorer-Demo.md).

## Ideia

1. Projeto de testes legado continua com o framework de asserts que já usa.  
2. Inclui a unit de integração Dext Testing correspondente (DUnit / DUnitX / DUnit2).  
3. O Explorer descobre, compila e mostra PASS/FAIL como nas suítes Dext.
