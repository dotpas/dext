# Install the Dext Test Explorer by hand

22 October 2026.

The Dext Test Explorer already runs inside RAD Studio: it discovers the suite, runs it, opens the failing line, and paints line coverage when the platform has a line source. Soon we will offer a simpler way to install the expert directly in the IDE, possibly through GetIt. Anyone who wants to look now builds the DLL and registers it with the script.

We are still deciding whether to publish a compiled DLL. The expert is not digitally signed. A development certificate has a cost, and without that signature Windows treats the file as a plugin from an unknown publisher. Build it on your machine. Do not use a loose DLL.

The steps, including the build commands, the register script and the Win64x coverage flags, are in the book:

[Dext Test Explorer — manual install](../Book/08-testing/test-explorer.md)

The same text in Portuguese: [instalação manual](../Book.pt-br/08-testes/test-explorer.md).

What you can use today: discover and run a `.dproj` with `Dext.Testing`, a DUnit `.cbproj` (`Tests\Samples\Cpp.DUnitSmoke\DextDUnitSmokeTestsP.cbproj`), and a Google Test `.cbproj` (`Tests\Samples\Cpp.GTestSmoke\DextGTestSmokeTests.cbproj`). Delphi line coverage needs the detailed map and Delphi Code Coverage. On C++Builder, line coverage stays on Win64x (`bcc64x`), with `llvm-cov`. On the other `.cbproj` platforms the Explorer hides those options. This is not an Embarcadero feature.
