/**
 * C++Builder console MainSource.
 * GetIt gtest needs Delphi RTL = False — do not #include <System.hpp> here.
 * Put TEST() in SmokeGTestSuite.cpp / SmokeGTestDeep.cpp (normal units open fine).
 */

#pragma hdrstop

#include "DextGTestAdapter.hpp"

#if defined(_WIN64) && !defined(_WIN64X)
#pragma comment(lib, "gtest.a")
#else
#pragma comment(lib, "gtest.lib")
#endif

#pragma argsused
int main(int argc, char* argv[])
{
  return Dext::Testing::RunDextGTest(argc, argv);
}
