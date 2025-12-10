FROM node:20-slim

WORKDIR /app

COPY package*.json ./
RUN npm install

COPY *.js ./

# Switch to non-root user (node user is built-in)
USER node

EXPOSE 3000

CMD ["node", "--require", "./tracing.js", "app.js"]
