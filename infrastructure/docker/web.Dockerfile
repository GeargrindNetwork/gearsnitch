# --- Build stage ---
FROM node:20-alpine AS builder

WORKDIR /app

# Copy workspace root files
COPY package.json package-lock.json turbo.json ./

# Copy web package files (shared not needed for web build)
COPY web/package.json ./web/

# Install dependencies for web workspace
RUN npm ci --workspace=web --include-workspace-root

# Copy web source
COPY web/ ./web/

# Build the Vite app
RUN cd web && npm run build

# Verify build output exists
RUN ls -la /app/web/dist/index.html

# --- Production stage ---
FROM nginx:alpine AS runner

# Custom nginx config for SPA
RUN echo 'server { \
    listen 8080; \
    root /usr/share/nginx/html; \
    index index.html; \
    \
    gzip on; \
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml text/javascript image/svg+xml; \
    gzip_min_length 256; \
    \
    location /assets/ { \
        expires 1y; \
        add_header Cache-Control "public, immutable"; \
    } \
    \
    location / { \
        try_files $uri $uri/ /index.html; \
        add_header Cache-Control "no-cache"; \
    } \
}' > /etc/nginx/conf.d/default.conf

# Copy built static files
COPY --from=builder /app/web/dist /usr/share/nginx/html

EXPOSE 8080

CMD ["nginx", "-g", "daemon off;"]
