# Rejuvenation Co-op -- native launcher (WinForms).
# Best started via start-launcher.bat (hides the console window).

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$ServerDir    = $PSScriptRoot
$SettingsFile = Join-Path $ServerDir "launcher_settings.json"
$TokenFile    = Join-Path $ServerDir "token.txt"
$RelayJs      = Join-Path $ServerDir "relay.js"
$RelayPort    = 7777
$ZtExe        = "C:\ProgramData\ZeroTier\One\zerotier-one_x64.exe"

# --- Helpers -----------------------------------------------------------------

function Load-Settings {
  try { return (Get-Content -Raw $SettingsFile | ConvertFrom-Json) } catch { return New-Object PSObject }
}
function Save-Setting([string]$name, [string]$value) {
  $s = Load-Settings
  if ($s.PSObject.Properties[$name]) { $s.$name = $value }
  else { $s | Add-Member -NotePropertyName $name -NotePropertyValue $value }
  $s | ConvertTo-Json | Set-Content -Encoding utf8 $SettingsFile
}
function Get-Setting([string]$name) {
  $s = Load-Settings
  if ($s.PSObject.Properties[$name]) { return [string]$s.$name }
  return ""
}

function Load-Token {
  try { $t = (Get-Content -Raw $TokenFile).Trim(); if ($t) { return $t } } catch {}
  return ""
}
function Save-Token([string]$t) { $t | Set-Content -Encoding ascii $TokenFile }
function New-RandomToken {
  -join ((1..16) | ForEach-Object { "0123456789abcdef"[(Get-Random -Maximum 16)] })
}

function Get-ZtStatus {
  # Returns @{ ok=bool; text=string; ip=string; nwid=string }
  $r = @{ ok = $false; text = "ZeroTier not installed (winget install ZeroTier.ZeroTierOne)"; ip = ""; nwid = "" }
  if (-not (Test-Path $ZtExe)) { return $r }
  try {
    $info = (& $ZtExe -q info 2>$null)
    if (-not $info) { $r.text = "ZeroTier service not responding"; return $r }
    $online = ($info -match "ONLINE")
    $lines = (& $ZtExe -q listnetworks 2>$null) -split "`n"
    $netLines = @()
    foreach ($ln in $lines) {
      $ln = $ln.Trim()
      if ($ln -match "^200 listnetworks ([0-9a-f]{16})\s+(.*)$") {
        $nwid = $Matches[1]
        $rest = ($Matches[2].Trim()) -split "\s+"
        $ips = $rest[$rest.Length - 1]
        $status = $rest[$rest.Length - 4]
        if ($status -eq "OK" -and $ips -ne "-") {
          $ip = ($ips -split ",")[0] -replace "/\d+$", ""
          $r.ok = $true; $r.ip = $ip; $r.nwid = $nwid
          $netLines += "Network $nwid  OK  IP: $ip"
        } elseif ($status -eq "REQUESTING_CONFIGURATION" -or $status -eq "ACCESS_DENIED") {
          $netLines += "Network $nwid  waiting for host authorization!"
        } else {
          $netLines += "Network $nwid  Status: $status"
        }
      }
    }
    if ($netLines.Count -eq 0) { $netLines += "Not in any network (enter the host's Network ID in the Join field)" }
    $stateStr = "OFFLINE"; if ($online) { $stateStr = "ONLINE" }
    $r.text = "ZeroTier " + $stateStr + "`n" + ($netLines -join "`n")
    return $r
  } catch { $r.text = "ZeroTier error: $($_.Exception.Message)"; return $r }
}

function Test-RelayPort {
  try {
    $c = New-Object Net.Sockets.TcpClient
    $iar = $c.BeginConnect("127.0.0.1", $RelayPort, $null, $null)
    if ($iar.AsyncWaitHandle.WaitOne(300)) { $c.EndConnect($iar); $c.Close(); return $true }
    $c.Close(); return $false
  } catch { return $false }
}

function Find-GameExe {
  $saved = Get-Setting "gameExe"
  if ($saved -and (Test-Path $saved)) { return $saved }
  $dirSetting = Get-Setting "gameDir"
  if ($dirSetting) {
    $p = Join-Path $dirSetting "Rejuvenation.exe"
    if (Test-Path $p) { return $p }
  }
  $cand = Join-Path (Split-Path (Split-Path $ServerDir)) "game\Rejuvenation-14.0-windows\Rejuvenation.exe"
  if (Test-Path $cand) { return $cand }
  return ""
}

