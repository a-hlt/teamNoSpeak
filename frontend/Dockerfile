FROM alpine:3.19

ENV APP_DIR=/app

RUN apk add --no-cache nodejs npm

WORKDIR ${APP_DIR}

COPY package*.json ./
RUN npm install

COPY . .
RUN npm run build

EXPOSE 3000

CMD ["node", "server.js"]
