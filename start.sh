#!/bin/sh

set -eu

# ============================================================
# Hostless + sing-box VLESS WebSocket
# 单进程极简版
#
# 不使用 nginx
# 不修改 /etc
# 配置写入 /tmp
# 直接监听 Hostless 自动提供的 $PORT
# ============================================================


# ============================================================
# 环境变量
# ============================================================

UUID="${UUID:-}"

WS_PATH="${WS_PATH:-/vless}"

# Hostless 自动注入 PORT
PORT="${PORT:-8000}"

# 第一次部署成功拿到域名后再设置
# 例如：
# PUBLIC_HOST=xxxx.hostless.app
PUBLIC_HOST="${PUBLIC_HOST:-}"


# ============================================================
# 固定路径
# ============================================================

SINGBOX="/usr/local/bin/sing-box"

CONFIG="/tmp/sing-box.json"


# ============================================================
# 检查 UUID
# ============================================================

if [ -z "$UUID" ]; then

    echo ""
    echo "============================================================"
    echo "ERROR: UUID environment variable is missing"
    echo "============================================================"
    echo ""
    echo "Please add:"
    echo ""
    echo "UUID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
    echo ""

    exit 1
fi


# ============================================================
# 修正 WS Path
# ============================================================

case "$WS_PATH" in
    /*)
        ;;
    *)
        WS_PATH="/$WS_PATH"
        ;;
esac


# ============================================================
# 检查 sing-box
# ============================================================

if [ ! -x "$SINGBOX" ]; then

    echo ""
    echo "============================================================"
    echo "ERROR: sing-box binary not found"
    echo "============================================================"
    echo ""
    echo "Expected:"
    echo "$SINGBOX"
    echo ""

    ls -lah /usr/local/bin 2>/dev/null || true

    exit 1
fi


# ============================================================
# 启动信息
# ============================================================

echo ""
echo "============================================================"
echo "       Hostless + sing-box VLESS WebSocket"
echo "============================================================"
echo ""
echo "PORT        : $PORT"
echo "WS PATH     : $WS_PATH"
echo "SINGBOX BIN : $SINGBOX"
echo "CONFIG      : $CONFIG"

if [ -n "$PUBLIC_HOST" ]; then
    echo "PUBLIC HOST : $PUBLIC_HOST"
fi

echo ""
echo "============================================================"
echo ""


# ============================================================
# 生成 sing-box 配置
#
# 重要：
# Hostless 在外层负责 HTTPS/TLS
# sing-box 容器内部只需要 WS
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

      "listen": "0.0.0.0",
      "listen_port": ${PORT},

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
# STEP 1
# 检查 sing-box
# ============================================================

echo "[1/3] Checking sing-box binary..."
echo ""

"$SINGBOX" version

echo ""


# ============================================================
# STEP 2
# 检查配置
# ============================================================

echo "[2/3] Checking configuration..."
echo ""

"$SINGBOX" check -c "$CONFIG"

echo ""
echo "Configuration OK"
echo ""


# ============================================================
# 如果已经设置 PUBLIC_HOST
# 自动输出节点
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

    VLESS_LINK="vless://${UUID}@${CLEAN_HOST}:443?encryption=none&security=tls&type=ws&host=${CLEAN_HOST}&sni=${CLEAN_HOST}&path=${ENCODED_PATH}#Hostless-VLESS"

    echo ""
    echo "============================================================"
    echo "                      VLESS NODE"
    echo "============================================================"
    echo ""
    echo "$VLESS_LINK"
    echo ""
    echo "============================================================"
    echo "Protocol : VLESS"
    echo "Address  : $CLEAN_HOST"
    echo "Port     : 443"
    echo "UUID     : $UUID"
    echo "Network  : WebSocket"
    echo "Path     : $WS_PATH"
    echo "TLS      : enabled"
    echo "Host     : $CLEAN_HOST"
    echo "SNI      : $CLEAN_HOST"
    echo "Flow     : empty"
    echo "============================================================"
    echo ""

else

    echo ""
    echo "============================================================"
    echo "PUBLIC_HOST not configured yet"
    echo "============================================================"
    echo ""
    echo "This is normal for the first deployment."
    echo ""
    echo "After Hostless gives you the public hostname,"
    echo "add Environment Variable:"
    echo ""
    echo "PUBLIC_HOST=xxxx.hostless.app"
    echo ""
    echo "Then redeploy."
    echo "============================================================"
    echo ""

fi


# ============================================================
# STEP 3
# 直接运行 sing-box
#
# 使用 exec：
# sing-box 成为容器 PID 1
# 不再需要 nginx / supervisor / while true
# ============================================================

echo "[3/3] Starting sing-box..."
echo ""
echo "============================================================"
echo "Hostless VLESS starting"
echo "Listening : 0.0.0.0:$PORT"
echo "WS Path   : $WS_PATH"
echo "============================================================"
echo ""

exec "$SINGBOX" run -c "$CONFIG"