function Write-CoopConfig([string]$gameDir, [string]$server, [string]$token) {
  $lines = @("# written by the launcher", "server = $server")
  if ($token) { $lines += "token  = $token" }
  ($lines -join "`n") + "`n" | Set-Content -Encoding ascii (Join-Path $gameDir "coop_config.txt")
}

# --- Pre-game options --------------------------------------------------------
function Get-OptOr([string]$name, [string]$default) {
  $v = Get-Setting $name
  if ([string]::IsNullOrWhiteSpace($v)) { return $default }
  return $v
}
function Write-CoopOptions([string]$gameDir, [string]$role = "host") {
  $sl   = Get-OptOr "optSoulLink"    "off"
  $rw   = Get-OptOr "optRandWild"    "off"
  $rt   = Get-OptOr "optRandTrainer" "off"
  $rs   = Get-OptOr "optRandStatic"  "off"
  $seed = Get-OptOr "optRandSeed"    "0"
  $diff = Get-OptOr "optDifficulty"  "normal"
  $lines = @(
    "# written by the launcher (pre-game options)",
    "role            = $role",
    "soul_link       = $sl",
    "rand_wild       = $rw",
    "rand_trainer    = $rt",
    "rand_static     = $rs",
    "randomizer_seed = $seed",
    "difficulty      = $diff"
  )
  ($lines -join "`n") + "`n" | Set-Content -Encoding ascii (Join-Path $gameDir "coop_options.txt")
}

