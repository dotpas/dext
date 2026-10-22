---
name: dext-testing
description: Write unit tests with the Dext Testing Framework — test fixtures, mocking interfaces, fluent assertions, and running tests.
---

# Dext Testing Framework

## Core Imports

```pascal
uses
  Dext.Testing; // Facade: Assert, Should, TTest, [TestFixture], [Test], etc.
  Dext.Mocks;   // Mock<T> — NOT included in Dext.Testing facade
```

> `Mock<T>` lives in `Dext.Mocks`, not in the `Dext.Testing` facade.
> Import both when writing tests with mocks.

## Test Project Structure (`.dpr`)

Create a separate **Console Application** project for tests:

```pascal
program MyProject.Tests;

{$APPTYPE CONSOLE}

uses
  Dext.MM,          // Optional: FastMM5 memory manager
  Dext.Utils,       // SetConsoleCharSet, ConsolePause
  System.SysUtils,
  Dext.Testing,     // Main facade
  TUserServiceTests in 'UserServiceTests.pas',
  TOrderTests in 'OrderTests.pas';

begin
  SetConsoleCharSet;  // REQUIRED for all console projects

  TTest.SetExitCode(
    TTest.Configure
      .Verbose            // REQUIRED: without this, output is silent
      .RegisterFixtures([TUserServiceTests, TOrderTests])
      .Run
  );

  ConsolePause;  // Keeps console open in IDE
end.
```

## Test Fixture — Attributes

```pascal
uses
  Dext.Testing;

type
  [TestFixture]
  TUserServiceTests = class
  public
    [Setup]
    procedure Setup;       // Runs before each test

    [TearDown]
    procedure TearDown;    // Runs after each test

    [Test]
    procedure Should_ReturnUser_WhenExists;

    [Test]
    [TestCase(1, 2, 3)]    // Parameters: A=1, B=2, Expected=3
    [TestCase(10, 5, 15)]
    procedure Should_Add_WithParams(A, B, Expected: Integer);
  end;
```

## Mocking with `Mock<T>`

`Mock<T>` is a **generic record** — it does NOT need `.Free`.

```pascal
uses
  Dext.Testing,   // TestFixture, Test, etc.
  Dext.Mocks;     // Mock<T>

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

    [Test]
    procedure GetUser_ReturnsNil_WhenNotFound;
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
  User.Name := 'Alice';
  FMockRepo.Setup.Returns(User).When.FindById(Arg.Any<Integer>);

  // Act
  var Result := FService.GetById(1);

  // Assert
  Should(Result).NotBeNil;
  Should(Result.Name).Be('Alice');

  // Verify
  FMockRepo.Received(Times.Once).FindById(1);
end;

procedure TUserServiceTests.GetUser_ReturnsNil_WhenNotFound;
begin
  // Arrange
  FMockRepo.Setup.Returns(nil).When.FindById(Arg.Any<Integer>);

  // Act
  var Result := FService.GetById(999);

  // Assert
  Should(Result).BeNil;
end;
```

### Mock Setup Patterns

```pascal
// Return a value
FMock.Setup.Returns(SomeValue).When.MethodName(Args);

// Return different values in sequence
FMock.Setup.Returns(User1).When.GetNext;
// On second call, returns User2, etc.

// Return nil
FMock.Setup.Returns(nil).When.MethodName(Arg.Any<T>);

// Throw exception
FMock.Setup.Throws(ENotFoundException).When.FindById(999);

// Argument matchers
Arg.Any<Integer>          // Any integer value
Arg.Is<string>('alice')   // Exact match
Arg.IsNot<string>('')     // Not equal
```

### Mock Verification

```pascal
// Verify call count
FMock.Received(Times.Once).MethodName(expectedArg);
FMock.Received(Times.Never).MethodName(Arg.Any<T>);
FMock.Received(Times.AtLeast(2)).MethodName(Arg.Any<T>);
FMock.Received(Times.Exactly(3)).MethodName(Arg.Any<T>);

// Access the interface instance
var Instance := FMock.Instance;  // IUserRepository
```

## Fluent Assertions (`Should`)

