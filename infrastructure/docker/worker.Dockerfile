# --- Build stage ---
FROM node:20-alpine AS builder

WORKDIR /app

# Copy workspace root files
COPY package.json package-lock.json turbo.json ./

# Copy shared and worker package files
COPY shared/ ./shared/
COPY worker/ ./worker/

# Install all dependencies
RUN npm ci --ignore-scripts

# Build shared first, then worker
RUN cd shared && npx tsc && cd ../worker && npx tsc

# --- Production stage ---
FROM node:20-alpine AS runner

WORKDIR /app

ENV NODE_ENV=production

# Create non-root user
RUN addgroup --system --gid 1001 nodejs && \
    adduser --system --uid 1001 gearsnitch

# Copy built artifacts
COPY --from=builder /app/shared/dist ./shared/dist
COPY --from=builder /app/shared/package.json ./shared/
COPY --from=builder /app/worker/dist ./worker/dist
COPY --from=builder /app/worker/package.json ./worker/
COPY --from=builder /app/package.json ./
COPY --from=builder /app/package-lock.json ./

# Install production dependencies only
RUN npm ci --omit=dev --ignore-scripts && \
    npm cache clean --force

USER gearsnitch

CMD ["node", "worker/dist/index.js"]
