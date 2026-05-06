FROM caddy:2-builder AS builder
RUN xcaddy build \
    --with github.com/tailscale/caddy-tailscale

FROM caddy:2
COPY --from=builder /usr/bin/caddy /usr/bin/caddy
