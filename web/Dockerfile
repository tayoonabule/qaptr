FROM node:22-bookworm-slim AS build

WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY . .
RUN npm run build:dokploy && npm prune --omit=dev

FROM node:22-bookworm-slim AS runtime

ENV HOST=0.0.0.0 \
    PORT=3000 \
    WAITLIST_DB_PATH=/data/qaptr-waitlist.sqlite

WORKDIR /app
COPY --from=build --chown=node:node /app/dist ./dist
COPY --from=build --chown=node:node /app/migrations ./migrations
COPY --from=build --chown=node:node /app/node_modules ./node_modules
COPY --from=build --chown=node:node /app/package.json ./package.json
RUN mkdir -p /data && chown node:node /data

USER node
EXPOSE 3000
CMD ["node", "./dist/server/entry.mjs"]
