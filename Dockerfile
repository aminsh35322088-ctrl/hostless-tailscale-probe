FROM node:22-alpine
WORKDIR /app
COPY probe.js ./probe.js
ENV NODE_ENV=production
EXPOSE 8080
CMD ["node", "/app/probe.js"]
