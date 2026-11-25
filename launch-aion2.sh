#!/bin/zsh
# Launch AION 2 (Steam, CrossOver bottle "Steam") with the NCGuard compatibility shim.
# Quit Steam inside CrossOver first: the shim only loads if Steam itself is started by this script.
#
# Why a private Wine copy: CrossOver's own wine is signed so that macOS ignores DYLD_INSERT_LIBRARIES.
# To rebuild after a CrossOver update (or if this folder is lost):
#   cp -R /path/to/CrossOver.app/Contents/SharedSupport/CrossOver ~/.aion2fix/cx
#   codesign -f -s - --options runtime --entitlements ~/.aion2fix/ent.plist ~/.aion2fix/cx/bin/wineloader ~/.aion2fix/cx/lib/wine/x86_64-unix/wine
#   add to cx/bin/wine, just above 'delete $ENV{CX_WINDOWS_VERSION};':
#     $ENV{DYLD_INSERT_LIBRARIES}=$ENV{AION_SHIM} if $ENV{AION_SHIM};
#   clang -arch x86_64 -dynamiclib -O1 -o ~/.aion2fix/ncgate.dylib ~/.aion2fix/ncgate.c
# The bottle also has the Steam overlay DLLs disabled for AION2.exe (NCGuard exits with 0xE0000012 otherwise):
#   HKCU\Software\Wine\AppDefaults\AION2.exe\DllOverrides  gameoverlayrenderer / gameoverlayrenderer64 = ""
#
# Usage: launch-aion2.sh [--diag] [--check]
#   --diag   log shim faults to ~/.aion2fix/diag/
#   --check  run preflight checks only, don't launch

set -u

F="$HOME/.aion2fix"
BOTTLE="$HOME/Library/Application Support/CrossOver/Bottles/Steam"
STEAM_EXE='C:\Program Files (x86)\Steam\steam.exe'
APPID=3393110

# --- palette ---------------------------------------------------------------
if [[ -t 1 ]]; then
  R=$'\e[0m'; DIM=$'\e[2m'; B=$'\e[1m'
  CY=$'\e[36m'; BL=$'\e[34m'; GR=$'\e[32m'; Y=$'\e[33m'; RD=$'\e[31m'
else
  R=""; DIM=""; B=""; CY=""; BL=""; GR=""; Y=""; RD=""
fi

say()  { print -r -- "${BL}▸${R} $*"; }
ok()   { print -r -- "  ${GR}✔${R} $*"; }
warn() { print -r -- "  ${Y}⚠${R} $*"; }
die()  { print -r -- "  ${RD}✘${R} $*" >&2; exit 1; }

banner() {
  print -r -- "${CY}${B}"
  cat <<'EOF'
   ___  _  _____ ___ ____  _   _ ____  ____  ____
  / _ \| |/ /_ _|_ _/ ___|| | | |  _ \|  _ \| __ )
 | | | | ' / | | | || |    | |_| | |_) | |_) |  _ \
 | |_| | . \ | | | || |___ |  _  |  __/|  _ <| |_) |
  \___/|_|\_\___|___\____||_| |_|_|   |_| \_\____/
EOF
  print -r -- "${R}${DIM}   NCGuard compatibility shim  ·  CrossOver / Wine  ·  Apple Silicon${R}"
  print
}

DIAG=0; CHECK=0
for a in "$@"; do
  case "$a" in
    --diag)  DIAG=1 ;;
    --check) CHECK=1 ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) die "unknown flag: $a (try --help)" ;;
  esac
done

banner

# --- preflight -------------------------------------------------------------
fail=0

if [[ -x "$F/cx/bin/wine" ]]; then ok "private wine copy"; else
  warn "private wine copy missing — rebuild it (see header comments)"; fail=1
fi

if [[ -f "$F/ncgate.c" ]]; then ok "shim source (ncgate.c)"; else fail=1; warn "ncgate.c missing"; fi

if [[ ! -f "$F/ncgate.dylib" && -f "$F/ncgate.c" ]]; then
  say "building ncgate.dylib ..."
  clang -arch x86_64 -dynamiclib -O1 -o "$F/ncgate.dylib" "$F/ncgate.c" \
    && ok "shim built" || { warn "clang build failed"; fail=1; }
fi
[[ -f "$F/ncgate.dylib" ]] && ok "shim binary (ncgate.dylib)" || fail=1

if [[ -d "$BOTTLE" ]]; then ok "Steam bottle"; else warn "bottle not found: $BOTTLE"; fail=1; fi

if pgrep -f 'CrossOver.app/.*/wineserver' >/dev/null; then
  die "CrossOver's own Wine is running. Quit Steam (and other bottle apps) in CrossOver first, then rerun."
fi
ok "no conflicting CrossOver wine session"

(( CHECK )) && { print; ok "preflight passed"; exit $fail; }
(( fail )) && die "fix the items above and rerun"

# --- launch ----------------------------------------------------------------
print
say "launching Steam + AION 2 (appid $APPID) ..."
print "${DIM}   the Steam window can take a minute on first boot — this terminal${R}"
print "${DIM}   stays attached until you quit the game.${R}"
print

cd "$F" || exit 1
if (( DIAG )); then
  mkdir -p "$F/diag"
  SIGDIAG_DIR="$F/diag" AION_SHIM="$F/ncgate.dylib" \
    exec "$F/cx/bin/wine" --bottle Steam -- "$STEAM_EXE" -applaunch "$APPID"
fi
AION_SHIM="$F/ncgate.dylib" exec "$F/cx/bin/wine" --bottle Steam -- "$STEAM_EXE" -applaunch "$APPID"
