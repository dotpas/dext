# 8. Testing

Dext includes a powerful testing framework inspired by NUnit/xUnit, with mocking, fluent assertions, and built-in test runners.

## Chapters

1. [Mocking](mocking.md) - `Mock<T>` for interfaces
2. [Assertions](assertions.md) - Fluent `Should()` syntax
3. [Snapshots](snapshots.md) - JSON snapshot testing
4. [Non-Dext projects](non-dext-projects.md) - DUnit / DUnitX / DUnit2 in Explorer without rewrite
5. [Test Explorer](test-explorer.md) - Manual install and line coverage

## Test Project Structure (.dpr)

Create a separate Console Application project for tests:

```pascal
program MyProject.Tests;

{$APPTYPE CONSOLE}

uses
  Dext.MM,             // Optional: FastMM5 wrapper
  Dext.Utils,          // SetConsoleCharSet, ConsolePause
  System.SysUtils,
  Dext.Testing,        // Main test facade (Assert, TTest, Should)
  MyTests in 'MyTests.pas';

begin
  try
    // New Simplified Fluent Runner
    RunTests(ConfigureTests
      .Verbose             // Detailed output
      // .UseTestInsight   // Optional: Force TestInsight even if not in IDE
      // .UseDashboard     // Optional: Start Web Dashboard
      .RegisterFixtures([
        TDiscountServiceTests,
        TUserServiceTests
      ])
    );
  except
    on E: Exception do
      Writeln('FATAL ERROR: ', E.ClassName, ': ', E.Message);
  end;
end.
```

## Writing Tests (Attributes)

```pascal
uses
  Dext.Testing; // Single facade

type
  [TestFixture]
  TDiscountServiceTests = class
  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure Should_Give_No_Discount_For_Standard_User;

    [Test]
    [TestCase(100.0, False, '', 0.0)]
    [TestCase(100.0, True, '', 10.0)]
    [TestCase(200.0, False, 'BLACKFRIDAY', 30.0)]
    procedure Should_Calculate_Discount_Rules(const Subtotal: Double; const IsVip: Boolean; const Coupon: string; const ExpectedDiscount: Double);
  end;
```

## Quick Start

```pascal
uses
  Dext.Testing,   // Facade: Assert, Should, TTest
  Dext.Mocks;     // Mock<T> - generic record, NOT in facade

type
  [TestFixture]
  TUserServiceTests = class
  private
    FService: TUserService;
    FMockRepo: Mock<IUserRepository>;
  public
    [Setup]
    procedure Setup;

    [Test]
    procedure GetUser_ReturnsUser_WhenExists;
  end;

procedure TUserServiceTests.Setup;
begin
  FMockRepo := Mock<IUserRepository>.Create;
  FService := TUserService.Create(FMockRepo.Instance);
end;

procedure TUserServiceTests.GetUser_ReturnsUser_WhenExists;
var
  User: TUser;
begin
  // Arrange
  User := TUser.Create;
  User.Name := 'John';
  FMockRepo.Setup.Returns(User).When.FindById(Arg.Any<Integer>);

  // Act
  var Result := FService.GetById(1);

  // Assert
  Should(Result).NotBeNil;
  Should(Result.Name).Be('John');

  // Verify
  FMockRepo.Received(Times.Once).FindById(1);
end;
```

> [!IMPORTANT]
> `Mock<T>` is a **generic Record** — it lives in `Dext.Mocks` (NOT in the `Dext.Testing` facade) and does **NOT** need `.Free`.

## Fluent Assertions

```pascal
// Simple values
Should(Total).Be(100);
Should(Name).StartWith('John').AndAlso.EndWith('Doe');

// Collections
Should(List).Contain(Item);
Should(List).HaveCount(5);

// Exceptions
Should(procedure begin Calc.DivByZero end).Throw<EInvalidOp>;

// Smart Assertions (Strongly Typed)
var u := Prototype.Entity<TUser>; // Ghost entity for metadata
Should(User).HaveValue(u.Name, 'Alice');
```

## Unit Testing Entities (Memory Warning)

When testing entities with `OwnsObjects=False` child collections (required for ORM compatibility), **you must manually free child items** in your test's `finally` block:

```pascal
var Order := TOrder.Create;
var Item := TOrderItem.Create;  // Created manually
try
  Order.Items.Add(Item);
  Order.CalculateTotal;
  // Assert...
finally
  Order.Free; // Frees Order and the List (but NOT the Item)
  Item.Free;  // REQUIRED: Free child manually
end;
```

**Why?** Entities use `OwnsObjects = False` to avoid Double Free when tracked by a DbContext. In unit tests (without DbContext), this means child objects must be freed manually.

## Integration Testing (PowerShell Scripts)

Every Web API must have a PowerShell integration test script (e.g., `Test.MyProject.ps1`) in the project root.

### Recommended Structure

1. Configuration (BaseURL, UTF-8 encoding)
2. Health Check (validate server is online)
3. Auth / Token Generation
4. Use case tests (CRUD, Business Flows)
5. Result validation (HTTP codes, JSON content)

### Tips

