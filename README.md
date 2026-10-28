## Quick start

### Start the relay (Linux)

1. Put this repo on your server and open a terminal in its folder.
2. In `docker-relay/compose.yaml`, replace `INSERT_YOUR_TOKEN_HERE` with a
   private token. Share it only with your players.
3. Start the relay:

   ```sh
   chmod +x start-docker.sh
   ./start-docker.sh
   ```

Give them your server's
address as `host:port` default is `host:7777` and the token you chose.

### Join (Windows)

1. Download this repo and run `client-installer/install.bat`.
2. Choose your Rejuvenation folder, then enter the server address and shared
   token.
3. Click **Install mod and connect**, then launch the game.

That's it! The installer adds the mod files and connection config to your game
folder. If you need a hand, check `coop_net.txt` and `coop_error.txt` there.

Thx to https://github.com/sukjacode/rejuvenation-multiplayer