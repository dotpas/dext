# Demo — projetos não-Dext no Test Explorer (Cap18b sample)

**Sample no repo:** [`Tests/Samples/Cap18b.LegacyDUnitX/LegacyCobrancaTests.dproj`](../../Tests/Samples/Cap18b.LegacyDUnitX/LegacyCobrancaTests.dproj)

Objetivo do pitch: suíte **DUnitX** (Assert clássico) aparece e roda no **Dext Test Explorer** sem reescrever fixtures em `[Fact]`.

---

## Pré-requisitos

1. Packages `Dext.Testing.Design` (+ Expert) instalados; IDE reiniciada.  
2. Search path do sample: `Sources/Common` (`Dext.Testing.Integration`, `Dext.Testing.DUnitX`).  
3. **DUnitX** no Library path da IDE (GetIt ou clone — **não** há `Libs/` neste repositório).  
4. Delphi **10.4+**.

---

## Passos (Você no Delphi)

1. **File → Open** `Tests/Samples/Cap18b.LegacyDUnitX/LegacyCobrancaTests.dproj` (deste repositório).  
2. Abrir o **Dext Test Explorer** (Tools / menu Dext).  
3. No combo de projetos do Explorer, selecionar `LegacyCobrancaTests` (Refresh se preciso).  
4. **Run All** — compile + exe com `--port`; o adapter `Dext.Testing.DUnitX` envia resultados.  
5. Esperado na árvore / Console:
   - Fixture `TIssue447MoraTrunc` (ou nomes dos testes `Issue_447_*`)
   - Passes nos dois testes de demo
   - Console Log estruturado (sem wall de PASS se a suite for grande; aqui são 2 testes)
6. Opcional: Actions → **Apply Debug Trace Options** → rebuild → forçar um fail temporário e ver frames no Inspector.  
7. Opcional coverage: Collect + MAP → Run All → aba Coverage (o sample é mínimo; o valor didático é o adapter, não o %).

---

## Verificação rápida fora da IDE

```text
cd Tests\Samples\Cap18b.LegacyDUnitX
# Build no RAD Studio; depois:
LegacyCobrancaTests.exe
# Exit code 0 se ambos os testes passam.
```

Com Explorer: o mesmo exe recebe `--port 8102` (ou a porta do Server do Expert).

---

## O que este sample **não** é

- Não migra asserts para `Should` (Cap. 5).  
- Não é o módulo de cobrança real de 2008 — é o cabo didático do capítulo.  
- Não exige ORM/Web/DI no host de teste.

---

## Status Sprint E

- [x] Sample + este roteiro no repo  
- [ ] Validação humana 10.4 + 13.2 (marcar no [Execution-Plan](Dext-Testing-Execution-Plan.md) DoD / checklist)