function Show-PreGameOptions {
  $dlg = New-Object Windows.Forms.Form
  $dlg.Text = "Pre-Game Options"
  $dlg.ClientSize = New-Object Drawing.Size(372, 316)
  $dlg.StartPosition = "CenterParent"
  $dlg.FormBorderStyle = "FixedDialog"; $dlg.MaximizeBox = $false; $dlg.MinimizeBox = $false
  $dlg.BackColor = [Drawing.Color]::FromArgb(24, 26, 34)
  $dlg.ForeColor = [Drawing.Color]::FromArgb(220, 224, 234)
  $dlg.Font = New-Object Drawing.Font("Segoe UI", 9.5)

  $info = New-Object Windows.Forms.Label
  $info.Text = "Affects the game. Applies to both players (the host decides)."
  $info.Location = New-Object Drawing.Point(16, 12); $info.Size = New-Object Drawing.Size(330, 32)
  $info.ForeColor = [Drawing.Color]::FromArgb(150, 156, 174)
  $dlg.Controls.Add($info)

  $cbSoul = New-Object Windows.Forms.CheckBox
  $cbSoul.Text = "Soul Link  (linked faint across both teams)"
  $cbSoul.Location = New-Object Drawing.Point(16, 52); $cbSoul.Size = New-Object Drawing.Size(330, 24)
  $cbSoul.Checked = ((Get-OptOr "optSoulLink" "off") -eq "on")
  $dlg.Controls.Add($cbSoul)

  $lblRand = New-Object Windows.Forms.Label
  $lblRand.Text = "Randomizer (fully random, same seed):"
  $lblRand.Location = New-Object Drawing.Point(16, 82); $lblRand.Size = New-Object Drawing.Size(344, 20)
  $lblRand.ForeColor = [Drawing.Color]::FromArgb(150, 156, 174)
  $dlg.Controls.Add($lblRand)

  $cbRandWild = New-Object Windows.Forms.CheckBox
  $cbRandWild.Text = "Wild Pokemon"
  $cbRandWild.Location = New-Object Drawing.Point(32, 104); $cbRandWild.Size = New-Object Drawing.Size(320, 22)
  $cbRandWild.Checked = ((Get-OptOr "optRandWild" "off") -eq "on")
  $dlg.Controls.Add($cbRandWild)

  $cbRandTrainer = New-Object Windows.Forms.CheckBox
  $cbRandTrainer.Text = "Trainer teams"
  $cbRandTrainer.Location = New-Object Drawing.Point(32, 128); $cbRandTrainer.Size = New-Object Drawing.Size(320, 22)
  $cbRandTrainer.Checked = ((Get-OptOr "optRandTrainer" "off") -eq "on")
  $dlg.Controls.Add($cbRandTrainer)

  $cbRandStatic = New-Object Windows.Forms.CheckBox
  $cbRandStatic.Text = "Gift / Static"
  $cbRandStatic.Location = New-Object Drawing.Point(32, 152); $cbRandStatic.Size = New-Object Drawing.Size(320, 22)
  $cbRandStatic.Checked = ((Get-OptOr "optRandStatic" "off") -eq "on")
  $dlg.Controls.Add($cbRandStatic)

  $lblSeed = New-Object Windows.Forms.Label
  $lblSeed.Text = "Seed (empty = random):"
  $lblSeed.Location = New-Object Drawing.Point(32, 180); $lblSeed.Size = New-Object Drawing.Size(140, 22)
  $dlg.Controls.Add($lblSeed)
  $txtSeed = New-Object Windows.Forms.TextBox
  $txtSeed.Location = New-Object Drawing.Point(178, 178); $txtSeed.Size = New-Object Drawing.Size(180, 22)
  $txtSeed.BackColor = [Drawing.Color]::FromArgb(14, 16, 22); $txtSeed.ForeColor = $dlg.ForeColor
  $s = Get-OptOr "optRandSeed" "0"; if ($s -ne "0") { $txtSeed.Text = $s }
  $dlg.Controls.Add($txtSeed)

  $lblDiff = New-Object Windows.Forms.Label
  $lblDiff.Text = "Difficulty (co-op):"
  $lblDiff.Location = New-Object Drawing.Point(16, 212); $lblDiff.Size = New-Object Drawing.Size(150, 22)
  $dlg.Controls.Add($lblDiff)
  $cmbDiff = New-Object Windows.Forms.ComboBox
  $cmbDiff.DropDownStyle = "DropDownList"
  $cmbDiff.Location = New-Object Drawing.Point(170, 210); $cmbDiff.Size = New-Object Drawing.Size(188, 24)
  [void]$cmbDiff.Items.AddRange(@("Light", "Normal", "Hard", "Very Hard"))
  $diffMap = @{ "light" = "Light"; "normal" = "Normal"; "hard" = "Hard"; "veryhard" = "Very Hard" }
  $cur = Get-OptOr "optDifficulty" "normal"
  $cmbDiff.SelectedItem = $diffMap[$cur]; if (-not $cmbDiff.SelectedItem) { $cmbDiff.SelectedIndex = 1 }
  $dlg.Controls.Add($cmbDiff)

  $btnOk = New-Object Windows.Forms.Button
  $btnOk.Text = "Save"; $btnOk.Location = New-Object Drawing.Point(186, 262); $btnOk.Size = New-Object Drawing.Size(90, 30)
  $btnOk.BackColor = [Drawing.Color]::FromArgb(46, 125, 50); $btnOk.ForeColor = [Drawing.Color]::White
  $dlg.Controls.Add($btnOk)
  $btnCancel = New-Object Windows.Forms.Button
  $btnCancel.Text = "Cancel"; $btnCancel.Location = New-Object Drawing.Point(280, 262); $btnCancel.Size = New-Object Drawing.Size(80, 30)
  $btnCancel.BackColor = [Drawing.Color]::FromArgb(45, 49, 64); $btnCancel.ForeColor = $dlg.ForeColor
  $dlg.Controls.Add($btnCancel)

  $btnOk.Add_Click({
    $rev = @{ "Light" = "light"; "Normal" = "normal"; "Hard" = "hard"; "Very Hard" = "veryhard" }
    Save-Setting "optSoulLink"    ($(if ($cbSoul.Checked) { "on" } else { "off" }))
    Save-Setting "optRandWild"    ($(if ($cbRandWild.Checked) { "on" } else { "off" }))
    Save-Setting "optRandTrainer" ($(if ($cbRandTrainer.Checked) { "on" } else { "off" }))
    Save-Setting "optRandStatic"  ($(if ($cbRandStatic.Checked) { "on" } else { "off" }))
    $seedVal = $txtSeed.Text.Trim()
    $anyRand = $cbRandWild.Checked -or $cbRandTrainer.Checked -or $cbRandStatic.Checked
    if ($anyRand -and ($seedVal -eq "" -or $seedVal -eq "0")) {
      $seedVal = [string](Get-Random -Minimum 1 -Maximum 2147483647)
    }
    if ($seedVal -eq "") { $seedVal = "0" }
    Save-Setting "optRandSeed"    $seedVal
    Save-Setting "optDifficulty"  $rev[[string]$cmbDiff.SelectedItem]
    $dlg.DialogResult = "OK"; $dlg.Close()
  })
  $btnCancel.Add_Click({ $dlg.DialogResult = "Cancel"; $dlg.Close() })
  [void]$dlg.ShowDialog()
}

