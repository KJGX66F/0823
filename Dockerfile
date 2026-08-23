FROM alpine:3.22

ARG SINGBOX_VERSION=1.13.19

RUN apk add --no-cache \
    nginx \
    curl \
    tar \
    ca-certificates \
    tzdata

RUN set -eux; \
    ARCH="$(uname -m)"; \
    case "$ARCH" in \
      x86_64) SB_ARCH="amd64-musl" ;; \
      aarch64) SB_ARCH="arm64-musl" ;; \
      *) echo "Unsupported architecture: $ARCH"; exit 1 ;; \
    esac; \
    FILE="sing-box-${SINGBOX_VERSION}-linux-${SB_ARCH}"; \
    URL="https://github.com/SagerNet/sing-box/releases/download/v${SINGBOX_VERSION}/${FILE}.tar.gz"; \
    echo "Downloading: $URL"; \
    curl -fL --retry 3 --retry-delay 2 \
      "$URL" \
      -o /tmp/sing-box.tar.gz; \
    mkdir -p /tmp/sing-box; \
    tar -xzf /tmp/sing-box.tar.gz -C /tmp/sing-box; \
    cp "/tmp/sing-box/${FILE}/sing-box" /usr/local/bin/sing-box; \
    chmod 755 /usr/local/bin/sing-box; \
    /usr/local/bin/sing-box version; \
    test -x /usr/sbin/nginx; \
    /usr/sbin/nginx -v; \
    rm -rf /tmp/sing-box /tmp/sing-box.tar.gz

ENV PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

COPY start.sh /start.sh

RUN chmod 755 /start.sh

EXPOSE 8000

CMD ["/start.sh"]
