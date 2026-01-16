FROM node:20-slim

WORKDIR /app

COPY package*.json ./
RUN npm install

COPY *.js ./

# Switch to non-root user (node user is built-in)
USER node

EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD node -e "require('http').get('http://localhost:3000/health', (r) => process.exit(r.statusCode === 200 ? 0 : 1))" || exit 1

CMD ["node", "--require", "./tracing.js", "app.js"]
