#!/bin/sh

set -eu

# ============================================================
# Hostless + sing-box VLESS WebSocket
# Read-only filesystem compatible
# ============================================================

UUID="${UUID:-}"
WS_PATH="${WS_PATH:-/vless}"

# Hostless 自动注入 PORT
PORT="${PORT:-8000}"

PUBLIC_HOST="${PUBLIC_HOST:-}"

# sing-box 内部端口
SB_PORT="10000"

# 所有运行时动态文件全部写入 /tmp
CONFIG="/tmp/sing-box.json"
NGINX_CONFIG="/tmp/nginx.conf"

NGINX_TMP="/tmp/nginx"
NGINX_PID="/tmp/nginx.pid"

mkdir -p \
    "$NGINX_TMP/client_body" \
    "$NGINX_TMP/proxy" \
    "$NGINX_TMP/fastcgi" \
    "$NGINX_TMP/uwsgi" \
    "$NGINX_TMP/scgi"


# ============================================================
# 参数检查
# ============================================================

if [ -z "$UUID" ]; then
    echo ""
    echo "ERROR: UUID environment variable is missing."
    echo ""
    exit 1
fi


case "$WS_PATH" in
    /*)
        ;;
    *)
        WS_PATH="/$WS_PATH"
        ;;
esac


echo ""
echo "============================================================"
echo "             Hostless + sing-box VLESS"
echo "============================================================"
echo "PORT         : $PORT"
echo "WS PATH      : $WS_PATH"
echo "SINGBOX PORT : $SB_PORT"
echo "CONFIG       : $CONFIG"
echo "NGINX CONFIG : $NGINX_CONFIG"

if [ -n "$PUBLIC_HOST" ]; then
    echo "PUBLIC HOST  : $PUBLIC_HOST"
fi

echo "============================================================"
echo ""


# ============================================================
# sing-box 配置
# ============================================================

cat > "$CONFIG" <<EOF
{
  "log": {
    "level": "info",
    "timestamp": true
  },

  "inbounds": [
    {
      "type": "vless",
      "tag": "vless-in",

      "listen": "127.0.0.1",
      "listen_port": ${SB_PORT},

      "users": [
        {
          "name": "hostless",
          "uuid": "${UUID}"
        }
      ],

      "transport": {
        "type": "ws",
        "path": "${WS_PATH}"
      }
    }
  ],

  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    }
  ],

  "route": {
    "final": "direct"
  }
}
EOF


# ============================================================
# Nginx 完整配置
#
# 重点：
# 不再写 /etc/nginx/*
# PID / temp / config 全部放 /tmp
# ============================================================

cat > "$NGINX_CONFIG" <<EOF
worker_processes 1;

error_log /dev/stderr info;
pid ${NGINX_PID};

events {
    worker_connections 1024;
}

http {

    include /etc/nginx/mime.types;

    default_type application/octet-stream;

    access_log /dev/stdout;

    sendfile on;

    keepalive_timeout 65;


    client_body_temp_path ${NGINX_TMP}/client_body;
    proxy_temp_path       ${NGINX_TMP}/proxy;
    fastcgi_temp_path     ${NGINX_TMP}/fastcgi;
    uwsgi_temp_path       ${NGINX_TMP}/uwsgi;
    scgi_temp_path        ${NGINX_TMP}/scgi;


    server {

        listen 0.0.0.0:${PORT};
        server_name _;


        # ========================================
        # 首页
        # ========================================

        location = / {

            default_type text/plain;

            add_header Cache-Control "no-store";

            return 200 "Hostless VLESS is running\n";
        }


        # ========================================
        # Health Check
        # ========================================

        location = /health {

            default_type application/json;

            add_header Cache-Control "no-store";

            return 200 '{"status":"ok"}';
        }


        # ========================================
        # VLESS WebSocket
        # ========================================

        location ${WS_PATH} {

            proxy_pass http://127.0.0.1:${SB_PORT};

            proxy_http_version 1.1;

            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection "upgrade";

            proxy_set_header Host \$host;

            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto https;

            proxy_read_timeout 3600s;
            proxy_send_timeout 3600s;

            proxy_buffering off;
        }
    }
}
EOF


# ============================================================
# 检查 sing-box
# ============================================================

echo "[1/5] Checking sing-box configuration..."

sing-box check -c "$CONFIG"

echo ""
echo "sing-box configuration OK"
echo ""


# ============================================================
# 检查 Nginx
# ============================================================

echo "[2/5] Checking nginx configuration..."

nginx -t -c "$NGINX_CONFIG"

echo ""
echo "nginx configuration OK"
echo ""


# ============================================================
# 自动打印节点
# ============================================================

if [ -n "$PUBLIC_HOST" ]; then

    ENCODED_PATH="$(printf '%s' "$WS_PATH" | sed 's#/#%2F#g')"

    echo ""
    echo "============================================================"
    echo "                       VLESS NODE"
    echo "============================================================"
    echo ""

    echo "vless://${UUID}@${PUBLIC_HOST}:443?encryption=none&security=tls&type=ws&host=${PUBLIC_HOST}&sni=${PUBLIC_HOST}&path=${ENCODED_PATH}#Hostless-VLESS"

    echo ""
    echo "============================================================"
    echo "Protocol : VLESS"
    echo "Address  : $PUBLIC_HOST"
    echo "Port     : 443"
    echo "UUID     : $UUID"
    echo "Network  : WebSocket"
    echo "Path     : $WS_PATH"
    echo "TLS      : enabled"
    echo "Host     : $PUBLIC_HOST"
    echo "SNI      : $PUBLIC_HOST"
    echo "Flow     : empty"
    echo "============================================================"
    echo ""

else

    echo ""
    echo "============================================================"
    echo "PUBLIC_HOST is not configured yet."
    echo ""
    echo "This is OK for the first deployment."
    echo ""
    echo "After Hostless gives you a public hostname,"
    echo "add this Environment Variable:"
    echo ""
    echo "PUBLIC_HOST=your-app.hostless.app"
    echo ""
    echo "Then redeploy to print the complete VLESS URL."
    echo "============================================================"
    echo ""

fi


# ============================================================
# 启动 sing-box
# ============================================================

echo "[3/5] Starting sing-box..."

sing-box run -c "$CONFIG" &

SB_PID=$!

sleep 1


if ! kill -0 "$SB_PID" 2>/dev/null; then

    echo "ERROR: sing-box failed to start."

    exit 1
fi


# ============================================================
# 启动 Nginx
#
# 使用 /tmp/nginx.conf
# 不加载 /etc/nginx/http.d/default.conf
# ============================================================

echo "[4/5] Starting nginx..."

nginx \
    -c "$NGINX_CONFIG" \
    -g "daemon off;" &

NGINX_PID=$!

sleep 1


if ! kill -0 "$NGINX_PID" 2>/dev/null; then

    echo "ERROR: nginx failed to start."

    kill "$SB_PID" 2>/dev/null || true

    exit 1
fi


echo ""
echo "============================================================"
echo " Hostless VLESS started successfully"
echo "============================================================"
echo "Public HTTP port : $PORT"
echo "WebSocket path   : $WS_PATH"
echo "Health check     : /health"
echo "============================================================"
echo ""


# ============================================================
# 优雅退出
# ============================================================

shutdown() {

    echo ""
    echo "Stopping Hostless VLESS..."

    kill "$NGINX_PID" 2>/dev/null || true
    kill "$SB_PID" 2>/dev/null || true

    wait "$NGINX_PID" 2>/dev/null || true
    wait "$SB_PID" 2>/dev/null || true

    exit 0
}


trap shutdown TERM INT


# ============================================================
# 监控进程
# ============================================================

echo "[5/5] Service monitoring started."
echo ""


while true; do

    if ! kill -0 "$SB_PID" 2>/dev/null; then

        echo "ERROR: sing-box stopped."

        kill "$NGINX_PID" 2>/dev/null || true

        exit 1
    fi


    if ! kill -0 "$NGINX_PID" 2>/dev/null; then

        echo "ERROR: nginx stopped."

        kill "$SB_PID" 2>/dev/null || true

        exit 1
    fi


    sleep 10

done
