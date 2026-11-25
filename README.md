# AION 2 on macOS via CrossOver

Fix for AION 2 (NCGuard anti-cheat) crashing under CrossOver/Wine on Apple
Silicon — the game exits immediately or hangs with a Dock icon and no window.

Built and tested on CrossOver 26.3, macOS on Apple Silicon (Rosetta).

## How it works

NCGuard runs a CPUID check through a stub that switches to a 32-bit code
segment (`cs 0x23`) via `iretq`. That selector exists on Windows and Linux
but not macOS, so under Rosetta the stub faults before it runs and the game
dies. On top of that, CrossOver's signed `wine` binaries ignore
`DYLD_INSERT_LIBRARIES`, so a shim can't be injected the normal way.

This repo works around both:

1. `ncgate.c` — a dylib injected into Wine that interposes `sigaction`,
   recognizes NCGuard's stub, and emulates the exact fault Windows would
   have delivered so the game continues normally.
2. `install.sh` — makes a private copy of CrossOver's Wine, re-signs it with
   `ent.plist` (which permits `DYLD_*` env vars), and patches the wine
   launcher to forward `AION_SHIM` into `DYLD_INSERT_LIBRARIES`.
3. `launch-aion2.sh` — starts Steam inside the bottle with the shim loaded,
   then launches AION 2.

## Requirements

- Apple Silicon Mac (Intel Macs don't need any of this)
- CrossOver (developed against 26.x)
- AION 2 installed through the **Steam** version inside a CrossOver bottle
- Xcode Command Line Tools (`xcode-select --install`) for `clang`/`codesign`

## Install

```sh
git clone https://github.com/Shadow0Broker/aion2-crossover-fix.git
cd aion2-crossover-fix
./install.sh
```

If CrossOver isn't in `/Applications`, pass its path:

```sh
./install.sh ~/Downloads/CrossOver.app
```

The installer copies the shim into `~/.aion2fix`, builds the private Wine
copy (~1 GB, only once), re-signs it, patches the launcher, and compiles the
shim. Re-run it any time — it's safe to repeat.

### Manual setup (what install.sh does, if you prefer)

```sh
cp -R "/Applications/CrossOver.app/Contents/SharedSupport/CrossOver" ~/.aion2fix/cx
codesign -f -s - --options runtime --entitlements ~/.aion2fix/ent.plist \
  ~/.aion2fix/cx/bin/wineloader ~/.aion2fix/cx/lib/wine/x86_64-unix/wine
```

In `~/.aion2fix/cx/bin/wine`, directly above the line
`delete $ENV{CX_WINDOWS_VERSION};`, add:

```perl
$ENV{DYLD_INSERT_LIBRARIES}=$ENV{AION_SHIM} if $ENV{AION_SHIM};
```

```sh
clang -arch x86_64 -dynamiclib -O1 -o ~/.aion2fix/ncgate.dylib ~/.aion2fix/ncgate.c
```

### Bottle registry tweak (required)

In the Steam bottle's registry, disable the Steam overlay DLLs for the game —
NCGuard exits with `0xE0000012` if they're loaded:

```
HKCU\Software\Wine\AppDefaults\AION2.exe\DllOverrides
  gameoverlayrenderer   = ""
  gameoverlayrenderer64 = ""
```

(Easiest via `wine regedit` inside the bottle, or CrossOver's Registry Editor.)

## Usage

```sh
~/.aion2fix/launch-aion2.sh
```

- `--check` — run the preflight checks without launching
- `--diag`  — write shim fault logs to `~/.aion2fix/diag/`
- `-h`      — show the header comments

First boot can take a minute while Wine updates the prefix — the Steam
window appears when it's done.

**Important:** the shim only loads if Steam itself is started by the script.
Once Steam is running, you can launch/relaunch the game from Steam's library
normally. Do **not** use the `AION 2.app` or `Steam.app` shortcuts CrossOver
creates in `~/Applications/CrossOver/` — they start a separate, unshimmed
Wine session and the game will die with no window.

## Troubleshooting

**Game shows a Dock icon but no window**
The game was launched without the shim. Quit everything (Steam inside
CrossOver, the `AION 2.app` shortcut, CrossOver itself) and start over with
`launch-aion2.sh`, then press Play in Steam.

**"CrossOver's own Wine is running"**
The script refuses to start while CrossOver's Wine is up, because both would
share the bottle. Quit Steam and any bottle apps inside CrossOver first.

**CrossOver.app runs from a weird translocated path**
If you see `AppTranslocation` in process paths, the app is quarantined —
usually because it was launched straight from `~/Downloads` or a DMG.
Move it to `/Applications` and run:

```sh
xattr -dr com.apple.quarantine /Applications/CrossOver.app
```

**Game worked before, broke after a CrossOver update**
Rebuild the private copy: delete `~/.aion2fix/cx`, then re-run
`./install.sh`.

**wineboot / wine.inf appears stuck for a long time**
The bottle prefix is being rebuilt. Give it a few minutes; if it never
finishes, quit all Wine processes and run `launch-aion2.sh` again.

**Shim does nothing / want logs**
Run `launch-aion2.sh --diag`, reproduce the issue, then check
`~/.aion2fix/diag/sigdiag.*.log`.

## Uninstall

```sh
rm -rf ~/.aion2fix
```

(The bottle itself is untouched; the registry `DllOverrides` entry is
harmless to leave, or remove it via `wine regedit`.)

## Disclaimer

Unofficial fan fix, not affiliated with NCSoft, Steam, or CodeWeavers.
Anti-cheat bypasses exist in a gray area — use at your own risk, and never
use this on a machine where you'd mind an account flag. This only works
because the shim emulates standard Windows exception behavior; it doesn't
touch the game's code or anti-cheat checks themselves.

## License

MIT — see [LICENSE](LICENSE).
