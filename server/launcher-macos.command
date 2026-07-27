#!/bin/bash
# Rejuvenation Co-op -- macOS launcher (Terminal menu). Double-click in Finder.
# Counterpart to the Windows launcher (launcher-gui.ps1). Host or join a co-op
# session, set pre-game options, manage ZeroTier. Does NOT include the game.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SETTINGS="$SCRIPT_DIR/launcher_settings_mac.conf"
TOKENFILE="$SCRIPT_DIR/token.txt"
RELAYJS="$SCRIPT_DIR/relay.js"
RELAYPORT=7777
REPO="sukjacode/rejuvenation-multiplayer"
BRANCH="main"
RELAYPIDFILE="$SCRIPT_DIR/.relay.pid"

# --- settings (simple key=value file) ---------------------------------------
get_setting() { [ -f "$SETTINGS" ] && grep -E "^$1=" "$SETTINGS" | tail -1 | cut -d= -f2- ; }
set_setting() {
  touch "$SETTINGS"
  local tmp; tmp="$(mktemp)"
  grep -vE "^$1=" "$SETTINGS" > "$tmp" 2>/dev/null
  echo "$1=$2" >> "$tmp"
  mv "$tmp" "$SETTINGS"
}
lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

pause() { echo; read -n 1 -s -r -p "Press any key..."; echo; }

# --- ZeroTier ---------------------------------------------------------------
find_ztcli() {
  for z in zerotier-cli /usr/local/bin/zerotier-cli "/Library/Application Support/ZeroTier/One/zerotier-cli"; do
    if command -v "$z" >/dev/null 2>&1; then echo "$z"; return 0; fi
    [ -x "$z" ] && { echo "$z"; return 0; }
  done
  return 1
}
# echoes "ip|nwid" of the first authorized (OK) network, else nothing
zt_info() {
  local cli; cli="$(find_ztcli)" || return 1
  "$cli" listnetworks 2>/dev/null | awk '
    /^200 listnetworks/ {
      nwid=$3; status=$(NF-3); ips=$NF;
      if (status=="OK" && ips!="-") { sub(/\/.*/,"",ips); n=split(ips,a,","); print a[1]"|"nwid; exit }
    }'
}
zt_status_text() {
  local cli; cli="$(find_ztcli)"
  if [ -z "$cli" ]; then echo "ZeroTier: not installed (https://www.zerotier.com/download/)"; return; fi
  local info; info="$("$cli" info 2>/dev/null)"
  local state="OFFLINE"; echo "$info" | grep -q ONLINE && state="ONLINE"
  echo "ZeroTier: $state"
  "$cli" listnetworks 2>/dev/null | awk '
    /^200 listnetworks/ { nwid=$3; status=$(NF-3); ips=$NF;
      if (status=="OK" && ips!="-") { sub(/\/.*/,"",ips); print "  net "nwid"  OK  IP: "ips }
      else print "  net "nwid"  "status" (host must authorize you)" }'
}

# --- token ------------------------------------------------------------------
ensure_token() {
  local t; t="$(cat "$TOKENFILE" 2>/dev/null | tr -d '[:space:]')"
  if [ -z "$t" ]; then
    t="$(openssl rand -hex 8 2>/dev/null)"
    [ -z "$t" ] && t="$(date +%s | shasum | cut -c1-16)"
    printf '%s' "$t" > "$TOKENFILE"
  fi
  printf '%s' "$t"
}

# --- game location ----------------------------------------------------------
find_game_root() {  # data root that holds Scripts/ or patch/ or Data/
  local base="$1"
  for cand in "$base" "$base/Contents/Resources" "$base/Contents/Game" "$base/Contents/MacOS"; do
    if [ -d "$cand/Scripts" ] || [ -d "$cand/patch" ] || [ -d "$cand/Data" ]; then echo "$cand"; return 0; fi
  done
  local hit; hit="$(find "$base" -maxdepth 4 -type d -name Scripts 2>/dev/null | head -1)"
  [ -n "$hit" ] && { dirname "$hit"; return 0; }
  return 1
}
find_game_app() {  # a .app to 'open', else the path itself
  local base="$1"
  case "$base" in *.app) echo "$base"; return 0;; esac
  local app; app="$(find "$base" -maxdepth 2 -name '*.app' 2>/dev/null | head -1)"
  [ -n "$app" ] && { echo "$app"; return 0; }
  echo "$base"
}
ask_game_path() {
  local saved; saved="$(get_setting gamepath)"
  echo "Rejuvenation folder or .app:"
  [ -n "$saved" ] && echo "  (Enter = keep: $saved)"
  echo "  Drag it into this window, then press Enter:"
  read -r p
  p="${p%\"}"; p="${p#\"}"; p="${p%\'}"; p="${p#\'}"; p="${p//\\ / }"; p="${p%% }"; p="${p%/}"
  [ -z "$p" ] && p="$saved"
  [ -z "$p" ] || [ ! -e "$p" ] && { echo "!! Path not found."; return 1; }
  set_setting gamepath "$p"
  printf '%s' "$p"
}

