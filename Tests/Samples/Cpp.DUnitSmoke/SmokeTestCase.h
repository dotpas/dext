#ifndef SmokeTestCaseH
#define SmokeTestCaseH

#include <TestFramework.hpp>

/**
 * DUnit C++ smoke — pass, direct fail (origin), and deep fail (Gateway→Auditor).
 */
class TSmokeTestCase : public TTestCase
{
public:
  __fastcall virtual TSmokeTestCase(System::UnicodeString name)
    : TTestCase(name) {}

  virtual void __fastcall SetUp();
  virtual void __fastcall TearDown();

__published:
  void __fastcall TestOnePlusOne();
  void __fastcall TestIntentionalFail();
  void __fastcall TestDeepCallFail();
};

#endif
