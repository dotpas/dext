# Assertions

Sintaxe fluente e expressiva para validação de testes com `Should()`.

## Sintaxe Should

O Dext Testing fornece uma API fluente que torna os testes extremamente legíveis:

```pascal
Should(Value).Be(10);
Should(Name).Contain('Dext');
Should(List).HaveCount(5);
```

---

## Tipos de Asserções

### Valores Numéricos (Integer, Int64, Double)

```pascal
Should(Id).Be(123);
Should(Count).BeGreaterThan(0);
Should(Price).BeInRange(10.0, 50.0);
Should(Value).BePositive;
Should(Value).BeZero;
```

### Strings

```pascal
Should(Email).NotBeEmpty;
Should(Name).StartWith('C');
Should(Description).MatchRegex('^[a-z]+$');
Should(Text).HaveLength(5);
Should(Text).BeLowerCase;
```

### Objetos, Interfaces e Nil

```pascal
Should(User).NotBeNil;
Should(Order).BeOfType<TOrder>;
Should(PaymentIntf).NotBeNil;
```

### Datas

`Should` de `TDateTime`, `TDate` e `TTime` devolve `ShouldDateTime`. `Be` compara com precisão de milissegundo. Quando a tolerância precisa ser maior, use `BeCloseTo` com milissegundos ou `BeApproximately` com a tolerância em dias. `ShouldDate` continua disponível para quem quer o nome do calendário na chamada.

```pascal
Should(Fatura.Vencimento).Be(Combinado);
Should(Fatura.Emissao).BeBefore(Fatura.Vencimento);
Should(Fatura.Emissao).BeCloseTo(Now, 1000);
```

### GUIDs e UUIDs (Tipos Nativos Dext)

```pascal
Should(RecordGuid).NotBeEmpty;
Should(DextUuid).Be(ExpectedUuid);
```

### Listas e Coleções (TArray e IEnumerable)

```pascal
var u := Prototype.Entity<TUser>;
Should(Users).NotBeEmpty;
Should(Users).Contain(AdminUser);
Should(Users).AllSatisfy(function(User: TUser): Boolean
  begin
    Result := User.IsActive;
  end);
```

---

## Asserções de Propriedades Profundas (Property Accessors)

Você pode encadear asserções para inspecionar propriedades internas de objetos usando `.HaveProperty()`:

```pascal
Should(Order)
  .NotBeNil
  .HaveProperty('Customer').WhichObject
  .HaveProperty('Name').WhichString
  .StartWith('Enterprise');
```

---

## Tratamento de Exceções

Verifique se um bloco de código lança a exceção correta de forma fluente:

```pascal
Should(procedure
  begin
    Service.Process(nil);
  end).Throw<EArgumentNullException>();
```

Ou valide se o código executa sem exceções:

```pascal
Should(procedure
  begin
    Service.Process(Valido);
  end).NotThrow;
```

---

## Mensagens Customizadas (Because)

Você pode adicionar justificativas amigáveis que serão exibidas caso a asserção falhe:

```pascal
Should(Value).Because('O total deve incluir impostos').Be(150);
```

---

## Múltiplas Asserções (Soft Asserts)

Verifique várias condições de uma vez sem interromper no primeiro erro, acumulando todas as falhas no relatório:

```pascal
Assert.Multiple(procedure
  begin
    Should(User.Name).Be('João');
    Should(User.Email).Contain('@');
    Should(User.Age).Be(30);
  end);
```

---

[← Mocking](mocking.md) | [Próximo: Snapshots →](snapshots.md)