```pascal
// Equality
Should(Value).Be(Expected);
Should(Value).NotBe(Expected);

// Nil checks
Should(Obj).BeNil;
Should(Obj).NotBeNil;

// String assertions
Should(Name).StartWith('John');
Should(Name).EndWith('Doe');
Should(Name).Contain('oh');
Should(Name).StartWith('John').AndAlso.EndWith('Doe');

// Numeric comparisons
Should(Count).BeGreaterThan(0);
Should(Count).BeLessThan(100);

// Collections
Should(List).Contain(Item);
Should(List).NotContain(Item);
Should(List).ContainOnly(Item1, Item2);
Should(List).HaveCount(5);
Should(List).BeEmpty;
Should(List).NotBeEmpty;
Should(List).BeOrdered;

// Objects
Should(Obj).BeOfType<TUser>;
Should(Obj).BeAssignableTo<IPerson>;
Should(Obj1).BeEquivalentTo(Obj2);
Should(User).HaveProperty('Name').WithValue('Alice');

// Exceptions
Should.Raise<EArgumentException>(procedure begin Svc.BadCall end);
Should.RaiseAny(procedure begin Svc.BadCall end);
Should.NotRaise(procedure begin Svc.ValidCall end);

// Smart assertions (strongly typed, with Prototype)
var u := Prototype.Entity<TUser>;
Should(User).HaveValue(u.Name, 'Alice');
Should(User).HaveValue(u.Age, 30);
Users.Should.AllMatch(u.Age > 0);
```

## `Assert` (Classic Style)

The `Assert` helper from `Dext.Testing` also supports classic-style assertions:

```pascal
Assert.AreEqual(Expected, Actual);
Assert.AreNotEqual(Expected, Actual);
Assert.IsTrue(Condition);
Assert.IsFalse(Condition);
Assert.IsNil(Obj);
Assert.IsNotNil(Obj);
```

## Testing Entities with Child Collections

Entities use `OwnsObjects = False` for ORM compatibility. In unit tests (without DbContext), you must free child objects manually:

```pascal
procedure TOrderTests.Should_CalculateTotal;
var
  Order: TOrder;
  Item: TOrderItem;
begin
  Order := TOrder.Create;
  Item := TOrderItem.Create;
  try
    Item.Price := 25.00;
    Item.Quantity := 2;
    Order.Items.Add(Item);

    Order.CalculateTotal;

    Should(Order.Total).Be(50.00);
  finally
    Order.Free; // Frees Order + list, but NOT Item (OwnsObjects=False)
    Item.Free;  // REQUIRED: free child manually
  end;
end;
```

## Parametrised Tests

```pascal
[Test]
[TestCase(0, 0, 0)]
[TestCase(1, 2, 3)]
[TestCase(10, -5, 5)]
procedure Should_Add(A, B, Expected: Integer);
begin
  var Calc := TCalculator.Create;
  try
    Should(Calc.Add(A, B)).Be(Expected);
  finally
    Calc.Free;
  end;
end;
```

## Native DUnitX, DUnit, DUnit2 and TestInsight Integration

### Decoupled DUnit/DUnit2/DUnitX IDE Runner Integration

This configuration enables existing DUnit, DUnit2, or DUnitX test projects to run directly inside the **Dext Test Explorer** in RAD Studio or via the **Dext CLI**, while keeping the project completely decoupled from Dext at runtime (meaning it can still run as a standard standalone VCL/Console test suite when executed normally).

#### 1. Configure Project Options in RAD Studio
1. Open your test project in RAD Studio.
2. Go to **Project > Options** (Shift+Ctrl+F11).
3. Under **Building > Delphi Compiler**, add the relative path to Dext's common sources directory (`\Sources\Common` or your relative equivalent) to the **Search Path**.
4. Under **Conditional defines**, add the compiler directive corresponding to your testing framework:
   - For DUnitX: `DEXT_DUNITX`
   - For DUnit: `DEXT_DUNIT`
   - For DUnit2: `DEXT_DUNIT2`

#### 2. Update your `.dpr` Uses Block
Add the conditional integration units to the project uses block:
```pascal
program MyProject.Tests;

uses
  System.SysUtils,
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
  // Your normal test units below:
  MyTestUnits in 'MyTestUnits.pas';
```

