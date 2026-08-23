FROM alpine:3.22

ARG SINGBOX_VERSION=1.13.19

RUN apk add --no-cache \
    nginx \
    curl \
    tar \
    ca-certificates

# 下载 sing-box
RUN ARCH="$(uname -m)" && \
    case "$ARCH" in \
      x86_64) SB_ARCH="amd64" ;; \
      aarch64) SB_ARCH="arm64" ;; \
      *) echo "Unsupported architecture: $ARCH" && exit 1 ;; \
    esac && \
    FILE="sing-box-${SINGBOX_VERSION}-linux-${SB_ARCH}" && \
    curl -fL --retry 3 \
      "https://github.com/SagerNet/sing-box/releases/download/v${SINGBOX_VERSION}/${FILE}.tar.gz" \
      -o /tmp/sing-box.tar.gz && \
    mkdir -p /tmp/sing-box && \
    tar -xzf /tmp/sing-box.tar.gz -C /tmp/sing-box && \
    cp "/tmp/sing-box/${FILE}/sing-box" /usr/local/bin/sing-box && \
    chmod +x /usr/local/bin/sing-box && \
    rm -rf /tmp/sing-box /tmp/sing-box.tar.gz

COPY start.sh /start.sh

RUN chmod +x /start.sh && \
    mkdir -p /run/nginx /etc/nginx/http.d

EXPOSE 8080

CMD ["/start.sh"]
