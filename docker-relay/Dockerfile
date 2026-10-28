FROM node:22-alpine

WORKDIR /app
COPY --chown=node:node server/relay.js ./relay.js

USER node
EXPOSE 7777/tcp

CMD ["node", "relay.js"]