#### 3. Add CommandLine Interceptor in the main block
Add the `TryExecuteFromCommandLine` check at the very beginning of the `begin..end` block. If the project is executed by Dext's background runner, it will capture command-line parameters, run the tests silently, report results to the IDE/CLI, and exit early.
```pascal
begin
  ReportMemoryLeaksOnShutdown := True;

  // Intercept Dext execution calls (runs silently and exits if called via CLI or Test Explorer)
  {$IF (defined(DEXT_DUNITX) or defined(DEXT_DUNIT) or defined(DEXT_DUNIT2))}
  if TTestRunnerRegistry.TryExecuteFromCommandLine then
    Exit;
  {$ENDIF}

  // Your standard framework initialization (VCL GUI or Console runner)
  // ...
end.
```

### Decoupled TestInsight Integration
To run **Dext** test projects (using the Dext framework) and display results inside Stefan Gliener's **TestInsight IDE plugin**:

1. Add the Dext common sources directory (`\Sources\Common`) to your project's search paths.
2. Add the `Dext.Testing.TestInsight` unit to your `.dpr` file's uses clause:
   ```pascal
   uses
     Dext.Testing,
     Dext.Testing.TestInsight, // Registers the TestInsight execution hook
     MyTests in 'MyTests.pas';
   ```
3. When executed from the TestInsight plugin inside the IDE, Dext will automatically detect the `/X` or `/TestInsight` parameters and route all results to TestInsight.

## Running Tests

```bash
dext test                              # Run all tests
dext test --verbose                    # Verbose output
dext test --coverage                   # With code coverage
dext test --html --output report.html  # HTML report
```

Or via Delphi IDE: Run the test console project directly. The docked runner is the **Dext Test Explorer**.

## Dext Test Explorer

Install from source. We are still deciding whether to ship a prebuilt DLL: it is not digitally signed, and a development certificate has a cost. The steps are in `Docs/Book/08-testing/test-explorer.md` (Portuguese: `Docs/Book.pt-br/08-testes/test-explorer.md`).

- Close RAD Studio, build `Apps/TestExplorerExpert/Dext.Testing.Design.ExpertLib.dproj` (Win32, or Win64 for the 64-bit IDE), then run `Installers/DextTestExplorer/Install-DextTestExplorer.ps1 -StudioVersion 37.0`.
- Delphi line coverage needs a detailed MAP and **Collect code coverage**. The tool is Delphi Code Coverage.
- C++ line coverage is **Win64x only** (`bcc64x`). On any other `.cbproj` platform the Explorer hides the coverage checkbox, menu and tab, and the run log says Win32 and classic Win64 do not support code coverage.
- Win64x compiler options that reach `bcc64x -cc1`: `-fprofile-instrument=clang -fcoverage-mapping`. Linker: `-lclang_rt.profile-x86_64`. After the run the Explorer reads LCOV from LLVM 20 `llvm-cov`. RAD Studio does not ship `llvm-cov`. Do not use `-fprofile-instr-generate` on the MSBuild `-cc1` line.
- Do not wrap a C++ exe with Delphi Code Coverage. The C++ map has no line table. Do not embed a profiler for classic Win32 or Win64. An integrated profiler is only an idea.
- This is not an Embarcadero feature. Do not describe the C++ expert as finished support.

## Integration Testing — WebApplicationFactory (S66 / S68)

```pascal
uses
  Dext.Testing,
  Dext.Testing.WebApplicationFactory,
  Dext.Web,
  Dext.Web.Results;

var
  Factory: TDextApplicationFactory<TObject>;
  Client: IDextTestHttpClient;
  Response: IDextTestHttpResponse;
begin
  Factory := TDextApplicationFactory<TObject>.Create
    .WithConfigure(
      procedure(App: TWebApplication)
      begin
        App.Builder.MapGet('/api/ping',
          procedure(Ctx: IHttpContext)
          begin
            Results.Ok('pong').Execute(Ctx);
          end);
      end);
  try
    Client := Factory.CreateClient; // in-process, no TCP
    Response := Client.Get('/api/ping');
    Should(Response.StatusCode).Be(200);
  finally
    Factory.Free;
  end;
end;
```

## Integration Testing (PowerShell)

Every Web API should have a PowerShell integration test script (e.g., `Test.MyApi.ps1`):

