$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$modFiles = @("coop.rb", "coop_menu.rb")
$repoOwner = "sukjacode"
$repoName = "rejuvenation-multiplayer"
$repoBranch = "main"

function Test-GameFolder([string]$folder) {
    if ([string]::IsNullOrWhiteSpace($folder)) { return $false }
    return (Test-Path (Join-Path $folder "Game.exe")) -or
        (Test-Path (Join-Path $folder "Rejuvenation.exe"))
}

function Get-ModFile([string]$name) {
    $localPath = Join-Path (Join-Path $PSScriptRoot "..\mod") $name
    if (Test-Path $localPath) {
        return (Resolve-Path $localPath).Path
    }

    $url = "https://raw.githubusercontent.com/$repoOwner/$repoName/$repoBranch/mod/$name"
    $downloadPath = Join-Path $env:TEMP ("rejuvenation-coop-" + $name)
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $url -OutFile $downloadPath -UseBasicParsing
    if (-not (Test-Path $downloadPath)) {
        throw "The mod file '$name' could not be downloaded."
    }
    return $downloadPath
}

$form = New-Object System.Windows.Forms.Form
$form.Text = "Rejuvenation Co-op Client-Installer"
$form.ClientSize = New-Object System.Drawing.Size(560, 305)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false
$form.Font = New-Object System.Drawing.Font("Segoe UI", 9)

$title = New-Object System.Windows.Forms.Label
$title.Text = "Set up Rejuvenation Co-op"
$title.Font = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
$title.Location = New-Object System.Drawing.Point(16, 14)
$title.Size = New-Object System.Drawing.Size(520, 30)
$form.Controls.Add($title)

$description = New-Object System.Windows.Forms.Label
$description.Text = "Select your game folder and enter the relay server and token."
$description.Location = New-Object System.Drawing.Point(18, 49)
$description.Size = New-Object System.Drawing.Size(520, 22)
$form.Controls.Add($description)

$folderLabel = New-Object System.Windows.Forms.Label
$serverLabel = New-Object System.Windows.Forms.Label
$serverLabel.Text = "Relay server (host:port)"
$serverLabel.Location = New-Object System.Drawing.Point(18, 82)
$serverLabel.Size = New-Object System.Drawing.Size(520, 20)
$form.Controls.Add($serverLabel)

$serverBox = New-Object System.Windows.Forms.TextBox
$serverBox.Location = New-Object System.Drawing.Point(18, 104)
$serverBox.Size = New-Object System.Drawing.Size(524, 24)
$form.Controls.Add($serverBox)

$folderLabel.Text = "Game folder (containing Game.exe or Rejuvenation.exe)"
$folderLabel.Location = New-Object System.Drawing.Point(18, 141)
$folderLabel.Size = New-Object System.Drawing.Size(520, 20)
$form.Controls.Add($folderLabel)

$folderBox = New-Object System.Windows.Forms.TextBox
$folderBox.Location = New-Object System.Drawing.Point(18, 163)
$folderBox.Size = New-Object System.Drawing.Size(410, 24)
$form.Controls.Add($folderBox)

$browseButton = New-Object System.Windows.Forms.Button
$browseButton.Text = "Browse..."
$browseButton.Location = New-Object System.Drawing.Point(438, 161)
$browseButton.Size = New-Object System.Drawing.Size(104, 27)
$form.Controls.Add($browseButton)

$tokenLabel = New-Object System.Windows.Forms.Label
$tokenLabel.Text = "Relay token"
$tokenLabel.Location = New-Object System.Drawing.Point(18, 200)
$tokenLabel.Size = New-Object System.Drawing.Size(520, 20)
$form.Controls.Add($tokenLabel)

$tokenBox = New-Object System.Windows.Forms.TextBox
$tokenBox.Location = New-Object System.Drawing.Point(18, 222)
$tokenBox.Size = New-Object System.Drawing.Size(524, 24)
$tokenBox.UseSystemPasswordChar = $true
$form.Controls.Add($tokenBox)

$installButton = New-Object System.Windows.Forms.Button
$installButton.Text = "Install mod and connect"
$installButton.Location = New-Object System.Drawing.Point(18, 260)
$installButton.Size = New-Object System.Drawing.Size(240, 32)
$installButton.BackColor = [System.Drawing.Color]::FromArgb(46, 125, 50)
$installButton.ForeColor = [System.Drawing.Color]::White
$installButton.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($installButton)

$browseButton.Add_Click({
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = "Select the Rejuvenation game folder containing Game.exe"
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $folderBox.Text = $dialog.SelectedPath
    }
})

$installButton.Add_Click({
    $installButton.Enabled = $false
    try {
        $folder = $folderBox.Text.Trim()
        $server = $serverBox.Text.Trim()
        $token = $tokenBox.Text.Trim()

        if (-not (Test-GameFolder $folder)) {
            throw "Please select a valid Rejuvenation game folder containing Game.exe or Rejuvenation.exe."
        }
        if ([string]::IsNullOrWhiteSpace($server)) {
            throw "Please enter the relay server in host:port format."
        }
        if ($server.Contains("`r") -or $server.Contains("`n")) {
            throw "The relay server must not contain line breaks."
        }
        if ([string]::IsNullOrWhiteSpace($token)) {
            throw "Please enter the relay token."
        }
        if ($token.Contains("`r") -or $token.Contains("`n")) {
            throw "The token must not contain line breaks."
        }

        $mods = @{}
        foreach ($name in $modFiles) {
            $mods[$name] = Get-ModFile $name
        }

        $modsFolder = Join-Path $folder "patch\Mods"
        New-Item -ItemType Directory -Path $modsFolder -Force | Out-Null
        foreach ($name in $modFiles) {
            Copy-Item -LiteralPath $mods[$name] -Destination (Join-Path $modsFolder $name) -Force
        }

        $configPath = Join-Path $folder "coop_config.txt"
        if (Test-Path $configPath) {
            $backupPath = $configPath + ".backup-" + (Get-Date -Format "yyyyMMdd-HHmmss")
            Copy-Item -LiteralPath $configPath -Destination $backupPath
        }
        $config = "# Written by the Rejuvenation Co-op client installer.`r`nserver = $server`r`ntoken = $token`r`n"
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($configPath, $config, $utf8NoBom)

        [System.Windows.Forms.MessageBox]::Show(
            "Installation complete.`r`n`r`nRelay: $server`r`nStart your game now. If the connection fails, check that the relay is running and its TCP port is reachable.",
            "Rejuvenation Co-op",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null
        $form.Close()
    } catch {
        [System.Windows.Forms.MessageBox]::Show(
            $_.Exception.Message,
            "Installation failed",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
    } finally {
        $installButton.Enabled = $true
    }
})

[void]$form.ShowDialog()
