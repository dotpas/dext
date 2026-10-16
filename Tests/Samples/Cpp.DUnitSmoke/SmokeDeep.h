#ifndef SmokeDeepH
#define SmokeDeepH

#include <TestFramework.hpp>

/**
 * Multi-hop helpers for stack-trace smoke:
 *   TestDeepCallFail → TSmokeGateway → TSmokeAuditor → CheckEquals
 *
 * NoteFailureStack() runs in the auditor *before* CheckEquals so the MAP
 * resolve still sees Gateway + test frames (DUnit alone only keeps ExceptAddr).
 */
class TSmokeLedger
{
public:
  static int Balance();
};

class TSmokeAuditor
{
public:
  static void RequireBalance(TTestCase* test, int expected);
};

class TSmokeGateway
{
public:
  static void RunBalanceCheck(TTestCase* test, int expected);
};

#endif