# --- config / options -------------------------------------------------------
write_config() {  # root, server, token
  { echo "# written by launcher-macos"; echo "server = $2"; [ -n "$3" ] && echo "token  = $3"; } > "$1/coop_config.txt"
}
write_options() {  # root, role
  local root="$1" role="$2"
  local sl rw rt seed diff
  sl="$(get_setting opt_soullink)";   [ -z "$sl" ] && sl="off"
  rw="$(get_setting opt_randwild)";   [ -z "$rw" ] && rw="off"
  rt="$(get_setting opt_randtrainer)";[ -z "$rt" ] && rt="off"
  seed="$(get_setting opt_seed)";     [ -z "$seed" ] && seed="0"
  diff="$(get_setting opt_diff)";     [ -z "$diff" ] && diff="normal"
  if [ "$role" = "host" ] && { [ "$rw" = "on" ] || [ "$rt" = "on" ]; } && { [ "$seed" = "0" ] || [ -z "$seed" ]; }; then
    seed="$(( (RANDOM<<15 | RANDOM) % 2000000000 + 1 ))"; set_setting opt_seed "$seed"
  fi
  {
    echo "# written by launcher-macos"
    echo "role            = $role"
    echo "soul_link       = $sl"
    echo "rand_wild       = $rw"
    echo "rand_trainer    = $rt"
    echo "rand_static     = off"
    echo "randomizer_seed = $seed"
    echo "difficulty      = $diff"
  } > "$root/coop_options.txt"
}

decode_join_code() {  # sets JC_ZTNET JC_SERVER JC_TOKEN ; returns 1 on error
  local code; code="$(printf '%s' "$1" | tr -d '[:space:]')"
  local dec; dec="$(printf '%s' "$code" | base64 -D 2>/dev/null)"
  [ -z "$dec" ] && dec="$(printf '%s' "$code" | base64 -d 2>/dev/null)"
  local ver; IFS='|' read -r ver JC_ZTNET JC_SERVER JC_TOKEN <<< "$dec"
  [ "$ver" = "v1" ] && [ -n "$JC_SERVER" ]
}
make_join_code() {  # ztnet, ip, port, token
  printf 'v1|%s|%s:%s|%s' "$1" "$2" "$3" "$4" | base64 | tr -d '\n'
}

# --- relay ------------------------------------------------------------------
relay_running() {
  local pid; pid="$(cat "$RELAYPIDFILE" 2>/dev/null)"
  [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null
}
start_relay() {
  relay_running && return 0
  command -v node >/dev/null 2>&1 || { echo "!! Node.js not found -- install from nodejs.org"; return 1; }
  ( cd "$SCRIPT_DIR" && node "$RELAYJS" >/dev/null 2>&1 & echo $! > "$RELAYPIDFILE" )
  sleep 1; return 0
}
stop_relay() {
  local pid; pid="$(cat "$RELAYPIDFILE" 2>/dev/null)"
  [ -n "$pid" ] && kill "$pid" 2>/dev/null
  rm -f "$RELAYPIDFILE"
}

launch_game() {  # path
  local app; app="$(find_game_app "$1")"
  case "$app" in
    *.app) open "$app" ;;
    *) if [ -x "$app" ]; then ( "$app" >/dev/null 2>&1 & ) ; else open "$app" ; fi ;;
  esac
}

