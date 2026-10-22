/**
 * Dext DUnit C++ smoke — console host for Test Explorer.
 *
 * Project must use Win32 Clang (not classic bcc32) — see README.
 * Include path: ..\..\..\Sources\Testing\Cpp
 */

#include <System.hpp>
#pragma hdrstop

#include "DextDUnitCppAdapter.hpp"
#include "SmokeTestCase.h"

#pragma argsused
int main(int argc, char* argv[])
{
  return Dext::Testing::RunDextDUnit(argc, argv);
}
