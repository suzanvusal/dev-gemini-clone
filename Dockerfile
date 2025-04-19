# Stage 1: Build Stage
FROM node:18-alpine AS builder

# Metadata (consolidated for clarity)
LABEL maintainer="Amitabh Soni <amitabhdevops2024@gmail.com>" \
      org.opencontainers.image.title="Gemini" \
      org.opencontainers.image.description="Next.js Application" \
      org.opencontainers.image.vendor="Amitabh Soni"

WORKDIR /app

# 1. Improved dependency caching
COPY package.json package-lock.json ./
RUN npm ci --no-audit --prefer-offline && \
    npm cache clean --force

# 2. Copy only necessary files for build (exclude .dockerignore patterns)
COPY . .
RUN npm run build

# 3. Purge build-time artifacts (reduces layer size)
RUN rm -rf node_modules .next/cache

##################################
# Stage 2: Production Stage
##################################
FROM node:18-alpine

WORKDIR /app

# 4. Copy only production essentials
COPY --from=builder --chown=node:node /app/package.json .
COPY --from=builder --chown=node:node /app/.next ./.next
COPY --from=builder --chown=node:node /app/public ./public
COPY --from=builder --chown=node:node /app/next.config.mjs .

# 5. Install production deps with security hardening
RUN npm ci --production --no-audit --prefer-offline && \
    npm cache clean --force && \
    rm -rf /tmp/* /var/tmp/*

# 6. Runtime optimizations
ENV NODE_ENV=production \
    PORT=3000 \
    NEXT_TELEMETRY_DISABLED=1

EXPOSE 3000
USER node
HEALTHCHECK --interval=30s --timeout=3s CMD curl -f http://localhost:3000/api/health || exit 1

CMD ["npm", "start"]