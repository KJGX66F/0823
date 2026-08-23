#!/bin/sh

set -eu

UUID="${UUID:-}"
WS_PATH="${WS_PATH:-/vless}"
PORT="${PORT:-8000}"
PUBLIC_HOST="${PUBLIC_HOST:-}"

SINGBOX="/usr/local/bin/sing-box"
CONFIG="/tmp/sing-box.json"


# ============================================================
# UUID
# ============================================================

if [ -z "$UUID" ]; then
    echo ""
    echo "ERROR: UUID environment variable is missing."
    echo ""
    echo "Please add:"
    echo "UUID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
    echo ""
    exit 1
fi


# ============================================================
# WebSocket Path
# ============================================================

case "$WS_PATH" in
    /*) ;;
    *) WS_PATH="/$WS_PATH" ;;
esac


# ============================================================
# Check sing-box
# ============================================================

if [ ! -x "$SINGBOX" ]; then
    echo ""
    echo "ERROR: sing-box not found:"
    echo "$SINGBOX"
    echo ""
    ls -lah /usr/local/bin 2>/dev/null || true
    exit 1
fi


echo ""
echo "============================================================"
echo "       Hostless + sing-box VLESS WebSocket"
echo "============================================================"
echo "PORT        : $PORT"
echo "WS PATH     : $WS_PATH"
echo "SINGBOX BIN : $SINGBOX"
echo "CONFIG      : $CONFIG"

if [ -n "$PUBLIC_HOST" ]; then
    echo "PUBLIC HOST : $PUBLIC_HOST"
fi

echo "============================================================"
echo ""


# ============================================================
# sing-box config
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
# ============================================================

echo "[1/3] Checking sing-box binary..."
echo ""

"$SINGBOX" version

echo ""


# ============================================================
# STEP 2
# ============================================================

echo "[2/3] Checking configuration..."
echo ""

"$SINGBOX" check -c "$CONFIG"

echo ""
echo "Configuration OK"
echo ""


# ============================================================
# Print node
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
    echo "                     VLESS NODE"
    echo "============================================================"
    echo ""
    echo "vless://${UUID}@${CLEAN_HOST}:443?encryption=none&security=tls&type=ws&host=${CLEAN_HOST}&sni=${CLEAN_HOST}&path=${ENCODED_PATH}#Hostless-VLESS"
    echo ""
    echo "============================================================"
    echo "Address : ${CLEAN_HOST}"
    echo "Port    : 443"
    echo "UUID    : ${UUID}"
    echo "Network : ws"
    echo "Path    : ${WS_PATH}"
    echo "TLS     : enabled"
    echo "SNI     : ${CLEAN_HOST}"
    echo "============================================================"
    echo ""

else

    echo ""
    echo "============================================================"
    echo "PUBLIC_HOST not configured yet."
    echo ""
    echo "First deployment is OK without it."
    echo ""
    echo "After Hostless gives you a domain, add:"
    echo ""
    echo "PUBLIC_HOST=xxxx.hostless.app"
    echo ""
    echo "Then redeploy."
    echo "============================================================"
    echo ""

fi


# ============================================================
# STEP 3
# ============================================================

echo "[3/3] Starting sing-box..."
echo ""
echo "Listening : 0.0.0.0:${PORT}"
echo "WS Path   : ${WS_PATH}"
echo ""

exec "$SINGBOX" run -c "$CONFIG"
