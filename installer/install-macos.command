#!/bin/bash
# Rejuvenation Co-op -- macOS setup (double-click in Finder).
# Installs the co-op mod into an existing Pokemon Rejuvenation V14 (Mac) install
# and writes the connection from a Join Code. This does NOT include the game.

REPO="sukjacode/rejuvenation-multiplayer"
BRANCH="main"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "==============================================="
echo "  Pokemon Rejuvenation Co-op -- macOS setup"
echo "==============================================="
echo
echo "For players joining a friend's game. You need your own"
echo "Pokemon Rejuvenation V14 (Mac) install."
echo

# ---------------------------------------------------------------------------
# 1) Locate the game
# ---------------------------------------------------------------------------
echo "Drag your Pokemon Rejuvenation folder or .app into this window,"
echo "then press Enter (or type the path):"
read -r GAMEPATH
# clean up a drag-and-dropped path (quotes, escaped spaces, trailing slash/space)
GAMEPATH="${GAMEPATH%\"}"; GAMEPATH="${GAMEPATH#\"}"
GAMEPATH="${GAMEPATH%\'}"; GAMEPATH="${GAMEPATH#\'}"
GAMEPATH="${GAMEPATH//\\ / }"
GAMEPATH="${GAMEPATH%% }"; GAMEPATH="${GAMEPATH%/}"

if [ -z "$GAMEPATH" ] || [ ! -e "$GAMEPATH" ]; then
  echo "!! That path does not exist. Aborting."
  read -n 1 -s -r -p "Press any key to close..."; exit 1
fi

# Find the game data root: the folder that contains Scripts/ or patch/ or Data/.
# On Mac that can be next to the .app or inside <App>/Contents/Resources.
find_root() {
  local base="$1"
  for cand in "$base" "$base/Contents/Resources" "$base/Contents/Game" "$base/Contents/MacOS"; do
    if [ -d "$cand/Scripts" ] || [ -d "$cand/patch" ] || [ -d "$cand/Data" ]; then
      echo "$cand"; return 0
    fi
  done
  local hit
  hit="$(find "$base" -maxdepth 4 -type d -name Scripts 2>/dev/null | head -1)"
  if [ -n "$hit" ]; then dirname "$hit"; return 0; fi
  return 1
}
ROOT="$(find_root "$GAMEPATH")"
if [ -z "$ROOT" ]; then
  echo "!! Could not find the game data (a Scripts/ or patch/ folder) under:"
  echo "   $GAMEPATH"
  echo "   Point this at your Rejuvenation folder or the .app."
  read -n 1 -s -r -p "Press any key to close..."; exit 1
fi
echo "-> Game data root: $ROOT"
echo

# ---------------------------------------------------------------------------
# 2) Install the mod
# ---------------------------------------------------------------------------
MODS="$ROOT/patch/Mods"
mkdir -p "$MODS"
MODSRC=""
for c in "$SCRIPT_DIR/../mod" "$SCRIPT_DIR/mod" "$SCRIPT_DIR"; do
  if [ -f "$c/coop.rb" ]; then MODSRC="$c"; break; fi
done
if [ -n "$MODSRC" ]; then
  cp "$MODSRC/coop.rb"      "$MODS/coop.rb"
  cp "$MODSRC/coop_menu.rb" "$MODS/coop_menu.rb"
  echo "-> Installed mod from bundle."
else
  echo "-> Mod files not bundled; downloading from GitHub..."
  if ! curl -fsSL -o "$MODS/coop.rb"      "https://raw.githubusercontent.com/$REPO/$BRANCH/mod/coop.rb" \
     || ! curl -fsSL -o "$MODS/coop_menu.rb" "https://raw.githubusercontent.com/$REPO/$BRANCH/mod/coop_menu.rb"; then
    echo "!! Download failed (no internet?). Aborting."
    read -n 1 -s -r -p "Press any key to close..."; exit 1
  fi
fi
echo "   patch/Mods/coop.rb + coop_menu.rb"
echo

# ---------------------------------------------------------------------------
# 3) Join Code -> coop_config.txt + coop_options.txt
# ---------------------------------------------------------------------------
echo "Paste the Join Code from your host, then press Enter:"
read -r CODE
CODE="$(printf '%s' "$CODE" | tr -d '[:space:]')"
DECODED="$(printf '%s' "$CODE" | base64 -D 2>/dev/null)"
[ -z "$DECODED" ] && DECODED="$(printf '%s' "$CODE" | base64 -d 2>/dev/null)"
[ -z "$DECODED" ] && DECODED="$(printf '%s' "$CODE" | base64 --decode 2>/dev/null)"

# format: v1|<ztnet>|<ip:port>|<token>
IFS='|' read -r VER ZTNET SERVER TOKEN <<< "$DECODED"
if [ "$VER" != "v1" ] || [ -z "$SERVER" ]; then
  echo "!! Invalid Join Code. Aborting."
  read -n 1 -s -r -p "Press any key to close..."; exit 1
fi

{
  echo "# written by install-macos.command"
  echo "server = $SERVER"
  echo "token  = $TOKEN"
} > "$ROOT/coop_config.txt"

{
  echo "# written by install-macos.command"
  echo "role            = join"
} > "$ROOT/coop_options.txt"

echo "-> Connection written: coop_config.txt (server $SERVER)"
echo "   (pre-game options come from the host automatically)"
echo

# ---------------------------------------------------------------------------
# 4) ZeroTier
# ---------------------------------------------------------------------------
echo "ZeroTier network to join: $ZTNET"
ZTCLI=""
for z in "zerotier-cli" "/usr/local/bin/zerotier-cli" "/Library/Application Support/ZeroTier/One/zerotier-cli"; do
  if command -v "$z" >/dev/null 2>&1 || [ -x "$z" ]; then ZTCLI="$z"; break; fi
done
if [ -n "$ZTCLI" ] && [ -n "$ZTNET" ]; then
  echo "Joining the ZeroTier network (may ask for your password)..."
  sudo "$ZTCLI" join "$ZTNET" || echo "   Join via CLI failed -- use the ZeroTier menu-bar app: Join Network -> $ZTNET"
  echo "   The HOST must authorize your device at my.zerotier.com (Members -> Auth)."
else
  echo "ZeroTier is not installed."
  echo "   Download: https://www.zerotier.com/download/"
  echo "   After installing, join network $ZTNET via the menu-bar app."
fi

echo
echo "==============================================="
echo "  Done! Start Pokemon Rejuvenation."
echo "  You'll see each other once you're on the same map."
echo "==============================================="
echo
read -n 1 -s -r -p "Press any key to close..."
echo
