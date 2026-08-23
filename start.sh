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

# 部署成功后可添加
# 例如：
# PUBLIC_HOST=xxxx.hostless.app
PUBLIC_HOST="${PUBLIC_HOST:-}"


# ============================================================
# sing-box
# ============================================================

SB="/usr/local/bin/sing-box"

SB_PORT="${SB_PORT:-10000}"


# ============================================================
# 所有运行时文件放 /tmp
# 避免 Hostless Read-only filesystem
# ============================================================

CONFIG="/tmp/sing-box.json"

NGINX_CONFIG="/tmp/nginx.conf"

NGINX_PID="/tmp/nginx.pid"

NGINX_TMP="/tmp/nginx"


mkdir -p \
    "${NGINX_TMP}/client_body" \
    "${NGINX_TMP}/proxy" \
    "${NGINX_TMP}/fastcgi" \
    "${NGINX_TMP}/uwsgi" \
    "${NGINX_TMP}/scgi"


# ============================================================
# 检查 UUID
# ============================================================

if [ -z "$UUID" ]; then

    echo ""
    echo "============================================================"
    echo "ERROR"
    echo "============================================================"
    echo ""
    echo "UUID environment variable is missing."
    echo ""
    echo "Please add:"
    echo ""
    echo "UUID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
    echo ""
    echo "============================================================"

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

if [ ! -x "$SB" ]; then

    echo ""
    echo "============================================================"
    echo "ERROR: sing-box binary not found"
    echo "============================================================"
    echo ""

    echo "Expected:"
    echo "$SB"

    echo ""
    echo "/usr/local/bin:"
    echo ""

    ls -lah /usr/local/bin 2>/dev/null || true

    echo ""
    echo "PATH:"
    echo "$PATH"

    echo ""

    exit 1
fi


# ============================================================
# 基本信息
# ============================================================

echo ""
echo "============================================================"
echo "             Hostless + sing-box VLESS"
echo "============================================================"
echo ""
echo "PORT         : $PORT"
echo "WS PATH      : $WS_PATH"
echo "SINGBOX PORT : $SB_PORT"
echo "SINGBOX BIN  : $SB"
echo "CONFIG       : $CONFIG"
echo "NGINX CONFIG : $NGINX_CONFIG"

if [ -n "$PUBLIC_HOST" ]; then

    echo "PUBLIC HOST  : $PUBLIC_HOST"

fi

echo ""
echo "============================================================"
echo ""