function Show-Err([string]$text) {
  [Windows.Forms.MessageBox]::Show($text, "Error", "OK", "Error") | Out-Null
}

function Test-TokenFormat([string]$token) {
  return ($token -match "^[A-Za-z0-9_\-]{1,64}$")
}

# Live check: briefly connects to the relay and tests the token.
# Returns: "ok" | "badformat" | "unreachable" | "badtoken"
function Test-CoopServer([string]$server, [string]$token) {
  if ($server -notmatch "^([^\s:]+):(\d{1,5})$") { return "badformat" }
  $sHost = $Matches[1]; $sPort = [int]$Matches[2]
  if ($sPort -lt 1 -or $sPort -gt 65535) { return "badformat" }
  try {
    $c = New-Object Net.Sockets.TcpClient
    $iar = $c.BeginConnect($sHost, $sPort, $null, $null)
    if (-not $iar.AsyncWaitHandle.WaitOne(2500)) { $c.Close(); return "unreachable" }
    $c.EndConnect($iar)
    $stream = $c.GetStream()
    $auth = '{"t":"auth","token":"' + $token + '","id":"launcher-test"}' + "`n"
    $bytes = [Text.Encoding]::UTF8.GetBytes($auth)
    $stream.Write($bytes, 0, $bytes.Length)
    $stream.ReadTimeout = 1200
    $buf = New-Object byte[] 512
    try {
      $n = $stream.Read($buf, 0, 512)
      $c.Close()
      if ($n -le 0) { return "badtoken" }   # server disconnected immediately
      $resp = [Text.Encoding]::UTF8.GetString($buf, 0, $n)
      if ($resp -match "bad token" -or $resp -match "auth required") { return "badtoken" }
      return "ok"                            # got other players' data -> auth ok
    } catch {
      # read timeout: server stays silent on successful auth -> ok
      $c.Close()
      return "ok"
    }
  } catch { return "unreachable" }
}

# --- Relay process -----------------------------------------------------------

