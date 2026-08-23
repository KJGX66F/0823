#!/bin/sh

set -eu

UUID="${UUID:-}"
WS_PATH="${WS_PATH:-/vless}"

# Hostless 自动提供
PORT="${PORT:-8000}"

# Node -> sing-box 内部端口
SB_PORT="${SB_PORT:-10000}"

PUBLIC_HOST="${PUBLIC_HOST:-}"

SINGBOX="/usr/local/bin/sing-box"
CONFIG="/tmp/sing-box.json"


# ============================================================
# 参数检查
# ============================================================

if [ -z "$UUID" ]; then
    echo "ERROR: UUID environment variable is missing."
    exit 1
fi

case "$WS_PATH" in
    /*) ;;
    *) WS_PATH="/$WS_PATH" ;;
esac

if [ ! -x "$SINGBOX" ]; then
    echo "ERROR: sing-box not found: $SINGBOX"
    exit 1
fi


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


echo ""
echo "============================================================"
echo " Hostless VLESS"
echo "============================================================"
echo "Public PORT : $PORT"
echo "WS PATH     : $WS_PATH"
echo "sing-box    : 127.0.0.1:$SB_PORT"
echo "============================================================"
echo ""


# ============================================================
# 检查配置
# ============================================================

echo "[1/4] Checking sing-box..."

"$SINGBOX" version

echo ""
echo "[2/4] Checking configuration..."

"$SINGBOX" check -c "$CONFIG"

echo "Configuration OK"


# ============================================================
# 输出节点
# ============================================================

if [ -n "$PUBLIC_HOST" ]; then

    CLEAN_HOST="$(
        printf '%s' "$PUBLIC_HOST" |
        sed \
            -e 's#^https://##' \
            -e 's#^http://##' \
            -e 's#/$##'
    )"

    ENCODED_PATH="$(
        printf '%s' "$WS_PATH" |
        sed 's#/#%2F#g'
    )"

    echo ""
    echo "============================================================"
    echo "VLESS NODE"
    echo "============================================================"
    echo ""
    echo "vless://${UUID}@${CLEAN_HOST}:443?encryption=none&security=tls&type=ws&host=${CLEAN_HOST}&sni=${CLEAN_HOST}&path=${ENCODED_PATH}#Hostless-VLESS"
    echo ""
    echo "Address : $CLEAN_HOST"
    echo "Port    : 443"
    echo "UUID    : $UUID"
    echo "Network : ws"
    echo "Path    : $WS_PATH"
    echo "TLS     : enabled"
    echo "SNI     : $CLEAN_HOST"
    echo "============================================================"

fi


# ============================================================
# 启动 sing-box
# ============================================================

echo ""
echo "[3/4] Starting sing-box..."

"$SINGBOX" run -c "$CONFIG" &

SB_PID=$!

sleep 1

if ! kill -0 "$SB_PID" 2>/dev/null; then
    echo "ERROR: sing-box failed."
    exit 1
fi


# ============================================================
# 启动 HTTP / WebSocket 前门
# ============================================================

echo ""
echo "[4/4] Starting HTTP/WebSocket frontend..."

export PORT
export SB_PORT
export WS_PATH

node /proxy.js &

NODE_PID=$!

sleep 1

if ! kill -0 "$NODE_PID" 2>/dev/null; then
    echo "ERROR: HTTP frontend failed."
    kill "$SB_PID" 2>/dev/null || true
    exit 1
fi


echo ""
echo "============================================================"
echo " Hostless VLESS started successfully"
echo "============================================================"
echo "HTTP       : 0.0.0.0:$PORT"
echo "Health     : /health"
echo "WebSocket  : $WS_PATH"
echo "sing-box   : 127.0.0.1:$SB_PORT"
echo "============================================================"
echo ""


shutdown() {

    echo "Stopping..."

    kill "$NODE_PID" 2>/dev/null || true
    kill "$SB_PID" 2>/dev/null || true

    wait "$NODE_PID" 2>/dev/null || true
    wait "$SB_PID" 2>/dev/null || true

    exit 0
}

trap shutdown TERM INT HUP


while true
do

    if ! kill -0 "$SB_PID" 2>/dev/null; then
        echo "ERROR: sing-box stopped."
        kill "$NODE_PID" 2>/dev/null || true
        exit 1
    fi

    if ! kill -0 "$NODE_PID" 2>/dev/null; then
        echo "ERROR: HTTP frontend stopped."
        kill "$SB_PID" 2>/dev/null || true
        exit 1
    fi

    sleep 10
done