# ===========================================================================
# Menu actions
# ===========================================================================
do_host() {
  echo "=== HOST A GAME ==="
  local gp root token ztl ip nwid
  gp="$(ask_game_path)" || { pause; return; }
  root="$(find_game_root "$gp")" || { echo "!! No Scripts/ or patch/ under that path."; pause; return; }
  token="$(ensure_token)"
  echo "Starting relay on port $RELAYPORT ..."
  start_relay || { pause; return; }
  write_config "$root" "127.0.0.1:$RELAYPORT" "$token"
  write_options "$root" "host"
  # join code from ZeroTier info
  ztl="$(zt_info)"
  if [ -n "$ztl" ]; then
    ip="${ztl%%|*}"; nwid="${ztl##*|}"
    local code; code="$(make_join_code "$nwid" "$ip" "$RELAYPORT" "$token")"
    echo
    echo "Share this JOIN CODE with your friends:"
    echo
    echo "  $code"
    echo
    printf '%s' "$code" | pbcopy 2>/dev/null && echo "  (copied to clipboard)"
    echo "  Server: $ip:$RELAYPORT   Token: $token"
    echo "  Remember to AUTHORIZE each friend at my.zerotier.com."
  else
    echo "ZeroTier has no authorized network yet -- friends over the internet"
    echo "need it. Local test still works. Token: $token"
  fi
  echo
  echo "Launching the game ..."
  launch_game "$gp"
  pause
}

do_join() {
  echo "=== JOIN A GAME ==="
  local gp root
  gp="$(ask_game_path)" || { pause; return; }
  root="$(find_game_root "$gp")" || { echo "!! No Scripts/ or patch/ under that path."; pause; return; }
  echo "Paste the JOIN CODE from your host:"
  read -r code
  if ! decode_join_code "$code"; then echo "!! Invalid join code."; pause; return; fi
  write_config "$root" "$JC_SERVER" "$JC_TOKEN"
  write_options "$root" "join"
  echo "-> Connection written (server $JC_SERVER)."
  if [ -n "$JC_ZTNET" ]; then
    local cli; cli="$(find_ztcli)"
    if [ -n "$cli" ]; then
      echo "Joining ZeroTier network $JC_ZTNET (may ask for your password)..."
      sudo "$cli" join "$JC_ZTNET" || echo "  Join via CLI failed -- use the ZeroTier menu-bar app."
      echo "  The HOST must authorize your device at my.zerotier.com."
    else
      echo "ZeroTier not installed -- get it at zerotier.com/download, then join $JC_ZTNET."
    fi
  fi
  echo
  echo "Launching the game ..."
  launch_game "$gp"
  pause
}

toggle() { if [ "$(get_setting "$1")" = "on" ]; then set_setting "$1" off; else set_setting "$1" on; fi; }
do_options() {
  while true; do
    clear
    echo "=== PRE-GAME OPTIONS (host decides; joiners inherit) ==="
    echo
    echo "  1) Soul Link .......... $(get_setting opt_soullink | sed 's/^$/off/')"
    echo "  2) Randomize wild ..... $(get_setting opt_randwild | sed 's/^$/off/')"
    echo "  3) Randomize trainers . $(get_setting opt_randtrainer | sed 's/^$/off/')"
    echo "  4) Seed ............... $(get_setting opt_seed | sed 's/^$/(random)/')"
    echo "  5) Difficulty ......... $(get_setting opt_diff | sed 's/^$/normal/')"
    echo "  0) Back"
    echo
    read -r -p "Choose: " c
    case "$c" in
      1) toggle opt_soullink ;;
      2) toggle opt_randwild ;;
      3) toggle opt_randtrainer ;;
      4) read -r -p "Seed (empty = random): " s; set_setting opt_seed "${s:-0}" ;;
      5) read -r -p "Difficulty [light/normal/hard/veryhard]: " d; d="$(lower "$d")"
         case "$d" in light|hard|veryhard) : ;; *) d="normal";; esac
         set_setting opt_diff "$d" ;;
      0|"") return ;;
    esac
  done
}

# ===========================================================================
# Main menu
# ===========================================================================
trap 'stop_relay' EXIT
while true; do
  clear
  echo "==============================================="
  echo "  Pokemon Rejuvenation Co-op -- macOS launcher"
  echo "==============================================="
  echo
  zt_status_text
  if relay_running; then echo "Relay: running on port $RELAYPORT"; else echo "Relay: off"; fi
  echo
  echo "  1) Host a game"
  echo "  2) Join a game"
  echo "  3) Pre-game options"
  echo "  4) Stop relay"
  echo "  5) Quit"
  echo
  read -r -p "Choose: " choice
  case "$choice" in
    1) clear; do_host ;;
    2) clear; do_join ;;
    3) do_options ;;
    4) stop_relay; echo "Relay stopped."; pause ;;
    5|q|Q) stop_relay; clear; echo "Bye!"; exit 0 ;;
  esac
done
