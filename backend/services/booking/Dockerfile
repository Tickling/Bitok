# Сборка из корня backend/: docker build -f services/booking/Dockerfile .
FROM node:22-alpine AS build
WORKDIR /app
COPY package.json package-lock.json tsconfig.base.json ./
COPY shared-kernel ./shared-kernel
COPY services/booking ./services/booking
RUN npm ci --workspaces --include-workspace-root && npm run build

FROM node:22-alpine
WORKDIR /app
ENV NODE_ENV=production
COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/shared-kernel ./shared-kernel
COPY --from=build /app/services/booking/dist ./services/booking/dist
COPY --from=build /app/services/booking/package.json ./services/booking/
USER node
EXPOSE 3001
CMD ["node", "services/booking/dist/main.js"]
