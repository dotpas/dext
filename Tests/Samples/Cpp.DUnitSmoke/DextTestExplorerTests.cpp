//---------------------------------------------------------------------------
// DUnit Project File.
//   Entry point of C++ project using DUnit framework.
//---------------------------------------------------------------------------
#include <System.hpp>
#pragma hdrstop

#include <tchar.h>
#include <XMLTestRunner.hpp>

int _tmain(int /*argc*/, _TCHAR */*argv*/[])
{
  Xmltestrunner::RunRegisteredTests();
  return 0;
}
