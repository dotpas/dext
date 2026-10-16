#ifndef DextDUnitCppAdapter_HPP
#define DextDUnitCppAdapter_HPP

/**
 * DUnit C++ → Dext Test Explorer (HTTP Host, --port protocol).
 *
 * Model (TestInsight-style):
 *   --port N --discover   walk RegisteredTests(), POST Idle (no execution)
 *   --port N              run selected (GET /tests) or all; POST Running/Passed/Failed
 *
 * DUnit names the registry root ExtractFileName(ParamStr(0)) — often "Project.exe".
 * That root is skipped in paths; leaf names are Suite.Method.
 *
 * Usage:
 *   #include "DextDUnitCppAdapter.hpp"
 *   // In the .cpp that defines the TTestCase (once per fixture):
 *   static void registerMyTests() {
 *     Dext::Testing::RegisterDunitTestCase<TSmokeTestCase>();
 *   }
 *   #pragma startup registerMyTests 33
 *   int main(int argc, char** argv) {
 *     return Dext::Testing::RunDextDUnit(argc, argv);
 *   }
 */

#include "DextTestingHost.hpp"
#include "DextMapResolve.hpp"

#include <TestFramework.hpp>
#include <TextTestRunner.hpp>

#include <System.SysUtils.hpp>

#include <memory>
#include <string>
#include <vector>
#include <windows.h>

namespace Dext {
namespace Testing {

inline std::string UnicodeToUtf8(const System::UnicodeString& u)
{
  if (u.IsEmpty())
    return std::string();
  UTF8String utf(u);
  return std::string(utf.c_str());
}

inline bool EndsWithIgnoreCase(const std::string& s, const char* suffix)
{
  const size_t n = s.size();
  const size_t m = std::char_traits<char>::length(suffix);
  if (n < m) return false;
  for (size_t i = 0; i < m; ++i) {
    char a = s[n - m + i];
    char b = suffix[i];
    if (a >= 'A' && a <= 'Z') a = static_cast<char>(a - 'A' + 'a');
    if (b >= 'A' && b <= 'Z') b = static_cast<char>(b - 'A' + 'a');
    if (a != b) return false;
  }
  return true;
}

/** Registry root is ParamStr(0) file name — never a real fixture. */
inline bool IsDUnitRegistryRootName(const std::string& name)
{
  if (name.empty()) return true;
  if (name.find('\\') != std::string::npos || name.find('/') != std::string::npos)
    return true;
  return EndsWithIgnoreCase(name, ".exe") || EndsWithIgnoreCase(name, ".dll")
      || EndsWithIgnoreCase(name, ".bpl");
}

inline bool IsLeafTest(Testframework::_di_ITest test)
{
  if (!test) return false;
  // DUnit isTestMethod: CountTestCases = 1
  if (test->CountTestCases() != 1) return false;
  System::Classes::_di_IInterfaceList kids = test->Tests();
  return !kids || (kids->Count == 0);
}

/** Posts DUnit events to the Explorer Host. */
class DextDUnitReporter {
public:
  explicit DextDUnitReporter(int port)
    : FHost(std::make_shared<HostClient>(port))
  {
    if (FHost->Ok()) {
      FSelected = FHost->GetSelectedTests();
      FSelectFilter = !FSelected.empty();
    }
  }

  bool Ok() const { return FHost && FHost->Ok(); }

  void TestingStarts(int totalHint = 0)
  {
    if (Ok()) FHost->PostStarted(totalHint);
  }

  void TestingEnds()
  {
    if (Ok()) FHost->PostFinished();
  }

  void Idle(const std::string& fixture, const std::string& testName)
  {
    if (!Ok() || fixture.empty() || testName.empty()) return;
    if (IsDUnitRegistryRootName(fixture) || IsDUnitRegistryRootName(testName))
      return;
    FHost->PostResultsJson(HostClient::MakeResultJson(
      "Idle", fixture, testName, testName, "", "", 0));
  }

  void Running(const std::string& fixture, const std::string& testName)
  {
    if (!Ok() || !Selected(fixture, testName)) return;
    if (IsDUnitRegistryRootName(fixture) || IsDUnitRegistryRootName(testName))
      return;
    FHost->PostResultsJson(HostClient::MakeResultJson(
      "Running", fixture, testName, testName, "", "", 0));
  }

  void Passed(const std::string& fixture, const std::string& testName, int durationMs = 0)
  {
    if (!Ok() || !Selected(fixture, testName)) return;
    if (IsDUnitRegistryRootName(fixture) || IsDUnitRegistryRootName(testName))
      return;
    FHost->PostResultsJson(HostClient::MakeResultJson(
      "Passed", fixture, testName, testName, "", "", durationMs));
  }