# ============================================================
# 生成 sing-box 配置
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
# 生成 Nginx 配置
#
# 注意：
# 不修改 /etc/nginx/
# 所有运行时目录全部使用 /tmp
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


    # ========================================================
    # Logs
    # ========================================================

    access_log /dev/stdout;


    # ========================================================
    # 基础设置
    # ========================================================

    sendfile on;

    tcp_nopush on;

    keepalive_timeout 65;


    # ========================================================
    # Hostless root filesystem 是只读
    # 所有临时目录必须使用 /tmp
    # ========================================================

    client_body_temp_path ${NGINX_TMP}/client_body;

    proxy_temp_path ${NGINX_TMP}/proxy;

    fastcgi_temp_path ${NGINX_TMP}/fastcgi;

    uwsgi_temp_path ${NGINX_TMP}/uwsgi;

    scgi_temp_path ${NGINX_TMP}/scgi;


    server {

        listen 0.0.0.0:${PORT};

        server_name _;


        # ====================================================
        # 首页
        # ====================================================

        location = / {

            default_type text/plain;

            add_header Cache-Control "no-store";

            return 200 "Hostless VLESS is running\n";

        }


        # ====================================================
        # Health Check
        # ====================================================

        location = /health {

            default_type application/json;

            add_header Cache-Control "no-store";

            return 200 '{"status":"ok"}';

        }


        # ====================================================
        # VLESS WebSocket
        # ====================================================

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
# 1. 检查 sing-box binary
# ============================================================

echo ""
echo "[1/6] Checking sing-box binary..."
echo ""

"$SB" version


# ============================================================
# 2. 检查 sing-box 配置
# ============================================================

echo ""
echo "[2/6] Checking sing-box configuration..."
echo ""

"$SB" check -c "$CONFIG"

echo ""
echo "sing-box configuration OK"
echo ""


# ============================================================
# 3. 检查 nginx
# ============================================================

echo ""
echo "[3/6] Checking nginx configuration..."
echo ""

nginx \
    -t \
    -c "$NGINX_CONFIG"

echo ""
echo "nginx configuration OK"
echo ""


# ============================================================
# 自动输出节点
# ============================================================

if [ -n "$PUBLIC_HOST" ]; then

    # 删除可能误填的 https://
    CLEAN_HOST="$(printf '%s' "$PUBLIC_HOST" | sed 's#^https://##;s#^http://##;s#/$##')"

    ENCODED_PATH="$(printf '%s' "$WS_PATH" | sed 's#/#%2F#g')"


    echo ""
    echo "============================================================"
    echo "                      VLESS NODE"
    echo "============================================================"
    echo ""

    echo "vless://${UUID}@${CLEAN_HOST}:443?encryption=none&security=tls&type=ws&host=${CLEAN_HOST}&sni=${CLEAN_HOST}&path=${ENCODED_PATH}#Hostless-VLESS"

    echo ""
    echo "============================================================"
    echo ""
    echo "Protocol : VLESS"
    echo ""
    echo "Address  : ${CLEAN_HOST}"
    echo ""
    echo "Port     : 443"
    echo ""
    echo "UUID     : ${UUID}"
    echo ""
    echo "Network  : WebSocket"
    echo ""
    echo "Path     : ${WS_PATH}"
    echo ""
    echo "TLS      : enabled"
    echo ""
    echo "Host     : ${CLEAN_HOST}"
    echo ""
    echo "SNI      : ${CLEAN_HOST}"
    echo ""
    echo "Flow     : empty"
    echo ""
    echo "============================================================"
    echo ""

else

    echo ""
    echo "============================================================"
    echo "PUBLIC_HOST is not configured yet"
    echo "============================================================"
    echo ""
    echo "This is normal for the first deployment."
    echo ""
    echo "After Hostless gives you a public domain,"
    echo "add Environment Variable:"
    echo ""
    echo "PUBLIC_HOST=your-app.hostless.app"
    echo ""
    echo "Then redeploy."
    echo ""
    echo "Logs will automatically print the complete vless:// URL."
    echo ""
    echo "============================================================"
    echo ""

fi


# ============================================================
# 4. 启动 sing-box
# ============================================================

echo ""
echo "[4/6] Starting sing-box..."
echo ""

"$SB" run -c "$CONFIG" &

SB_PID=$!


sleep 2


if ! kill -0 "$SB_PID" 2>/dev/null; then

    echo ""
    echo "ERROR: sing-box failed to start."
    echo ""

    exit 1
fi


echo "sing-box PID: $SB_PID"


# ============================================================
# 5. 启动 nginx
# ============================================================

echo ""
echo "[5/6] Starting nginx..."
echo ""

nginx \
    -c "$NGINX_CONFIG" \
    -g "daemon off;" &

NGINX_PID=$!


sleep 2


if ! kill -0 "$NGINX_PID" 2>/dev/null; then

    echo ""
    echo "ERROR: nginx failed to start."
    echo ""

    kill "$SB_PID" 2>/dev/null || true

    exit 1
fi


echo "nginx PID: $NGINX_PID"


# ============================================================
# 启动成功
# ============================================================

echo ""
echo "============================================================"
echo ""
echo "        Hostless VLESS started successfully"
echo ""
echo "============================================================"
echo ""
echo "Public HTTP Port : $PORT"
echo ""
echo "WebSocket Path   : $WS_PATH"
echo ""
echo "Health Check     : /health"
echo ""
echo "sing-box Port    : $SB_PORT"
echo ""
echo "============================================================"
echo ""


# ============================================================
# 优雅退出
# ============================================================

shutdown() {

    echo ""
    echo "Received shutdown signal."
    echo ""

    if [ -n "${NGINX_PID:-}" ]; then

        kill "$NGINX_PID" 2>/dev/null || true

    fi


    if [ -n "${SB_PID:-}" ]; then

        kill "$SB_PID" 2>/dev/null || true

    fi


    wait "$NGINX_PID" 2>/dev/null || true

    wait "$SB_PID" 2>/dev/null || true


    echo "Stopped."

    exit 0
}


trap shutdown TERM INT HUP


# ============================================================
# 6. 监控服务
# ============================================================

echo ""
echo "[6/6] Service monitoring started."
echo ""


while true
do

    # ========================================================
    # sing-box
    # ========================================================

    if ! kill -0 "$SB_PID" 2>/dev/null; then

        echo ""
        echo "ERROR: sing-box stopped unexpectedly."
        echo ""

        kill "$NGINX_PID" 2>/dev/null || true

        exit 1
    fi


    # ========================================================
    # nginx
    # ========================================================

    if ! kill -0 "$NGINX_PID" 2>/dev/null; then

        echo ""
        echo "ERROR: nginx stopped unexpectedly."
        echo ""

        kill "$SB_PID" 2>/dev/null || true

        exit 1
    fi


    sleep 10

done