$script:RelayProc = $null
function Start-Relay {
  if ($script:RelayProc -and -not $script:RelayProc.HasExited) { return }
  $script:RelayProc = Start-Process -FilePath "node" -ArgumentList "`"$RelayJs`"" -WorkingDirectory $ServerDir -WindowStyle Hidden -PassThru
}
function Stop-Relay {
  if ($script:RelayProc -and -not $script:RelayProc.HasExited) {
    try { Stop-Process -Id $script:RelayProc.Id -Force -Confirm:$false } catch {}
  }
  $script:RelayProc = $null
}

# --- GUI ---------------------------------------------------------------------

$form = New-Object Windows.Forms.Form
$form.Text = "Rejuvenation Co-op Launcher"
$form.ClientSize = New-Object Drawing.Size(640, 780)
$form.FormBorderStyle = "Sizable"          # freely resizable
$form.MinimumSize = New-Object Drawing.Size(600, 720)
$form.MaximizeBox = $true
$form.BackColor = [Drawing.Color]::FromArgb(24, 26, 34)
$form.ForeColor = [Drawing.Color]::White
$form.Font = New-Object Drawing.Font("Segoe UI", 10)

function New-Label($text, $x, $y, $w, $h) {
  $l = New-Object Windows.Forms.Label
  $l.Text = $text; $l.Location = New-Object Drawing.Point($x, $y)
  $l.Size = New-Object Drawing.Size($w, $h)
  $form.Controls.Add($l); return $l
}
function New-TextBox($x, $y, $w) {
  $t = New-Object Windows.Forms.TextBox
  $t.Location = New-Object Drawing.Point($x, $y); $t.Width = $w
  $t.BackColor = [Drawing.Color]::FromArgb(35, 39, 52); $t.ForeColor = [Drawing.Color]::White
  $t.BorderStyle = "FixedSingle"
  $form.Controls.Add($t); return $t
}
function New-Button($text, $x, $y, $w) {
  $b = New-Object Windows.Forms.Button
  $b.Text = $text; $b.Location = New-Object Drawing.Point($x, $y); $b.Width = $w; $b.Height = 32
  $b.FlatStyle = "Flat"; $b.BackColor = [Drawing.Color]::FromArgb(124, 92, 255); $b.ForeColor = [Drawing.Color]::White
  $b.FlatAppearance.BorderSize = 0
  $form.Controls.Add($b); return $b
}

# Section: game (top, grows with width)
New-Label "GAME" 20 15 200 18 | ForEach-Object { $_.ForeColor = [Drawing.Color]::FromArgb(138, 144, 162) }
$txtGame = New-TextBox 20 38 520
$txtGame.Anchor = "Top,Left,Right"
$txtGame.Text = Find-GameExe
$btnBrowse = New-Button "..." 552 36 68
$btnBrowse.Anchor = "Top,Right"
$btnBrowse.BackColor = [Drawing.Color]::FromArgb(45, 49, 64)
$btnBrowse.Add_Click({
  $dlg = New-Object Windows.Forms.OpenFileDialog
  $dlg.Filter = "Game EXE (*.exe)|*.exe"
  $dlg.Title = "Select Rejuvenation.exe"
  if ($dlg.ShowDialog() -eq "OK") {
    $txtGame.Text = $dlg.FileName
    Save-Setting "gameExe" $dlg.FileName
  }
})

# Section: ZeroTier status
New-Label "NETWORK" 20 82 200 18 | ForEach-Object { $_.ForeColor = [Drawing.Color]::FromArgb(138, 144, 162) }
$lblZt = New-Label "loading..." 20 104 600 64
$lblZt.Anchor = "Top,Left,Right"
$lblZt.Font = New-Object Drawing.Font("Consolas", 9.5)

# Section: host
New-Label "HOST" 20 178 200 18 | ForEach-Object { $_.ForeColor = [Drawing.Color]::FromArgb(138, 144, 162) }
New-Label "Password/Token:" 20 206 115 22
$txtToken = New-TextBox 140 204 300
$txtToken.Text = Load-Token
$btnHost = New-Button "Start Server" 20 238 190
$btnStop = New-Button "Stop Server" 220 238 140
$btnStop.BackColor = [Drawing.Color]::FromArgb(90, 40, 60)
$btnStop.Visible = $false
$btnOptions = New-Button "Pre-Game Options" 372 238 248
$btnOptions.Anchor = "Top,Right"
$btnOptions.BackColor = [Drawing.Color]::FromArgb(52, 44, 78)
$btnOptions.Add_Click({ Show-PreGameOptions })

# Instructions box: grows with the window (horizontal + vertical)
$txtShare = New-Object Windows.Forms.TextBox
$txtShare.Multiline = $true; $txtShare.ReadOnly = $true; $txtShare.ScrollBars = "Vertical"
$txtShare.Location = New-Object Drawing.Point(20, 282); $txtShare.Size = New-Object Drawing.Size(500, 200)
$txtShare.Anchor = "Top,Bottom,Left,Right"
$txtShare.BackColor = [Drawing.Color]::FromArgb(14, 16, 22); $txtShare.ForeColor = [Drawing.Color]::FromArgb(170, 178, 197)
$txtShare.Font = New-Object Drawing.Font("Consolas", 9.5)
$txtShare.BorderStyle = "FixedSingle"
$form.Controls.Add($txtShare)
$btnCopy = New-Button "Copy" 530 282 90
$btnCopy.Anchor = "Top,Right"
$btnCopy.BackColor = [Drawing.Color]::FromArgb(45, 49, 64)
$btnCopy.Add_Click({ if ($txtShare.Text) { Set-Clipboard -Value $txtShare.Text } })

# Section: join (anchored to the bottom)
New-Label "JOIN" 20 502 200 18 | ForEach-Object { $_.ForeColor = [Drawing.Color]::FromArgb(138, 144, 162); $_.Anchor = "Bottom,Left" }
$lblJs = New-Label "Server (ip:port):" 20 530 115 22; $lblJs.Anchor = "Bottom,Left"
$txtJoinServer = New-TextBox 140 528 300
$txtJoinServer.Anchor = "Bottom,Left"
$txtJoinServer.Text = Get-Setting "lastServer"
$lblJt = New-Label "Token:" 20 562 115 22; $lblJt.Anchor = "Bottom,Left"
$txtJoinToken = New-TextBox 140 560 300
$txtJoinToken.Anchor = "Bottom,Left"
$btnJoin = New-Button "Connect + Start Game" 20 594 230
$btnJoin.Anchor = "Bottom,Left"
$lblNw = New-Label "ZeroTier Network ID:" 20 640 120 22; $lblNw.Anchor = "Bottom,Left"
$txtNwid = New-TextBox 140 638 200
$txtNwid.Anchor = "Bottom,Left"
$txtNwid.Text = Get-Setting "lastNetworkId"
$btnZtJoin = New-Button "Join Network" 350 636 140
$btnZtJoin.Anchor = "Bottom,Left"
$btnZtJoin.BackColor = [Drawing.Color]::FromArgb(45, 49, 64)

# Status line (bottom, grows with width)
$lblStatus = New-Label "" 20 688 600 70
$lblStatus.Anchor = "Bottom,Left,Right"
$lblStatus.Font = New-Object Drawing.Font("Consolas", 9)
$lblStatus.ForeColor = [Drawing.Color]::FromArgb(154, 161, 181)

# --- Actions -----------------------------------------------------------------

$btnHost.Add_Click({
  # check preconditions before anything starts
  if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
    Show-Err "Node.js not found -- the server (relay) needs it.`nInstall it: nodejs.org"
    return
  }
  $token = $txtToken.Text.Trim()
  if (-not $token) { $token = New-RandomToken; $txtToken.Text = $token }
  if (-not (Test-TokenFormat $token)) {
    Show-Err "Invalid token: only letters, digits, - and _ allowed (max 64 chars), no spaces."
    return
  }
  $exe = $txtGame.Text.Trim()
  if ($exe -and -not (Test-Path $exe)) {
    Show-Err "Game EXE not found:`n$exe`n`nCheck the path or re-select via '...'."
    return
  }
  Save-Token $token
  Start-Relay
  if ($exe) {
    Write-CoopConfig (Split-Path $exe) "127.0.0.1:$RelayPort" $token
    Write-CoopOptions (Split-Path $exe) "host"
    Start-Process -FilePath $exe -WorkingDirectory (Split-Path $exe)
  }
})

