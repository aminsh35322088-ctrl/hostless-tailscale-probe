FROM alpine:3.22 AS downloads
RUN apk add --no-cache ca-certificates curl tar
WORKDIR /tmp/downloads

# Official Hiddify Core v5.5.5 (Linux amd64, musl).
RUN curl -fsSL --retry 3 \
      -o hiddify-core.tar.gz \
      https://github.com/hiddify/hiddify-core/releases/download/v5.5.5/hiddify-core-linux-amd64-musl.tar.gz \
    && echo "837f73a35eb4c629ba63a7e083b124533197f475d8defd950f3175d658e7a541  hiddify-core.tar.gz" | sha256sum -c - \
    && mkdir hiddify \
    && tar -xzf hiddify-core.tar.gz --strip-components=1 -C hiddify \
    && test -x hiddify/hiddify-core

# Official Cloudflare cloudflared v2026.10.7 (Linux amd64).
RUN curl -fsSL --retry 3 \
      -o cloudflared \
      https://github.com/cloudflare/cloudflared/releases/download/2026.10.7/cloudflared-linux-amd64 \
    && echo "1f99fb518b83dec2ba8d870a7cc991d82a77e6196295a3d2754ba17ab9f91872  cloudflared" | sha256sum -c - \
    && chmod 0755 cloudflared

FROM node:22-alpine
RUN apk add --no-cache ca-certificates
WORKDIR /app

COPY --from=downloads /tmp/downloads/hiddify/hiddify-core /usr/local/bin/hiddify-core
COPY --from=downloads /tmp/downloads/cloudflared /usr/local/bin/cloudflared
COPY start.sh make-config.js health.js ./

RUN chmod 0755 /app/start.sh \
    && hiddify-core version \
    && cloudflared --version

ENV NODE_ENV=production
EXPOSE 8000
CMD ["/app/start.sh"]
