# Multi-stage: official xray image has no shell, copy binary into Alpine
FROM ghcr.io/xtls/xray-core:latest AS builder
FROM alpine:latest
RUN apk add --no-cache ca-certificates tzdata
COPY --from=builder /usr/local/bin/xray /usr/local/bin/xray
COPY --from=builder /usr/local/share/xray/geoip.dat /usr/local/share/xray/geoip.dat
COPY --from=builder /usr/local/share/xray/geosite.dat /usr/local/share/xray/geosite.dat
COPY config.template.json /etc/xray/config.template.json
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
EXPOSE 3000
ENTRYPOINT ["/entrypoint.sh"]