  void Failed(const std::string& fixture, const std::string& testName,
    const std::string& message, int durationMs = 0, const std::string& stackTrace = "")
  {
    if (!Ok() || !Selected(fixture, testName)) return;
    if (IsDUnitRegistryRootName(fixture) || IsDUnitRegistryRootName(testName))
      return;
    FHost->PostResultsJson(HostClient::MakeResultJson(
      "Failed", fixture, testName, testName, "", message, durationMs, stackTrace));
  }

  void Error(const std::string& fixture, const std::string& testName,
    const std::string& message, int durationMs = 0, const std::string& stackTrace = "")
  {
    if (!Ok() || !Selected(fixture, testName)) return;
    if (IsDUnitRegistryRootName(fixture) || IsDUnitRegistryRootName(testName))
      return;
    FHost->PostResultsJson(HostClient::MakeResultJson(
      "Error", fixture, testName, testName, "", message, durationMs, stackTrace));
  }

  bool Allow(const std::string& fixture, const std::string& testName) const
  {
    return Selected(fixture, testName);
  }

private:
  std::shared_ptr<HostClient> FHost;
  std::vector<std::string> FSelected;
  bool FSelectFilter = false;

  bool Selected(const std::string& fixture, const std::string& testName) const
  {
    if (!FSelectFilter) return true;
    std::string full = fixture.empty() ? testName : (fixture + "." + testName);
    for (const auto& s : FSelected)
      if (s == full || s == testName) return true;
    return false;
  }
};

/**
 * Resolve Class.Method from DUnit ITest Name + suite stack.
 * Rejects registry-root / .exe names.
 */
inline bool ResolveLeafName(
  const System::UnicodeString& full,
  const std::vector<std::string>& suiteStack,
  std::string& fixture,
  std::string& testName)
{
  fixture.clear();
  testName.clear();
  std::string n = UnicodeToUtf8(full);
  if (n.empty() || IsDUnitRegistryRootName(n))
    return false;

  auto dot = n.rfind('.');
  if (dot != std::string::npos && dot + 1 < n.size()) {
    fixture = n.substr(0, dot);
    testName = n.substr(dot + 1);
    if (IsDUnitRegistryRootName(fixture) || IsDUnitRegistryRootName(testName))
      return false;
    return !fixture.empty() && !testName.empty();
  }

  // Bare method name — fixture = innermost suite on the stack
  if (suiteStack.empty())
    return false;
  fixture = suiteStack.back();
  testName = n;
  return !fixture.empty() && !testName.empty()
      && !IsDUnitRegistryRootName(fixture);
}

/** Walk RegisteredTests and POST Idle for each leaf (no execution). */
struct TDextDUnitTreeWalker {
  std::shared_ptr<DextDUnitReporter> Rep;
  std::vector<std::string> Stack;
  int LeafCount;

  void Walk(Testframework::_di_ITest test)
  {
    if (!test) return;
    const std::string name = UnicodeToUtf8(test->Name);
    const bool rootLike = IsDUnitRegistryRootName(name);

    if (IsLeafTest(test)) {
      std::string fixture, method;
      if (ResolveLeafName(test->Name, Stack, fixture, method)) {
        Rep->Idle(fixture, method);
        ++LeafCount;
      }
      return;
    }

    if (!rootLike && !name.empty())
      Stack.push_back(name);

    System::Classes::_di_IInterfaceList kids = test->Tests();
    if (kids) {
      for (int i = 0; i < kids->Count; ++i) {
        System::_di_IInterface iface = kids->Get(i);
        Testframework::_di_ITest child;
        if (iface && Supports(iface, __uuidof(Testframework::ITest), &child))
          Walk(child);
      }
    }

    if (!rootLike && !name.empty() && !Stack.empty() && Stack.back() == name)
      Stack.pop_back();
  }
};

inline int DiscoverRegisteredTests(const std::shared_ptr<DextDUnitReporter>& rep)
{
  if (!rep || !rep->Ok()) return 2;

  Testframework::_di_ITestSuite root = Testframework::RegisteredTests();
  if (!root) return 1;

  TDextDUnitTreeWalker walker;
  walker.Rep = rep;
  walker.LeafCount = 0;

  rep->TestingStarts(0);
  walker.Walk(static_cast<Testframework::_di_ITest>(root));
  rep->TestingEnds();
  return (walker.LeafCount > 0) ? 0 : 1;
}

/**
 * Bridges DUnit run events → Dext Host.
 */
class TDextDUnitListener : public Texttestrunner::TTextTestListener
{
private:
  std::shared_ptr<DextDUnitReporter> FRep;
  System::UnicodeString FCurrentName;
  bool FOutcomePosted;
  DWORD FStartTick;
  std::vector<std::string> FSuiteStack;

