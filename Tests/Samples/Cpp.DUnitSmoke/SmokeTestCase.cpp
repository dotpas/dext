#include <System.hpp>
#pragma hdrstop

#include "SmokeTestCase.h"
#include "SmokeDeep.h"
#include "DextDUnitCppAdapter.hpp"
#include "DextMapResolve.hpp"

void __fastcall TSmokeTestCase::SetUp()
{
}

void __fastcall TSmokeTestCase::TearDown()
{
}

void __fastcall TSmokeTestCase::TestOnePlusOne()
{
  CheckEquals(2, 1 + 1, System::UnicodeString(L"1+1 should be 2"));
}

void __fastcall TSmokeTestCase::TestIntentionalFail()
{
  CheckEquals(2, 1 + 2, System::UnicodeString(L"intentional fail for Explorer smoke"));
}

void __fastcall TSmokeTestCase::TestDeepCallFail()
{
  Dext::Testing::FailureStackScope scope("TestDeepCallFail", "SmokeTestCase.cpp");
  TSmokeGateway::RunBalanceCheck(this, 2);
}

static void registerSmokeTests()
{
  Dext::Testing::RegisterDunitTestCase<TSmokeTestCase>();
}
#pragma startup registerSmokeTests 33
