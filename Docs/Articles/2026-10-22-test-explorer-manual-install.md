# Install the Dext Test Explorer by hand

22 October 2026.

The Dext Test Explorer already runs inside RAD Studio: it discovers the suite, runs it, opens the failing line, and paints line coverage when the platform has a line source. The distribution we want is GetIt. Anyone who wants to look now installs from source.

We are still deciding whether to publish a compiled DLL. The expert is not digitally signed. A development certificate has a cost, and without that signature Windows treats the file as a plugin from an unknown publisher. Build it on your machine. Do not use a loose DLL.

The steps, including the build commands, the register script and the Win64x coverage flags, are in the book:

[Dext Test Explorer — manual install](../Book/08-testing/test-explorer.md)

The same text in Portuguese: [instalação manual](../Book.pt-br/08-testes/test-explorer.md).

What you can use today: a Delphi suite with a detailed map and Delphi Code Coverage; a C++ suite only on the Win64x platform (`bcc64x`), with `llvm-cov`. Win32 and classic Win64 have no line coverage, and the Explorer hides those options so they do not look available. This is not an Embarcadero feature.