  int ElapsedMs() const
  {
    return static_cast<int>(GetTickCount() - FStartTick);
  }

public:
  __fastcall TDextDUnitListener(std::shared_ptr<DextDUnitReporter> rep)
    : Texttestrunner::TTextTestListener()
    , FRep(std::move(rep))
    , FOutcomePosted(false)
    , FStartTick(0)
  {
  }

  virtual void __fastcall TestingStarts()
  {
    Texttestrunner::TTextTestListener::TestingStarts();
    if (FRep) FRep->TestingStarts();
  }

  virtual void __fastcall TestingEnds(Testframework::TTestResult* testResult)
  {
    Texttestrunner::TTextTestListener::TestingEnds(testResult);
    if (FRep) FRep->TestingEnds();
  }

  virtual void __fastcall StartTest(Testframework::_di_ITest test)
  {
    Texttestrunner::TTextTestListener::StartTest(test);
    FOutcomePosted = false;
    FStartTick = GetTickCount();
    FCurrentName = test ? test->Name : System::UnicodeString();

    const std::string name = UnicodeToUtf8(FCurrentName);
    if (test && !IsLeafTest(test)) {
      if (!IsDUnitRegistryRootName(name) && !name.empty())
        FSuiteStack.push_back(name);
      return;
    }

    if (FRep) {
      std::string fixture, method;
      if (ResolveLeafName(FCurrentName, FSuiteStack, fixture, method))
        FRep->Running(fixture, method);
    }
  }

  virtual void __fastcall EndTest(Testframework::_di_ITest test)
  {
    Texttestrunner::TTextTestListener::EndTest(test);
    if (test && !IsLeafTest(test)) {
      const std::string name = UnicodeToUtf8(test->Name);
      if (!IsDUnitRegistryRootName(name) && !FSuiteStack.empty()
          && FSuiteStack.back() == name)
        FSuiteStack.pop_back();
    }
  }

  virtual void __fastcall AddSuccess(Testframework::_di_ITest test)
  {
    Texttestrunner::TTextTestListener::AddSuccess(test);
    if (!FRep || FOutcomePosted) return;
    std::string fixture, method;
    if (!ResolveLeafName(test ? test->Name : FCurrentName, FSuiteStack, fixture, method))
      return;
    FOutcomePosted = true;
    FRep->Passed(fixture, method, ElapsedMs());
  }

  /**
   * Stock dunitrtl CaptureStackTrace is empty unless JCL/madExcept.
   * Prefer NoteFailureStack() snapped before CheckEquals (deep call chains).
   * Else resolve ThrownExceptionAddress via EXE .map + ASLR.
   */
  static std::string FailureStackOrLocation(Testframework::TTestFailure* failure)
  {
    if (!failure) return std::string();
    std::string stack = UnicodeToUtf8(failure->StackTrace());
    if (!stack.empty()) return stack;

    stack = TakePendingFailureStack();
    if (!stack.empty())
      return stack;

    std::string resolved;
    void* thrownAddr = failure->ThrownExceptionAddress();
    if (thrownAddr)
      resolved = ResolveAddressViaExeMap(thrownAddr);
    if (!resolved.empty())
      return resolved;

    std::string loc = UnicodeToUtf8(failure->LocationInfo());
    std::string addr = UnicodeToUtf8(failure->AddressInfo());
    if (loc.empty() && addr.empty()) return std::string();
    if (!loc.empty() && !addr.empty()) return loc + "\n" + addr;
    return loc.empty() ? addr : loc;
  }

  virtual void __fastcall AddFailure(Testframework::TTestFailure* failure)
  {
    Texttestrunner::TTextTestListener::AddFailure(failure);
    if (!FRep || FOutcomePosted) return;
    System::UnicodeString nm = FCurrentName;
    System::UnicodeString msg;
    if (failure) {
      if (failure->FailedTest())
        nm = failure->FailedTest()->Name;
      msg = failure->ThrownExceptionMessage();
    }
    std::string fixture, method;
    if (!ResolveLeafName(nm, FSuiteStack, fixture, method)) return;
    FOutcomePosted = true;
    FRep->Failed(fixture, method, UnicodeToUtf8(msg), ElapsedMs(), FailureStackOrLocation(failure));
  }

