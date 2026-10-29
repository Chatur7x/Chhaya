FROM node:24-alpine AS builder

WORKDIR /app

COPY backend/server/package*.json ./
RUN npm ci

COPY backend/server/ ./
RUN npm run build

FROM node:24-alpine AS runner

WORKDIR /app

ENV NODE_ENV=production

COPY backend/server/package*.json ./
RUN npm ci --omit=dev && npm cache clean --force
COPY --from=builder /app/dist ./dist

EXPOSE 10000
USER node

CMD ["node", "dist/index.js"]
