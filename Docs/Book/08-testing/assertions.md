# Assertions

Fluent and expressive assertion syntax with `Should()`.

## Should Syntax

Dext Testing provides a fluent API that makes tests extremely readable:

```pascal
Should(Value).Be(10);
Should(Name).Contain('Dext');
Should(List).HaveCount(5);
```

---

## Types of Assertions

### Numeric Values (Integer, Int64, Double)

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

### Objects, Interfaces, and Nil

```pascal
Should(User).NotBeNil;
Should(Order).BeOfType<TOrder>;
Should(PaymentIntf).NotBeNil;
```

### Dates

`Should` for `TDateTime`, `TDate` and `TTime` returns `ShouldDateTime`. `Be` compares to the millisecond. When the tolerance must be wider, use `BeCloseTo` with milliseconds or `BeApproximately` with the tolerance in days. `ShouldDate` remains available when the call should say calendar by name.

```pascal
Should(Invoice.DueDate).Be(Agreed);
Should(Invoice.IssuedAt).BeBefore(Invoice.DueDate);
Should(Invoice.IssuedAt).BeCloseTo(Now, 1000);
```

### GUIDs and UUIDs (Native Dext Types)

```pascal
Should(RecordGuid).NotBeEmpty;
Should(DextUuid).Be(ExpectedUuid);
```

### Lists and Collections (TArray and IEnumerable)

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

## Deep Property Assertions (Property Accessors)

You can chain assertions to inspect nested properties of objects using `.HaveProperty()`:

```pascal
Should(Order)
  .NotBeNil
  .HaveProperty('Customer').WhichObject
  .HaveProperty('Name').WhichString
  .StartWith('Enterprise');
```

---

## Exception Handling

Verify that a block of code throws the correct exception fluently:

```pascal
Should(procedure
  begin
    Service.Process(nil);
  end).Throw<EArgumentNullException>();
```

Or validate that the code executes without exceptions:

```pascal
Should(procedure
  begin
    Service.Process(ValidInstance);
  end).NotThrow;
```

---

## Custom Explanations (Because)

You can add friendly explanations that will be displayed if the assertion fails:

```pascal
Should(Value).Because('The total must include taxes').Be(150);
```

---

## Multiple Assertions (Soft Asserts)

Verify multiple conditions at once without interrupting at the first error, aggregating all failures in the report:

```pascal
Assert.Multiple(procedure
  begin
    Should(User.Name).Be('John');
    Should(User.Email).Contain('@');
    Should(User.Age).Be(30);
  end);
```

---

[← Mocking](mocking.md) | [Next: Snapshots →](snapshots.md)
