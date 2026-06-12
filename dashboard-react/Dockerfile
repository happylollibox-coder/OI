# OI React Dashboard — Cloud Run
# Deploys via: ./deployment/deploy_all.sh dashboard

# Stage 1: Build
FROM node:20-alpine AS build
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

# Stage 2: Serve with nginx
FROM nginx:alpine
COPY --from=build /app/dist /usr/share/nginx/html

# SPA routing + API proxy to Flask backend
RUN echo 'server { \
  listen 8080; \
  resolver 8.8.8.8 valid=30s; \
  set $flask_backend "https://data-entry-forms-405291422506.us-central1.run.app"; \
  location /api/ { \
    proxy_pass $flask_backend; \
    proxy_set_header Host data-entry-forms-405291422506.us-central1.run.app; \
    proxy_set_header X-Real-IP $remote_addr; \
    proxy_ssl_server_name on; \
  } \
  location / { \
    root /usr/share/nginx/html; \
    try_files $uri $uri/ /index.html; \
  } \
}' > /etc/nginx/conf.d/default.conf

EXPOSE 8080
CMD ["nginx", "-g", "daemon off;"]
