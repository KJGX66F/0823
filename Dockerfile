FROM alpine:3.22

ARG SINGBOX_VERSION=1.13.19

# ============================================================
# 安装依赖
# ============================================================

RUN apk add --no-cache \
    nginx \
    curl \
    tar \
    ca-certificates \
    tzdata

# ============================================================
# 安装 sing-box
# ============================================================

RUN set -eux; \
    ARCH="$(uname -m)"; \
    case "$ARCH" in \
      x86_64) SB_ARCH="amd64" ;; \
      aarch64) SB_ARCH="arm64" ;; \
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
    rm -rf /tmp/sing-box /tmp/sing-box.tar.gz

# ============================================================
# PATH
# ============================================================

ENV PATH="/usr/local/bin:/usr/bin:/bin"

# ============================================================
# 启动脚本
# ============================================================

COPY start.sh /start.sh

RUN chmod 755 /start.sh

# Hostless 当前默认应用端口
EXPOSE 8000

CMD ["/start.sh"]
