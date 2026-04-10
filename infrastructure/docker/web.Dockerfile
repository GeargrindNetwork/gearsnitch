# --- Build stage ---
FROM node:20-alpine AS builder

WORKDIR /app

# Copy workspace root files
COPY package.json package-lock.json turbo.json ./

# Copy shared and web package files
COPY shared/ ./shared/
COPY web/ ./web/

# Install all dependencies
RUN npm ci --ignore-scripts

# Build shared first, then web (Vite)
RUN cd web && npx vite build

# --- Production stage ---
FROM nginx:alpine AS runner

# Copy custom nginx config
COPY infrastructure/docker/nginx.conf /etc/nginx/conf.d/default.conf

# Copy built static files from Vite output
COPY --from=builder /app/web/dist /usr/share/nginx/html

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
