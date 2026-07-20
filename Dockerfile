FROM node:26-alpine3.23 AS build

WORKDIR /usr/src/app

COPY package*.json ./
COPY prisma ./prisma

RUN npm ci

COPY . .

ENV DATABASE_URL="postgresql://postgres:postgres@localhost:5432/db"

RUN npm run build
RUN npm prune --omit=dev && npm cache clean --force

FROM node:26-alpine3.23

ENV NODE_ENV=production

WORKDIR /usr/src/app

COPY --from=build /usr/src/app/package*.json ./
COPY --from=build /usr/src/app/prisma.config.ts ./
COPY --from=build /usr/src/app/dist ./dist
COPY --from=build /usr/src/app/node_modules ./node_modules
COPY --from=build /usr/src/app/prisma ./prisma

EXPOSE 3000

CMD ["sh", "-c", "exec node dist/main.js"]
