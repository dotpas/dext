#ifndef SmokeGTestDeepH
#define SmokeGTestDeepH

/**
 * Multi-hop helpers for GTest stack-trace smoke:
 *   DeepCallFail → Gateway → Auditor → NoteFailureStack + EXPECT_EQ
 *
 * Same idea as Cpp.DUnitSmoke SmokeDeep — snap the chain before the assert
 * so the MAP resolve still sees Gateway + test frames.
 */
namespace SmokeGTest {

class Ledger
{
public:
  static int Balance();
};

class Auditor
{
public:
  static void RequireBalance(int expected);
};

class Gateway
{
public:
  static void RunBalanceCheck(int expected);
};

} // namespace SmokeGTest

#endif
