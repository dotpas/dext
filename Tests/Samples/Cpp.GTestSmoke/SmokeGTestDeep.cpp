#include "SmokeGTestDeep.h"
#include "DextMapResolve.hpp"

#if defined(__clang__)
#pragma clang diagnostic ignored "-Wattributes"
#endif
#pragma warn -6759
#include <gtest/gtest.h>

namespace SmokeGTest {

__declspec(noinline) int Ledger::Balance()
{
  return 3;
}

__declspec(noinline) void Auditor::RequireBalance(int expected)
{
  Dext::Testing::FailureStackScope scope(
    "SmokeGTest::Auditor::RequireBalance", "SmokeGTestDeep.cpp");
  // Snap while Gateway + DeepCallFail scopes are still on the breadcrumb stack.
  Dext::Testing::NoteFailureStack();
  EXPECT_EQ(expected, Ledger::Balance()) << "deep chain fail for Explorer stack";
}

__declspec(noinline) void Gateway::RunBalanceCheck(int expected)
{
  Dext::Testing::FailureStackScope scope(
    "SmokeGTest::Gateway::RunBalanceCheck", "SmokeGTestDeep.cpp");
  Auditor::RequireBalance(expected);
}

} // namespace SmokeGTest

TEST(SmokeSuite, DeepCallFail)
{
  Dext::Testing::FailureStackScope scope("DeepCallFail", "SmokeGTestDeep.cpp");
  SmokeGTest::Gateway::RunBalanceCheck(2);
}