- **IPv6/404 Errors**: Always use `$baseUrl = "http://127.0.0.1:9000"` instead of `localhost`
- **Headers**: Set `Accept: application/json` and `Content-Type: application/json; charset=utf-8` explicitly
- **Enum values**: By default, Dext serializes enums as strings (`"tsOpen"` not `1`)
- **JWT testing**: If the API uses JWT, include a `New-JwtToken` function in the script

## IDE Integration (Dext Test Explorer)

Dext includes native high-level support for the **Dext Test Explorer**, a full-featured RAD Studio Delphi IDE Expert (plugin). It offers a rich, interactive visual interface to discover, run, and inspect tests directly from your development environment.

### Test Explorer Features:
*   **Automatic Discovery**: Dynamically maps all RTTI fixtures and test cases directly from the `.dproj` project file.
*   **Grouping Modes**: Group tests logically by structure (`Group by Code Structure`) or execution results (`Group by Test Status`).
*   **Flexible Layouts**: Supports tabbed views (`Tabbed Layout`) or split layouts (`Split Bottom/Right Layout`).
*   **Test Inspector**: Displays detailed error details, stack traces, precise duration, and source code location. Double-clicking a test navigates directly to the line of code in the IDE editor.
*   **Visual Reports**: Visual menu `...` to instantly export results to **JUnit XML**, **XUnit XML**, **JSON**, **SonarQube XML**, or **HTML Report**.

## Native DUnitX, DUnit and DUnit2 Integration

If your project already uses **DUnitX**, **DUnit** (classic) or **DUnit2** and you want to view and execute your tests directly in the **Dext Test Explorer**, you can enable native decoupled integration in a few steps:

### How to configure your test project:

1. **Add Files to search path**: Make sure the Dext common sources directory (`\Sources\Common`) is present in your project's search paths.
2. **Define Compiler Directive**: Add the compiler directive corresponding to your framework in your project options (or in your `Dext.inc` file):
   * For DUnitX: `DEXT_DUNITX`
   * For DUnit: `DEXT_DUNIT`
   * For DUnit2: `DEXT_DUNIT2`
3. **Update Uses Clause**: In your project's `.dpr` file, add the following units:
   ```pascal
   {$IFDEF DEXT_DUNITX}
   Dext.Testing.Integration,
   Dext.Testing.DUnitX,
   {$ENDIF}
   {$IFDEF DEXT_DUNIT}
   Dext.Testing.Integration,
   Dext.Testing.DUnit,
   {$ENDIF}
   {$IFDEF DEXT_DUNIT2}
   Dext.Testing.Integration,
   Dext.Testing.DUnit2,
   {$ENDIF}
   ```
4. **Trigger CommandLine Interceptor**: In the main block (`begin ... end.`) of your `.dpr` file, before running the default runner, invoke the command line check:
   ```pascal
   begin
     ReportMemoryLeaksOnShutdown := True;
     // ... other initializations ...

   {$IF (defined(DEXT_DUNITX) or defined(DEXT_DUNIT) or defined(DEXT_DUNIT2))}
     if TTestRunnerRegistry.TryExecuteFromCommandLine then
       Exit;
   {$ENDIF}

     // Default DUnitX, DUnit or DUnit2 runner code (Console or GUI)
     // ...
   end.
   ```

This approach allows the **Dext Test Explorer** and the **Dext CLI** to run your tests by passing background communication parameters in a completely decoupled way, free of heavy dependencies in the IDE.

---

## Alternative Integration (TestInsight)

Dext also retains backward compatibility with the classic **TestInsight** plugin by Stefan Gliener to run tests written in Dext.

### How to Enable TestInsight:
1. Install [TestInsight](https://github.com/stefangliener/TestInsight).
2. Add the unit `Dext.Testing.TestInsight` to the `uses` clause in your `.dpr` file.
3. The framework will automatically detect runs triggered via TestInsight.

---

## Code Coverage

Dext features support for code coverage analysis integrated with the community open-source tool **Delphi Code Coverage** (https://github.com/DelphiCodeCoverage/DelphiCodeCoverage). The `dext.exe` CLI utility automates the entire setup, download of the latest release from the official repository if missing, test run orchestration, and report consolidation.

### How to Run:
Code coverage is executed via the Dext CLI:
```bash
dext test --coverage
```
This generates unified reports in formats compatible with major DevSecOps quality tools (such as SonarQube) and visual static reports (HTML).

> [!TIP]
> **IDE Integration**: Manual install of the expert, the unsigned-DLL note, and Win64x line coverage are in [Test Explorer](test-explorer.md). The CLI engine (`dext test --coverage`) is **Stable**.

---

## Command Line Runner

Usage: `MyTestProject.exe [parameters]`

| Parameter | Alias | Description |
| :--- | :--- | :--- |
| `-verbose` | `-v` | Detailed console output |
| `-log` | | Creates a UTF-8 log file (`.log`) |
| `-dashboard`| `-d` | Starts the local Web Dashboard (Dext.Sidecar) |
| `-testinsight`| `-x` | Enables TestInsight communication |

### Dext CLI

```bash
dext test
dext test --coverage
dext test --html --output TestReport.html
```

---

[← Real-Time](../07-real-time/README.md) | [Next: Mocking →](mocking.md)
