# Windows 11 compatibility findings — 25 October 2026

Tested the exact published Honakari 14.0.5 x64 Free and Premium installers on free public GitHub Windows 11 ARM64 runners, under x64 emulation. Actual OS: Microsoft Windows 11 Enterprise, version 10.0.26200, build 26200. This is not an Intel/AMD Windows 11 laptop or a native ARM package.

Both editions passed installer hash verification, installation, bundled runtime/component checks without external Python on PATH, native WebView2 startup, and preservation of an expired trial on initial installation. Both installer signatures were confirmed NotSigned.

Both editions stopped at the physical mouse interaction check: the runner would not bring the isolated QA window into the foreground. A parent-launcher AppActivate helper was attempted on a fresh run; the same foreground guard still stopped the test. No protection was disabled and no failed interaction check was marked as passed.

Highlighting, companion interaction, audio output, the remaining reinstall/uninstall sequence and ordinary-laptop Windows 11 behavior are therefore not verified by these runs. The existing Windows 10 owner checks and Windows Server x64 automated checks are separate evidence. Keep the website's full Windows 11 verification claim disabled until the remaining checks pass on a suitable interactive machine.

Runs: https://github.com/Zorro0001/honakari-downloads/actions/runs/40230374423 and https://github.com/Zorro0001/honakari-downloads/actions/runs/40230605871 . Reports are attached to those runs.

No installer was changed, no certificate was bought and no payment was taken. These tests do not establish SmartScreen or Smart App Control acceptance on customer machines. The existing EXE downloads remain unsigned.