$btnStop.Add_Click({ Stop-Relay })

$btnJoin.Add_Click({
  $exe = $txtGame.Text.Trim()
  if (-not $exe) {
    Show-Err "Please select Rejuvenation.exe above first ('...' button)."
    return
  }
  if (-not (Test-Path $exe)) {
    Show-Err "Game EXE not found:`n$exe`n`nCheck the path or re-select via '...'."
    return
  }
  $server = $txtJoinServer.Text.Trim()
  $token = $txtJoinToken.Text.Trim()
  if (-not $server) {
    Show-Err "Server address missing (get it from the host, e.g. 10.147.20.10:7777)."
    return
  }
  if ($server -notmatch "^([^\s:]+):(\d{1,5})$") {
    Show-Err "Server address has the wrong format.`nCorrect: ip:port  --  e.g. 10.147.20.10:7777"
    return
  }
  if ($token -and -not (Test-TokenFormat $token)) {
    Show-Err "Invalid token: only letters, digits, - and _ allowed, no spaces."
    return
  }
  # live test: connect + check the token first, then start the game
  $btnJoin.Enabled = $false; $btnJoin.Text = "checking..."
  $result = Test-CoopServer $server $token
  $btnJoin.Enabled = $true; $btnJoin.Text = "Connect + Start Game"
  switch ($result) {
    "badformat"   { Show-Err "Server address has the wrong format (ip:port)."; return }
    "unreachable" { Show-Err "Server not reachable: $server`n`nPossible causes:`n- IP or port typed wrong`n- The host hasn't started the server`n- ZeroTier not connected / not yet authorized (see NETWORK above)"; return }
    "badtoken"    { Show-Err "The server rejected the connection: password/token is wrong.`nAsk the host for the token."; return }
  }
  Write-CoopConfig (Split-Path $exe) $server $token
  Write-CoopOptions (Split-Path $exe) "join"
  Save-Setting "lastServer" $server
  Start-Process -FilePath $exe -WorkingDirectory (Split-Path $exe)
})

