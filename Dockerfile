FROM alpine:3.22 AS tailscale-download
RUN apk add --no-cache curl tar
RUN mkdir -p /out && \
    curl -fsSL https://pkgs.tailscale.com/stable/tailscale_1.104.4_amd64.tgz | \
    tar -xzf - --strip-components=1 -C /out && \
    chmod 0755 /out/tailscale /out/tailscaled

FROM node:22-alpine
RUN apk add --no-cache ca-certificates
WORKDIR /app
COPY --from=tailscale-download /out/tailscale /usr/local/bin/tailscale
COPY --from=tailscale-download /out/tailscaled /usr/local/bin/tailscaled
COPY probe.js ./probe.js
COPY start.sh ./start.sh
RUN chmod 0755 /app/start.sh
ENV NODE_ENV=production
EXPOSE 8080
CMD ["/app/start.sh"]
