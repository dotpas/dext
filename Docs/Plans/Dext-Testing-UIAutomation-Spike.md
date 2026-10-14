# Spike — UI Automation / UI testing (Delphi 13)

**Status:** Spike notes only (Fase 4)  
**Context:** RAD Studio 13 (Florence) announced VCL integration with Microsoft UI Automation for accessibility and automated UI testing. Community reports: headers/`TUIAutomationCustomControlProvider` exist; ready-made control coverage and samples are still thin.

## Questions for the spike

1. Can stock VCL controls be driven by Inspect.exe / WinAppDriver without custom providers?
2. What does a minimal Dext-owned harness look like vs documenting third-party clients?
3. Does this belong in the Testing book (likely **no** for PT v1) or a later volume / blog?

## Non-goals now

- Shipping `Assert.That(Form)...` API in this track.
- Blocking Embarcadero pitch or Cap. 18b on UIA.

## Next concrete step

Half-day lab: blank VCL form on Delphi 13 → Inspect tree → one WinAppDriver or UIA client click → write findings into this file.
