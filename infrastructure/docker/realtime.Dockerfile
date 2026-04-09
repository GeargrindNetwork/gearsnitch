# --- Build stage ---
FROM node:20-alpine AS builder

WORKDIR /app

# Copy workspace root files
COPY package.json package-lock.json turbo.json ./

# Copy shared and realtime package files
COPY shared/ ./shared/
COPY realtime/ ./realtime/

# Install all dependencies
RUN npm ci --ignore-scripts

# Build shared first, then realtime
RUN npx turbo run build --filter=@gearsnitch/shared --filter=@gearsnitch/realtime

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
COPY --from=builder /app/realtime/dist ./realtime/dist
COPY --from=builder /app/realtime/package.json ./realtime/
COPY --from=builder /app/package.json ./
COPY --from=builder /app/package-lock.json ./

# Install production dependencies only
RUN npm ci --omit=dev --ignore-scripts && \
    npm cache clean --force

USER gearsnitch

EXPOSE 3001

CMD ["node", "realtime/dist/server.js"]
