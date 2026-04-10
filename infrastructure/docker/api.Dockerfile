# --- Build stage ---
FROM node:20-alpine AS builder

WORKDIR /app

# Copy workspace root files
COPY package.json package-lock.json turbo.json ./

# Copy shared and api package files
COPY shared/ ./shared/
COPY api/ ./api/

# Install all dependencies
RUN npm ci --ignore-scripts

# Build shared first, then api
RUN cd shared && npx tsc && cd ../api && npx tsc

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
COPY --from=builder /app/api/dist ./api/dist
COPY --from=builder /app/api/package.json ./api/
COPY --from=builder /app/package.json ./
COPY --from=builder /app/package-lock.json ./

# Install production dependencies only
RUN npm ci --omit=dev --ignore-scripts && \
    npm cache clean --force

USER gearsnitch

EXPOSE 3000

CMD ["node", "api/dist/server.js"]
