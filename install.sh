#!/bin/zsh
# Install the AION 2 NCGuard shim into ~/.aion2fix.
#
#   ./install.sh [/path/to/CrossOver.app]
#
# Does the fiddly parts for you:
#   1. copies CrossOver's Wine into ~/.aion2fix/cx (a private copy we can re-sign)
#   2. re-signs wine/wineloader with ent.plist so DYLD_INSERT_LIBRARIES works
#   3. patches cx/bin/wine to forward AION_SHIM into DYLD_INSERT_LIBRARIES
#   4. builds ncgate.dylib from ncgate.c
#
# Afterwards you still need the Steam bottle with AION 2 installed, and the
# overlay DLL override (see README). Then run:  ~/.aion2fix/launch-aion2.sh

set -euo pipefail

F="$HOME/.aion2fix"
SRC="${0:A:h}"   # directory this script lives in (the cloned repo)

# --- locate CrossOver -------------------------------------------------------
CXAPP="${1:-}"
if [[ -z "$CXAPP" ]]; then
  for p in /Applications/CrossOver.app "$HOME/Applications/CrossOver.app" \
           "$HOME/Downloads/CrossOver.app"; do
    [[ -d "$p" ]] && CXAPP="$p" && break
  done
fi
[[ -n "$CXAPP" && -d "$CXAPP" ]] || {
  print -u2 "CrossOver.app not found. Pass its path: ./install.sh /path/to/CrossOver.app"
  exit 1
}
CXROOT="$CXAPP/Contents/SharedSupport/CrossOver"
[[ -d "$CXROOT" ]] || { print -u2 "$CXAPP doesn't look like CrossOver (no SharedSupport/CrossOver)"; exit 1; }

print "==> CrossOver: $CXAPP"

# --- copy shim files --------------------------------------------------------
mkdir -p "$F"
for f in launch-aion2.sh ncgate.c ent.plist README.md install.sh; do
  [[ -f "$SRC/$f" && ! "$SRC/$f" -ef "$F/$f" ]] && cp "$SRC/$f" "$F/$f"
done
chmod +x "$F/launch-aion2.sh"
print "==> shim files -> $F"

# --- private wine copy ------------------------------------------------------
if [[ -x "$F/cx/bin/wine" ]]; then
  print "==> cx/ already exists, leaving it alone (delete it to rebuild)"
else
  print "==> copying Wine support files (this is ~1 GB) ..."
  cp -R "$CXROOT" "$F/cx"
fi

# --- re-sign so macOS honors DYLD_INSERT_LIBRARIES --------------------------
print "==> re-signing wine binaries ..."
codesign -f -s - --options runtime --entitlements "$F/ent.plist" \
  "$F/cx/bin/wineloader" "$F/cx/lib/wine/x86_64-unix/wine"

# --- patch the wine launcher -------------------------------------------------
WINE="$F/cx/bin/wine"
if grep -q 'AION_SHIM' "$WINE"; then
  print "==> cx/bin/wine already patched"
else
  print "==> patching cx/bin/wine ..."
  # insert the DYLD_INSERT_LIBRARIES line directly above 'delete $ENV{CX_WINDOWS_VERSION};'
  awk '
    /delete \$ENV\{CX_WINDOWS_VERSION\};/ && !done {
      print "    $ENV{DYLD_INSERT_LIBRARIES}=$ENV{AION_SHIM} if $ENV{AION_SHIM}; # DYLD_* is stripped by system perl, re-add here"
      done=1
    }
    { print }
  ' "$WINE" > "$WINE.tmp" && mv "$WINE.tmp" "$WINE"
  chmod +x "$WINE"
  grep -q 'AION_SHIM' "$WINE" || { print -u2 "patch failed — add the line by hand (see README)"; exit 1; }
fi

# --- build the shim ----------------------------------------------------------
print "==> building ncgate.dylib ..."
clang -arch x86_64 -dynamiclib -O1 -o "$F/ncgate.dylib" "$F/ncgate.c"

cat <<EOF

Done. Two manual steps remain:

  1. In your Steam bottle's registry, disable the Steam overlay for AION2.exe
     (NCGuard exits with 0xE0000012 otherwise):

       HKCU\\Software\\Wine\\AppDefaults\\AION2.exe\\DllOverrides
         gameoverlayrenderer   = ""
         gameoverlayrenderer64 = ""

  2. Launch with:  $F/launch-aion2.sh

Quit Steam inside CrossOver first — the shim only loads if Steam itself is
started by the script. Don't use the "AION 2.app" shortcut CrossOver makes.
EOF
