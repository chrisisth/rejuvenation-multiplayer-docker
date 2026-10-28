# Docker relay

This folder contains the Docker setup for the co-op TCP relay. Keep it inside
the repository: the image is built from `server/relay.js` at the repository root.

## Start

1. Copy `.env.example` to `.env` in this folder and replace the example value
   with a private token.
2. From the repository root, run:

   ```sh
   docker compose --env-file docker-relay/.env -f docker-relay/compose.yaml up -d --build
   ```

The relay listens on TCP port `7777`. The Compose port mapping publishes it on
all host interfaces. Install and join ZeroTier on the Linux Docker host, then
give players the host's ZeroTier IP and port, for example
`10.147.20.10:7777`. Players must use the same token in their game configuration.
Allow inbound TCP port `7777` through the host firewall, preferably only from
the private network used by your players.

## Manage

Run these commands from the repository root:

```sh
docker compose --env-file docker-relay/.env -f docker-relay/compose.yaml logs -f
docker compose --env-file docker-relay/.env -f docker-relay/compose.yaml down
```

Keep `.env` private; it contains the relay authentication token.
