#ifndef DextGTestAdapter_HPP
#define DextGTestAdapter_HPP

/**
 * Google Test → Dext Test Explorer (HTTP Host, --port protocol).
 *
 * Model (same spirit as DUnit adapter):
 *   --port N --discover   walk registered GTests, POST Idle (no execution)
 *   --port N              run (selected via GET /tests) or all; POST Running/Passed/Failed
 *   (no --port)           normal RUN_ALL_TESTS() console
 *
 * Usage:
 *   #include "DextGTestAdapter.hpp"
 *   int main(int argc, char** argv) {
 *     return Dext::Testing::RunDextGTest(argc, argv);
 *   }
 *
 * Requires Google Test on include/lib path (GetIt Package Manager).
 */

#include "DextTestingHost.hpp"
#include "DextMapResolve.hpp"
#include "DextReportWriter.hpp"

/* bcc32c W6759: GTest puts [[maybe_unused]] on sites Clang-Embarcadero rejects.
   Leave ignored for the rest of the TU (covers later TEST() expansions). */
#if defined(__clang__)
#pragma clang diagnostic ignored "-Wattributes"
#endif
#pragma warn -6759
#include <gtest/gtest.h>

#include <chrono>
#include <memory>
#include <string>
#include <vector>

namespace Dext {
namespace Testing {

/** Leaf name only — Explorer OpenModule / FindUnitFileByName. */
inline std::string UnitLeafName(const char* file)
{
  if (!file || !file[0])
    return std::string();
  std::string s(file);
  const auto slash = s.find_last_of("\\/");
  if (slash != std::string::npos)
    return s.substr(slash + 1);
  return s;
}

/**
 * Prefer NoteFailureStack() snapped before EXPECT (deep chains).
 * Else capture here — OnTestPartResult still runs inside the failing call stack.
 * Last resort: "[0] Method @ File.cpp:line" so Explorer columns stay Method | Location.
 */
inline std::string GTestFailureStackOrLocation(
  const ::testing::TestPartResult& part, const std::string& methodHint)
{
  StackDiagLogf("GTestFailureStackOrLocation: methodHint=%s assert=%s:%d",
    methodHint.c_str(),
    part.file_name() ? part.file_name() : "(null)",
    part.line_number());

  std::string stack = TakePendingFailureStack();
  if (!stack.empty()) {
    StackDiagLogf("GTestFailureStackOrLocation: USING PENDING chars=%u",
      static_cast<unsigned>(stack.size()));
    return stack;
  }

  // CaptureResolvedCallStack is inline — skip only this wrapper frame (not 2).
  stack = CaptureResolvedCallStack(1);
  if (!stack.empty()) {
    StackDiagLogf("GTestFailureStackOrLocation: USING LIVE CAPTURE chars=%u",
      static_cast<unsigned>(stack.size()));
    return stack;
  }

  const std::string leaf = UnitLeafName(part.file_name());
  if (leaf.empty()) {
    StackDiagLog("GTestFailureStackOrLocation: FALLBACK failed (no file)");
    return std::string();
  }
  std::string fileHint = leaf;
  if (part.line_number() > 0)
    fileHint += ":" + std::to_string(part.line_number());
  const std::string method = methodHint.empty() ? std::string("(assert)") : methodHint;
  stack = FormatIndexedFrame(0, method, fileHint);
  StackDiagLogf("GTestFailureStackOrLocation: USING GTEST FALLBACK %s", stack.c_str());
  return stack;
}

class DextGTestListener : public ::testing::EmptyTestEventListener {
public:
  explicit DextGTestListener(std::shared_ptr<HostClient> host)
    : FHost(std::move(host)), FFailed(false) {}

  void OnTestProgramStart(const ::testing::UnitTest& unit_test) override
  {
    if (FHost && FHost->Ok())
      FHost->PostStarted(unit_test.total_test_count());
  }

