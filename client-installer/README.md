# Rejuvenation Co-op Client-Installer (Windows)

This installer configures a player's existing legal Pokémon Rejuvenation V14
installation to connect to a relay. Enter the relay server address in the
installer. It does not include the game.

## Use

1. Run `install.bat` (or `install.ps1`) on Windows.
2. Select the game folder containing `Game.exe` or `Rejuvenation.exe`.
3. Enter the relay server address (`host:port`) and the token provided by the
   relay administrator.
4. Click **Install mod and connect**, then start the game.

The installer copies `coop.rb` and `coop_menu.rb` into `patch\Mods` and writes
`coop_config.txt` next to the game executable. If a config already exists, it
is backed up before being replaced.

When this folder is kept inside the repository, it uses the local `mod` files.
If distributed on its own, it downloads those files from the configured GitHub
repository, so an internet connection is required during setup.

Players still need network access to the relay on TCP port `7777`. The relay
administrator must provide the correct token and ensure the server firewall
allows the connection.
