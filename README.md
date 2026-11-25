# AION 2 on macOS via CrossOver

Fix for AION 2 (NCGuard anti-cheat) failing under CrossOver/Wine on Apple
Silicon — game exits immediately or hangs with no window.

## The problem

NCGuard runs a CPUID check through a stub that switches to a 32-bit code
segment (`cs 0x23`) via `iretq`. That selector exists on Windows and Linux
but not macOS, so under Rosetta the stub faults before it runs and the game
dies. On top of that, CrossOver's signed `wine` binaries ignore
`DYLD_INSERT_LIBRARIES`, so the shim can't be injected normally.

## What's here

- `launch-aion2.sh` — launches Steam inside the CrossOver "Steam" bottle with
  the shim loaded
- `ncgate.c` — the shim. Interposes `sigaction`, detects NCGuard's stub,
  emulates the fault Windows would deliver, and lets the game continue
- `ent.plist` — entitlements used to re-sign the private Wine copy so macOS
  honors `DYLD_INSERT_LIBRARIES`

## Setup

Requires CrossOver (developed against 26.3) and the Steam version of AION 2.

```sh
# 1. Private copy of CrossOver's Wine, re-signed with entitlements
cp -R "/Applications/CrossOver.app/Contents/SharedSupport/CrossOver" ~/.aion2fix/cx
codesign -f -s - --options runtime --entitlements ~/.aion2fix/ent.plist \
  ~/.aion2fix/cx/bin/wineloader ~/.aion2fix/cx/lib/wine/x86_64-unix/wine

# 2. Hook DYLD_INSERT_LIBRARIES into the wine launcher.
#    In ~/.aion2fix/cx/bin/wine, directly above the line
#    'delete $ENV{CX_WINDOWS_VERSION};' add:
#      $ENV{DYLD_INSERT_LIBRARIES}=$ENV{AION_SHIM} if $ENV{AION_SHIM};

# 3. Build the shim
clang -arch x86_64 -dynamiclib -O1 -o ~/.aion2fix/ncgate.dylib ~/.aion2fix/ncgate.c
```

In the Steam bottle's registry, disable the Steam overlay DLLs for the game
(NCGuard exits with `0xE0000012` otherwise):

```
HKCU\Software\Wine\AppDefaults\AION2.exe\DllOverrides
  gameoverlayrenderer  = ""
  gameoverlayrenderer64 = ""
```

Then run `./launch-aion2.sh`. Quit Steam inside CrossOver first — the shim
only loads if Steam itself is started by the script. Don't launch the game
through the `AION 2.app` shortcut CrossOver creates; that bypasses the shim.

## Notes

- Rebuild `cx/` after a CrossOver update (steps above).
- Set `SIGDIAG_DIR=~/.aion2fix/diag` before running the script to get fault
  logs from the shim.
- Only tested on Apple Silicon under Rosetta.
