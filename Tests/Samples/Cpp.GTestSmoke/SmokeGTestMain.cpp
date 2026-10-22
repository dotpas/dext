/**
 * C++Builder console MainSource.
 * GetIt gtest needs Delphi RTL = False — do not #include <System.hpp> here.
 * Put TEST() in SmokeGTestSuite.cpp / SmokeGTestDeep.cpp (normal units open fine).
 */

#pragma hdrstop

#include "DextGTestAdapter.hpp"

/* bcc64 (Clang 5) links gtest.a. bcc64x (Clang 20) and Win32 link gtest.lib.
   bcc64x defines _WIN64 and does not define _WIN64X. */
#if defined(_WIN64) && defined(__clang_major__) && (__clang_major__ < 15)
#pragma comment(lib, "gtest.a")
#else
#pragma comment(lib, "gtest.lib")
#endif

#pragma argsused
int main(int argc, char* argv[])
{
  return Dext::Testing::RunDextGTest(argc, argv);
}
