# syntax=docker/dockerfile:1

# ---------- Étape 1 : dépendances complètes + compilation ----------
FROM node:22-alpine AS builder
WORKDIR /app

# On copie d'abord les manifestes seuls : Docker met en cache cette couche
# et ne réinstalle les dépendances que si package.json change.
COPY package*.json ./
RUN npm ci

COPY tsconfig*.json esbuild.config.js ./
COPY src ./src
RUN npm run build

# ---------- Étape 2 : dépendances de production seules ----------
FROM node:22-alpine AS deps
WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev && npm cache clean --force

# ---------- Étape 3 : image finale ----------
FROM node:22-alpine AS runner
WORKDIR /app
ENV NODE_ENV=production

COPY --from=deps  /app/node_modules ./node_modules
COPY --from=builder /app/dist       ./dist
COPY --from=builder /app/public     ./public
# Les templates .njk ne sont pas compilés : ils sont lus à l'exécution.
COPY --from=builder /app/src/views  ./src/views
COPY package.json ./

# node:22-alpine fournit déjà un utilisateur non-root nommé "node".
# Tourner en root dans un conteneur est un risque inutile.
USER node

EXPOSE 3000
CMD ["node", "dist/server.js"]
