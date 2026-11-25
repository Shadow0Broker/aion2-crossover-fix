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
F="$HOME/.aion2fix"
if pgrep -f 'CrossOver.app/.*/wineserver' >/dev/null; then
  echo "CrossOver's own Wine is running. Quit Steam (and other bottle apps) in CrossOver first, then rerun." >&2
  exit 1
fi
cd "$F" || exit 1
# Set SIGDIAG_DIR="$F/diag" here to log what the shim does.
AION_SHIM="$F/ncgate.dylib" exec "$F/cx/bin/wine" --bottle Steam -- 'C:\Program Files (x86)\Steam\steam.exe' -applaunch 3393110
