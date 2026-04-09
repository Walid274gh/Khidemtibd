# ══════════════════════════════════════════════════════════════════════════════
# Khidmeti API — Multi-stage Dockerfile
#
# DESIGN DECISIONS:
#  • No package-lock.json required — npm install generates it inside Docker.
#  • Layer cache: package.json copied alone → node_modules layer is cached
#    and only invalidated when dependencies actually change.
#  • --legacy-peer-deps: resolves eslint v9 / @typescript-eslint v7 peer
#    conflict without downgrading either package.
#  • Production stage copies only compiled dist + prod node_modules.
# ══════════════════════════════════════════════════════════════════════════════

# ── Stage 1: dependency resolver (shared cache layer) ────────────────────────
FROM node:20-alpine AS deps
WORKDIR /app

# Copy only the manifest — this layer is cached unless deps change
COPY package.json ./

# Install ALL deps (dev included) and generate package-lock.json.
# --legacy-peer-deps: required because eslint@9 and @typescript-eslint@7
# have a declared-but-compatible peer conflict.
RUN npm install --legacy-peer-deps


# ── Stage 2: builder (compile TypeScript → dist/) ────────────────────────────
FROM deps AS builder
WORKDIR /app

# Copy source after node_modules are ready
COPY . .
RUN npm run build


# ── Stage 3: development (watch mode, hot-reload) ────────────────────────────
FROM deps AS development
WORKDIR /app

# Reuse node_modules from deps stage — no reinstall
COPY . .

EXPOSE 3000
CMD ["npm", "run", "start:dev"]


# ── Stage 4: production (minimal image, no devDeps) ──────────────────────────
FROM node:20-alpine AS production
WORKDIR /app
ENV NODE_ENV=production

COPY package.json ./

# Install only production dependencies (no devDeps, no test/lint tools)
RUN npm install --omit=dev --legacy-peer-deps \
 && npm cache clean --force

# Copy compiled output from builder
COPY --from=builder /app/dist ./dist

EXPOSE 3000
CMD ["node", "dist/main"]
