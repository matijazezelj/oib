FROM node:20-slim

WORKDIR /app

COPY package*.json ./
RUN npm install

COPY *.js ./

EXPOSE 3000

CMD ["node", "--require", "./tracing.js", "app.js"]