  void OnTestStart(const ::testing::TestInfo& info) override
  {
    FFailed = false;
    FMessage.clear();
    FStack.clear();
    FAssertFile.clear();
    FAssertLine = 0;
    FMethodHint = TestName(info);
    StackDiagLogf("OnTestStart: %s.%s (clear pending)",
      SuiteName(info).c_str(), TestName(info).c_str());
    TakePendingFailureStack(); // drop stale snap from a prior test
    FStart = std::chrono::steady_clock::now();
    if (!FHost || !FHost->Ok()) return;
    if (!Selected(info)) return;
    FHost->PostResultsJson(HostClient::MakeResultJson(
      "Running",
      SuiteName(info),
      TestName(info),
      TestName(info),
      FileName(info),
      "",
      0,
      "",
      LineNumber(info)));
  }

  void OnTestPartResult(const ::testing::TestPartResult& part) override
  {
    if (!part.failed()) return;
    FFailed = true;
    if (part.message())
      FMessage = part.message();
    StackDiagLogf("OnTestPartResult: FAIL methodHint=%s crumbs=%u",
      FMethodHint.c_str(),
      static_cast<unsigned>(FailureStackBreadcrumbs().size()));
    FStack = GTestFailureStackOrLocation(part, FMethodHint);
    StackDiagLogf("OnTestPartResult: FStack chars=%u",
      static_cast<unsigned>(FStack.size()));
    // Prefer assert site over the TEST macro line for Explorer navigate.
    if (part.file_name() && part.file_name()[0])
      FAssertFile = UnitLeafName(part.file_name());
    if (part.line_number() > 0)
      FAssertLine = part.line_number();
  }

  void OnTestEnd(const ::testing::TestInfo& info) override
  {
    if (!Selected(info)) return;
    auto ms = static_cast<int>(
      std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::steady_clock::now() - FStart).count());
    const char* type = "Passed";
    if (info.result() && info.result()->Skipped())
      type = "Ignored";
    else if (FFailed || (info.result() && info.result()->Failed()))
      type = "Failed";
    const std::string unit = (!FAssertFile.empty() && FFailed) ? FAssertFile : FileName(info);
    const int line = (FAssertLine > 0 && FFailed) ? FAssertLine : LineNumber(info);
    ReportSink::Instance().Add(SuiteName(info), TestName(info),
      ReportStatusFromType(type), FMessage, FStack, ms, unit);
    if (!FHost || !FHost->Ok()) return;
    if (!Selected(info)) return;
    if (FFailed || (type && type[0] == 'F')) {
      StackDiagLogf("OnTestEnd: POST Failed %s.%s stackChars=%u line=%d unit=%s",
        SuiteName(info).c_str(), TestName(info).c_str(),
        static_cast<unsigned>(FStack.size()), line, unit.c_str());
      if (!FStack.empty())
        StackDiagLogf("OnTestEnd: stack posted=\n%s", FStack.c_str());
      else
        StackDiagLog("OnTestEnd: WARNING empty FStack posted to Host");
    }
    FHost->PostResultsJson(HostClient::MakeResultJson(
      type,
      SuiteName(info),
      TestName(info),
      TestName(info),
      unit,
      FMessage,
      ms,
      FStack,
      line));
  }

  void OnTestProgramEnd(const ::testing::UnitTest& /*unit_test*/) override
  {
    if (FHost && FHost->Ok())
      FHost->PostFinished();
    ReportSink::Instance().Write();
  }

  void PrepareSelection() { LoadSelection(); }

private:
  std::shared_ptr<HostClient> FHost;
  std::vector<std::string> FSelected;
  bool FFailed;
  std::string FMessage;
  std::string FStack;
  std::string FMethodHint;
  std::string FAssertFile;
  int FAssertLine = 0;
  std::chrono::steady_clock::time_point FStart;
  bool FSelectFilter = false;

  static std::string SuiteName(const ::testing::TestInfo& info)
  {
    return info.test_suite_name() ? info.test_suite_name() : "";
  }

