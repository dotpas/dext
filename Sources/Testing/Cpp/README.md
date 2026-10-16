# Dext Testing — C++ bridge (C++Builder)

Header-only clients for the **Dext Test Explorer** HTTP Host. No Delphi RTL in the test exe.

| Header | Role |
|--------|------|
| `DextTestingHost.hpp` | WinHTTP client: `--port`, `GET /tests`, `POST /tests/results` |
| `DextGTestAdapter.hpp` | Google Test listener + `--discover` / `--port` |
| `DextDUnitCppAdapter.hpp` | DUnit C++ discover/run (`RegisterDunitTestCase`) |
| `DextMapResolve.hpp` | C++ MAP address resolve (DUnit deep stack) |

## Include path

Add this folder to the C++Builder project **Include path**.

## GTest (recommended)

Install **Google Test** via GetIt, then:

```cpp
#include "DextGTestAdapter.hpp"

int main(int argc, char** argv) {
  return Dext::Testing::RunDextGTest(argc, argv);
}
```

| Explorer | Args |
|----------|------|
| Refresh | `--port N --discover -no-wait` |
| Run | `--port N -no-wait` |

The same executable writes the Delphi report files when you pass the switches the Delphi runner already understands:

```text
MyTests.exe -junit:test-results.xml -json:test-results.json -html:test-results.html -sonar:sonar-tests.xml
```

JUnit, JSON and Sonar (`testExecutions`) follow `Dext.Testing.Report`. HTML is a table of those same rows. This works with or without `--port`.

Sample: `Tests/Samples/Cpp.GTestSmoke`.

## DUnit C++

Sample: `Tests/Samples/Cpp.DUnitSmoke`. See `DextDUnitCppAdapter.hpp`.

## Protocol

Same as Delphi `Dext.Testing.DUnit.pas` / `Dext.Testing.Design.Server.pas` — not the inventend `--dext-host` flags from early research docs.
