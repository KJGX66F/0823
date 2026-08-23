#!/bin/sh

set -eu

# ============================================================
# Hostless + sing-box VLESS WebSocket
# ============================================================

UUID="${UUID:-}"
WS_PATH="${WS_PATH:-/vless}"

# Hostless 会自动提供 PORT
PORT="${PORT:-8080}"

# Hostless 分配的公网域名
# 例如 abc.hostless.app
PUBLIC_HOST="${PUBLIC_HOST:-}"

# sing-box 内部端口
SB_PORT="10000"

CONFIG="/tmp/sing-box.json"
NGINX_CONFIG="/etc/nginx/http.d/default.conf"


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
echo "PORT        : $PORT"
echo "WS PATH     : $WS_PATH"
echo "SINGBOX PORT: $SB_PORT"

if [ -n "$PUBLIC_HOST" ]; then
    echo "PUBLIC HOST : $PUBLIC_HOST"
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
# Nginx 配置
# ============================================================

cat > "$NGINX_CONFIG" <<EOF
server {

    listen ${PORT};
    listen [::]:${PORT};

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
EOF


# ============================================================
# 检查 sing-box 配置
# ============================================================

echo "[1/4] Checking sing-box configuration..."

sing-box check -c "$CONFIG"

echo ""
echo "Configuration OK"
echo ""


# ============================================================
# 自动输出节点
# ============================================================

if [ -n "$PUBLIC_HOST" ]; then

    ENCODED_PATH="$(printf '%s' "$WS_PATH" | sed 's#/#%2F#g')"

    echo "============================================================"
    echo "                       VLESS 节点"
    echo "============================================================"
    echo ""

    echo "vless://${UUID}@${PUBLIC_HOST}:443?encryption=none&security=tls&type=ws&host=${PUBLIC_HOST}&sni=${PUBLIC_HOST}&path=${ENCODED_PATH}#Hostless-VLESS"

    echo ""
    echo "============================================================"
    echo "协议   : VLESS"
    echo "地址   : $PUBLIC_HOST"
    echo "端口   : 443"
    echo "UUID   : $UUID"
    echo "传输   : WebSocket"
    echo "Path   : $WS_PATH"
    echo "TLS    : 开启"
    echo "Host   : $PUBLIC_HOST"
    echo "SNI    : $PUBLIC_HOST"
    echo "Flow   : 留空"
    echo "============================================================"
    echo ""

else

    echo "============================================================"
    echo "PUBLIC_HOST 尚未设置"
    echo ""
    echo "第一次部署成功后，复制 Hostless 给你的域名，例如："
    echo ""
    echo "abc123.hostless.app"
    echo ""
    echo "然后 Environment 添加："
    echo ""
    echo "PUBLIC_HOST=abc123.hostless.app"
    echo ""
    echo "重新部署后 Logs 会自动打印完整 vless:// 节点。"
    echo "============================================================"
    echo ""

fi


# ============================================================
# 启动 sing-box
# ============================================================

echo "[2/4] Starting sing-box..."

sing-box run -c "$CONFIG" &

SB_PID=$!

sleep 1

if ! kill -0 "$SB_PID" 2>/dev/null; then
    echo "ERROR: sing-box failed to start."
    exit 1
fi


# ============================================================
# 启动 nginx
# ============================================================

echo "[3/4] Starting nginx..."

nginx -g "daemon off;" &

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
echo "HTTP PORT : $PORT"
echo "WS PATH   : $WS_PATH"
echo "HEALTH    : /health"
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
# 监控两个进程
# ============================================================

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