```powershell
# Always use 127.0.0.1 (not localhost — avoids IPv6/404 issues)
$baseUrl = "http://127.0.0.1:8080"
$headers = @{
  "Accept" = "application/json"
  "Content-Type" = "application/json; charset=utf-8"
}

# Health check
$r = Invoke-RestMethod -Uri "$baseUrl/health" -Headers $headers
if ($r -ne "healthy") { throw "Health check failed" }

# Auth
$body = '{"username":"admin","password":"secret"}' | ConvertFrom-Json
$token = (Invoke-RestMethod -Method POST -Uri "$baseUrl/api/auth/login" -Body ($body | ConvertTo-Json) -Headers $headers).token

# Authenticated request
$authHeaders = $headers + @{ "Authorization" = "Bearer $token" }
$users = Invoke-RestMethod -Uri "$baseUrl/api/users" -Headers $authHeaders
```

Notes:

- Use `127.0.0.1` not `localhost` to avoid IPv6 routing issues
- Set `Accept` and `Content-Type` headers explicitly
- Enums are serialized as strings by default (`"tsOpen"`, not `1`)

## Snapshot Testing

Compare complex objects against a saved JSON baseline instead of writing dozens of `Should.Be` assertions:

```pascal
[Test]
procedure TestComplexReport;
begin
  var Result := Service.GenerateReport(123);

  // First run: creates __snapshots__/MyTests.TestComplexReport.json
  // Subsequent runs: compares against the saved file
  Result.MatchSnapshot;
end;
```

Ignore fields that change per-run (timestamps, random IDs):

```pascal
Result.MatchSnapshot(procedure(Options: TSnapshotOptions)
  begin
    Options.IgnorePaths(['$.GenerationDate', '$.UniqueIdentifier']);
  end);
```

Update snapshots after intentional logic changes:

```bash
dext test --update-snapshots
```

Snapshot files are saved in `__snapshots__/` next to the test unit.

## Mock Verification Reference

```pascal
FMock.Received(Times.Once).Method(arg);         // Exactly once
FMock.Received(Times.Never).Method(arg);        // Never
FMock.Received(Times.Exactly(3)).Method(arg);   // Exactly N times
FMock.Received(Times.AtLeast(2)).Method(arg);   // At least N
FMock.Received(Times.AtMost(5)).Method(arg);    // At most N
FMock.DidNotReceive.Delete(Arg.Any<Integer>);   // Alias for Times.Never
FMock.VerifyNoOtherCalls;                        // No other calls were made
```

Interfaces must have `{$M+}` to be mockable:

```pascal
type
  {$M+}
  IMyService = interface
    ['{...}']
    function DoWork: Boolean;
  end;
  {$M-}
```

## Full Assertion Reference

```pascal
// Equality
Value.Should.Be(42);
Value.Should.NotBe(0);
Value.Should.BeGreaterThan(10);
Value.Should.BeLessThan(100);
Value.Should.BeInRange(1, 100);

// Nil / Boolean
Obj.Should.BeNil;
Obj.Should.NotBeNil;
Flag.Should.BeTrue;
Flag.Should.BeFalse;

// String
Text.Should.Contain('ell');
Text.Should.StartWith('He');
Text.Should.EndWith('lo');
Text.Should.Match('^[A-Z]');  // Regex
Text.Should.BeEmpty;
Text.Should.HaveLength(5);

// Collections
List.Should.HaveCount(5);
List.Should.BeEmpty;
List.Should.Contain(Item);
List.Should.ContainOnly(Item1, Item2);
List.Should.BeOrdered;
var u := Prototype.Entity<TUser>;
Users.Should.AllMatch(u.Age > 0);

// Objects
Obj.Should.BeOfType<TUser>;
Obj.Should.BeAssignableTo<IPerson>;
Obj.Should.BeEquivalentTo(Other);
User.Should.HaveProperty('Name').WithValue('John');

// Exceptions
Should.Raise<EArgumentException>(procedure begin Svc.Bad end);
Should.NotRaise(procedure begin Svc.Safe end);

// Soft assertions (collect all failures)
Assert.Multiple(procedure
  begin
    User.Name.Should.Be('John');
    User.Age.Should.BeGreaterThan(18);
  end);
```

## Common Mistakes

| Wrong | Correct |
|-------|---------|
| `uses Dext.Testing` only for mocks | Also add `uses Dext.Mocks` |
| `Mock<T>.Free` | Not needed — Mock is a record |
| `.RegisterFixtures([...])` without `.Verbose` | Always include `.Verbose` |
| Not freeing child entities in tests | `Item.Free` after `Order.Free` |
| `Should(Obj).Equal(...)` | `Should(Obj).Be(...)` |