  static std::string TestName(const ::testing::TestInfo& info)
  {
    return info.name() ? info.name() : "";
  }

  static std::string FileName(const ::testing::TestInfo& info)
  {
    return UnitLeafName(info.file());
  }

  static int LineNumber(const ::testing::TestInfo& info)
  {
    return info.line() > 0 ? info.line() : 0;
  }

  void LoadSelection()
  {
    if (!FHost) return;
    FSelected = FHost->GetSelectedTests();
    FSelectFilter = !FSelected.empty();
  }

  bool Selected(const ::testing::TestInfo& info) const
  {
    if (!FSelectFilter) return true;
    std::string full = SuiteName(info) + "." + TestName(info);
    const std::string leaf = TestName(info);
    for (const auto& s : FSelected)
      if (s == full || s == leaf)
        return true;
    return false;
  }
};

/** Walk GTest registry and POST Idle (Refresh / --discover). */
inline int DiscoverGTests(const std::shared_ptr<HostClient>& host)
{
  if (!host || !host->Ok())
    return 2;

  auto* ut = ::testing::UnitTest::GetInstance();
  if (!ut)
    return 1;

  host->PostStarted(ut->total_test_count());
  int posted = 0;
  for (int i = 0; i < ut->total_test_suite_count(); ++i) {
    const ::testing::TestSuite* suite = ut->GetTestSuite(i);
    if (!suite) continue;
    const char* suiteName = suite->name() ? suite->name() : "";
    for (int j = 0; j < suite->total_test_count(); ++j) {
      const ::testing::TestInfo* info = suite->GetTestInfo(j);
      if (!info) continue;
      const char* name = info->name() ? info->name() : "";
      host->PostResultsJson(HostClient::MakeResultJson(
        "Idle", suiteName, name, name, UnitLeafName(info->file()), "", 0, "",
        info->line() > 0 ? info->line() : 0));
      ++posted;
    }
  }
  host->PostFinished();
  return (posted > 0) ? 0 : 1;
}

/**
 * InitGoogleTest + optional Host listener / discover.
 * Prefer this over calling InitDextGTest + RUN_ALL_TESTS by hand.
 */
inline int RunDextGTest(int argc, char** argv)
{
  ReportSink::CaptureArgv(argc, argv);
  const HostLaunch launch = TakeHostLaunch(argc, argv);
  ::testing::InitGoogleTest(&argc, argv);

  if (launch.Port <= 0) {
    StackDiagRunBanner("RunDextGTest/console");
    auto* listener = new DextGTestListener(std::shared_ptr<HostClient>());
    ::testing::UnitTest::GetInstance()->listeners().Append(listener);
    return RUN_ALL_TESTS();
  }

  auto host = std::make_shared<HostClient>(launch.Port);
  if (!host->Ok()) {
    StackDiagRunBanner("RunDextGTest/host-fail-console");
    return RUN_ALL_TESTS();
  }

  if (launch.Discover) {
    StackDiagRunBanner("RunDextGTest/discover");
    return DiscoverGTests(host);
  }

  StackDiagRunBanner("RunDextGTest/host-run");
  auto* listener = new DextGTestListener(host);
  listener->PrepareSelection();
  ::testing::UnitTest::GetInstance()->listeners().Append(listener);
  return RUN_ALL_TESTS();
}

/** @deprecated Prefer RunDextGTest — kept for the .example snippet. */
inline void InitDextGTest(int argc, char** argv)
{
  int port = 0;
  if (!ParsePortFromArgv(argc, argv, port))
    return;
  auto host = std::make_shared<HostClient>(port);
  if (!host->Ok())
    return;
  auto* listener = new DextGTestListener(host);
  listener->PrepareSelection();
  ::testing::UnitTest::GetInstance()->listeners().Append(listener);
}

} // namespace Testing
} // namespace Dext

#endif
