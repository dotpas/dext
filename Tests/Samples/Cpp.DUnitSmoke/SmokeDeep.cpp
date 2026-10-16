#include <System.hpp>
#pragma hdrstop

#include "SmokeDeep.h"
#include "DextMapResolve.hpp"

int TSmokeLedger::Balance()
{
  return 3;
}

void TSmokeAuditor::RequireBalance(TTestCase* test, int expected)
{
  Dext::Testing::FailureStackScope scope(
    "TSmokeAuditor::RequireBalance", "SmokeDeep.cpp");
  // Snap while Gateway + test scopes are still on the breadcrumb stack.
  Dext::Testing::NoteFailureStack();
  test->CheckEquals(expected, TSmokeLedger::Balance(),
    System::UnicodeString(L"deep chain fail for Explorer stack"));
}

void TSmokeGateway::RunBalanceCheck(TTestCase* test, int expected)
{
  Dext::Testing::FailureStackScope scope(
    "TSmokeGateway::RunBalanceCheck", "SmokeDeep.cpp");
  TSmokeAuditor::RequireBalance(test, expected);
}
