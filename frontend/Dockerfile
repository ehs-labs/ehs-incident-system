# syntax=docker/dockerfile:1.7

# =============================================================================
# Frontend Dockerfile — two named stages:
#   dev   → vite dev server (hot reload, used by docker-compose.dev.yml)
#   final → nginx serving the built dist/  (used in production / cloud overlay)
# =============================================================================

# ---------- Dev stage --------------------------------------------------------
FROM node:24-alpine AS dev

RUN corepack enable && corepack prepare pnpm@9 --activate

WORKDIR /app
COPY package.json pnpm-lock.yaml* ./
RUN pnpm install --prefer-offline

COPY . .

EXPOSE 5173
CMD ["pnpm", "run", "dev", "--host", "0.0.0.0", "--port", "5173"]

# ---------- Build stage ------------------------------------------------------
FROM node:24-alpine AS build

RUN corepack enable && corepack prepare pnpm@9 --activate

WORKDIR /app
COPY package.json pnpm-lock.yaml* ./
RUN pnpm install --frozen-lockfile

COPY . .
RUN pnpm run build

# ---------- Final stage ------------------------------------------------------
FROM nginx:alpine AS final

COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/dist /usr/share/nginx/html

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget -q --spider http://localhost:80/ || exit 1