  virtual void __fastcall AddError(Testframework::TTestFailure* error)
  {
    Texttestrunner::TTextTestListener::AddError(error);
    if (!FRep || FOutcomePosted) return;
    System::UnicodeString nm = FCurrentName;
    System::UnicodeString msg;
    if (error) {
      if (error->FailedTest())
        nm = error->FailedTest()->Name;
      msg = error->ThrownExceptionMessage();
    }
    std::string fixture, method;
    if (!ResolveLeafName(nm, FSuiteStack, fixture, method)) return;
    FOutcomePosted = true;
    FRep->Error(fixture, method, UnicodeToUtf8(msg), ElapsedMs(), FailureStackOrLocation(error));
  }

  virtual bool __fastcall ShouldRunTest(Testframework::_di_ITest test)
  {
    if (!Texttestrunner::TTextTestListener::ShouldRunTest(test))
      return false;
    if (!FRep) return true;
    if (!IsLeafTest(test))
      return true; // descend into suites
    std::string fixture, method;
    if (!ResolveLeafName(test ? test->Name : System::UnicodeString(), FSuiteStack, fixture, method))
      return false;
    return FRep->Allow(fixture, method);
  }
};

/**
 * Register a TTestCase subclass with DUnit (suite name = ClassName).
 * Prefer DEXT_DUNIT_REGISTER(TMyCase) at file scope instead of hand-rolled startup.
 */
template<typename TTestCaseClass>
inline void RegisterDunitTestCase()
{
  System::TMetaClass* meta = __classid(TTestCaseClass);
  Testframework::_di_ITestSuite suite;
  Testframework::TTestSuite* raw =
    new Testframework::TTestSuite(meta->ClassName());
  if (raw->GetInterface(__uuidof(Testframework::ITestSuite), &suite)) {
    raw->AddTests(meta);
    Testframework::RegisterTest(suite);
  }
  else {
    delete raw;
  }
}

/** Optional explicit suite name (when it must differ from ClassName). */
template<typename TTestCaseClass>
inline void RegisterDunitTestCase(const System::UnicodeString& suiteName)
{
  System::TMetaClass* meta = __classid(TTestCaseClass);
  Testframework::_di_ITestSuite suite;
  Testframework::TTestSuite* raw = new Testframework::TTestSuite(suiteName);
  if (raw->GetInterface(__uuidof(Testframework::ITestSuite), &suite)) {
    raw->AddTests(meta);
    Testframework::RegisterTest(suite);
  }
  else {
    delete raw;
  }
}

/**
 * --port N [--discover] [-no-wait]
 * Without --port: plain TextTestRunner (console).
 */
inline int RunDextDUnit(int argc, char** argv)
{
  int port = 0;
  if (!ParsePortFromArgv(argc, argv, port)) {
    Testframework::TTestResult* r =
      Texttestrunner::RunRegisteredTests(Texttestrunner::rxbContinue);
    if (!r) return 1;
    return (r->WasSuccessful()) ? 0 : 1;
  }

  auto rep = std::make_shared<DextDUnitReporter>(port);
  if (!rep->Ok()) {
    Texttestrunner::RunRegisteredTests(Texttestrunner::rxbContinue);
    return 2;
  }

  if (HasArgvFlag(argc, argv, "--discover") || HasArgvFlag(argc, argv, "-discover"))
    return DiscoverRegisteredTests(rep);

  { /* _di_ITestListener::operator& returns ITestListener** — never pass &intf to RunRegisteredTests. */
    TDextDUnitListener* listenerObj = new TDextDUnitListener(rep);
    Testframework::_di_ITestListener listeners[1];
    listeners[0] = static_cast<Texttestrunner::TTextTestListener&>(*listenerObj);
    Testframework::TTestResult* r =
      Testframework::RunRegisteredTests(listeners, 0);
    if (!r) return 1;
    return (r->WasSuccessful()) ? 0 : 1;
  }
}

} // namespace Testing
} // namespace Dext

/**
 * Optional helper: defines the startup function only.
 * bcc32c rejects #pragma inside macros — keep #pragma startup on its own line:
 *
 *   DEXT_DUNIT_REGISTER_FN(TSmokeTestCase)
 *   #pragma startup dext_dunit_register_TSmokeTestCase 33
 */
#define DEXT_DUNIT_REGISTER_FN(TClass)                                         \
  static void dext_dunit_register_##TClass()                                   \
  {                                                                            \
    ::Dext::Testing::RegisterDunitTestCase<TClass>();                          \
  }

#endif