$btnZtJoin.Add_Click({
  $nwid = $txtNwid.Text.Trim().ToLower()
  if ($nwid -notmatch "^[0-9a-f]{16}$") {
    [Windows.Forms.MessageBox]::Show("Network ID must be 16 characters (0-9a-f).", "Invalid") | Out-Null
    return
  }
  $out = & $ZtExe -q join $nwid 2>$null
  if ($out -match "OK") {
    Save-Setting "lastNetworkId" $nwid
    [Windows.Forms.MessageBox]::Show("Joined. The host must now authorize you in the ZeroTier dashboard (Auth checkbox). After that your IP appears above.", "Joined") | Out-Null
  } else {
    [Windows.Forms.MessageBox]::Show("Join failed. Is the ZeroTier service running?", "Error") | Out-Null
  }
})

# --- Timer: refresh status ---------------------------------------------------

$timer = New-Object Windows.Forms.Timer
$timer.Interval = 3000
$timer.Add_Tick({
  $zt = Get-ZtStatus
  $lblZt.Text = $zt.text
  $relayUp = Test-RelayPort
  $ownRelay = ($script:RelayProc -and -not $script:RelayProc.HasExited)
  $btnStop.Visible = $ownRelay
  if ($ownRelay) { $btnHost.Text = "Server running"; $btnHost.Enabled = $false }
  elseif ($relayUp) { $btnHost.Text = "Server running (external)"; $btnHost.Enabled = $false }
  else { $btnHost.Text = "Start Server"; $btnHost.Enabled = $true }

  if ($zt.ok) {
    $tok = Load-Token
    if (-not $tok) { $tok = "(none yet -- created when you click 'Start Server')" }
    $prefix = ""
    if (-not $relayUp) {
      $prefix = ">>> SERVER IS OFF -- click 'Start Server' first, or nobody can join! <<<`r`n`r`n"
    }
    $txtShare.Text = $prefix + @"
=================================================
  POKEMON REJUVENATION CO-OP  --  HOW TO JOIN
=================================================

  STEP 1 -- Install the game
  --------------------------
  Download:  rebornevo.com/rejuvdown
  (Version 14, fully extracted)


  STEP 2 -- Install the co-op mod
  -------------------------------
  Copy the 'patch' folder from the host
  into the game folder.
  (important: patch\Mods\coop.rb)


  STEP 3 -- Install ZeroTier
  --------------------------
  Download:  zerotier.com/download


  STEP 4 -- Join the network
  --------------------------
  Network ID:  $($zt.nwid)
  (ZeroTier icon in the tray
   -> Join Network -> enter the ID)


  STEP 5 -- Get authorized
  ------------------------
  Tell the host -- they authorize you
  in the ZeroTier dashboard.


  STEP 6 -- Connect
  -----------------
  In the launcher under JOIN:

      Server:  $($zt.ip):$RelayPort
      Token:   $tok

  (or create a file 'coop_config.txt'
   in the game folder with:
      server = $($zt.ip):$RelayPort
      token  = $tok )


  STEP 7 -- Start the game. Done!
  -------------------------------
  You'll see each other once you're
  on the same map.
"@
  } else {
    $txtShare.Text = "ZeroTier is not connected -- see NETWORK above.`r`nWithout a ZeroTier IP no join instructions can be generated."
  }

  # own connection from coop_net.txt
  $exe = $txtGame.Text.Trim()
  $statusLines = @()
  if ($relayUp) { $statusLines += "Relay: running on port $RelayPort" } else { $statusLines += "Relay: off" }
  if ($exe) {
    $netFile = Join-Path (Split-Path $exe) "coop_net.txt"
    if (Test-Path $netFile) {
      $tail = Get-Content $netFile -Tail 2 -ErrorAction SilentlyContinue
      if ($tail) { $statusLines += $tail }
    }
  }
  $lblStatus.Text = ($statusLines -join "`n")
})
$timer.Start()

$form.Add_FormClosing({ $timer.Stop(); Stop-Relay })

# initial display
$lblZt.Text = (Get-ZtStatus).text

[void]$form.ShowDialog()
