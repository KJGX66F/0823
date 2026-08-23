#!/bin/sh

set -eu

# ============================================================
# Hostless + sing-box VLESS WebSocket
# Hostless Read-only filesystem compatible
# ============================================================


# ============================================================
# 用户配置
# ============================================================

UUID="${UUID:-}"

WS_PATH="${WS_PATH:-/vless}"

# Hostless 会自动注入 PORT
PORT="${PORT:-8000}"

# 部署成功后，可添加：
#
# PUBLIC_HOST=xxxx.hostless.app
#
# 不要带 https://
PUBLIC_HOST="${PUBLIC_HOST:-}"


# ============================================================
# 程序路径
# ============================================================

SINGBOX="/usr/local/bin/sing-box"

NGINX="/usr/sbin/nginx"


# ============================================================
# 内部端口
# ============================================================

SINGBOX_PORT="${SINGBOX_PORT:-10000}"


# ============================================================
# Hostless 根文件系统可能只读
# 所有动态文件放到 /tmp
# ============================================================

SINGBOX_CONFIG="/tmp/sing-box.json"

NGINX_CONFIG="/tmp/nginx.conf"

NGINX_PID_FILE="/tmp/nginx.pid"

NGINX_TMP="/tmp/nginx"


# ============================================================
# 创建 Nginx 临时目录
# ============================================================

mkdir -p \
    "${NGINX_TMP}/client_body" \
    "${NGINX_TMP}/proxy" \
    "${NGINX_TMP}/fastcgi" \
    "${NGINX_TMP}/uwsgi" \
    "${NGINX_TMP}/scgi"


# ============================================================
# UUID 检查
# ============================================================

if [ -z "$UUID" ]; then

    echo ""
    echo "============================================================"
    echo " ERROR: UUID environment variable is missing"
    echo "============================================================"
    echo ""
    echo "Please add Environment Variable:"
    echo ""
    echo "UUID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
    echo ""
    echo "============================================================"
    echo ""

    exit 1

fi


# ============================================================
# 修正 WebSocket Path
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
    echo " ERROR: sing-box not found"
    echo "============================================================"
    echo ""
    echo "Expected:"
    echo "$SINGBOX"
    echo ""

    echo "/usr/local/bin:"
    ls -lah /usr/local/bin 2>/dev/null || true

    echo ""
    exit 1

fi


# ============================================================
# 检查 nginx
# ============================================================

if [ ! -x "$NGINX" ]; then

    echo ""
    echo "============================================================"
    echo " ERROR: nginx not found"
    echo "============================================================"
    echo ""
    echo "Expected:"
    echo "$NGINX"
    echo ""

    echo "/usr/sbin:"
    ls -lah /usr/sbin 2>/dev/null || true

    echo ""
    exit 1

fi


# ============================================================
# 输出启动信息
# ============================================================

echo ""
echo "============================================================"
echo "          Hostless + sing-box VLESS WebSocket"
echo "============================================================"
echo ""
echo "PORT             : $PORT"
echo "WS PATH          : $WS_PATH"
echo "SINGBOX PORT     : $SINGBOX_PORT"
echo "SINGBOX BIN      : $SINGBOX"
echo "NGINX BIN        : $NGINX"
echo "SINGBOX CONFIG   : $SINGBOX_CONFIG"
echo "NGINX CONFIG     : $NGINX_CONFIG"

if [ -n "$PUBLIC_HOST" ]; then

    echo "PUBLIC HOST      : $PUBLIC_HOST"

fi

echo ""
echo "============================================================"
echo ""


# ============================================================
# 生成 sing-box 配置
# ============================================================

cat > "$SINGBOX_CONFIG" <<EOF
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
      "listen_port": ${SINGBOX_PORT},

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
# 重点：
# 不修改 /etc/nginx/*
#
# nginx.conf
# PID
# Cache
# Temp
#
# 全部使用 /tmp
# ============================================================

cat > "$NGINX_CONFIG" <<EOF
worker_processes 1;

error_log /dev/stderr info;

pid ${NGINX_PID_FILE};


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
    # 基础参数
    # ========================================================

    sendfile on;

    tcp_nopush on;

    tcp_nodelay on;

    keepalive_timeout 65;


    # ========================================================
    # Hostless 根文件系统只读
    #
    # 所有临时目录使用 /tmp
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
        #
        # 用于检测 Hostless 服务是否正常
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

            proxy_pass http://127.0.0.1:${SINGBOX_PORT};

            proxy_http_version 1.1;


            proxy_set_header Upgrade \$http_upgrade;

            proxy_set_header Connection "upgrade";


            proxy_set_header Host \$host;

            proxy_set_header X-Real-IP \$remote_addr;

            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;

            proxy_set_header X-Forwarded-Proto https;


            proxy_read_timeout 3600s;

            proxy_send_timeout 3600s;

            proxy_connect_timeout 60s;


            proxy_buffering off;

            proxy_request_buffering off;

        }

    }

}
EOF


# ============================================================
# STEP 1
# 检查 sing-box
# ============================================================

echo ""
echo "[1/6] Checking sing-box binary..."
echo ""

"$SINGBOX" version


# ============================================================
# STEP 2
# 检查 sing-box 配置
# ============================================================

echo ""
echo "[2/6] Checking sing-box configuration..."
echo ""

"$SINGBOX" check \
    -c "$SINGBOX_CONFIG"

echo ""
echo "sing-box configuration OK"
echo ""


# ============================================================
# STEP 3
# 检查 Nginx
# ============================================================

echo ""
echo "[3/6] Checking nginx binary..."
echo ""

"$NGINX" -v

echo ""
echo "[3/6] Checking nginx configuration..."
echo ""

"$NGINX" \
    -t \
    -c "$NGINX_CONFIG"

echo ""
echo "nginx configuration OK"
echo ""


# ============================================================
# 自动打印 VLESS 节点
# ============================================================

if [ -n "$PUBLIC_HOST" ]; then

    # ========================================================
    # 防止用户误填：
    #
    # https://abc.hostless.app/
    #
    # 自动变成：
    #
    # abc.hostless.app
    # ========================================================

    CLEAN_HOST="$(
        printf '%s' "$PUBLIC_HOST" |
        sed \
            -e 's#^https://##' \
            -e 's#^http://##' \
            -e 's#/$##'
    )"


    # ========================================================
    # URL Encode WebSocket Path
    # ========================================================

    ENCODED_PATH="$(
        printf '%s' "$WS_PATH" |
        sed 's#/#%2F#g'
    )"


    VLESS_LINK="vless://${UUID}@${CLEAN_HOST}:443?encryption=none&security=tls&type=ws&host=${CLEAN_HOST}&sni=${CLEAN_HOST}&path=${ENCODED_PATH}#Hostless-VLESS"


    echo ""
    echo "============================================================"
    echo "                       VLESS NODE"
    echo "============================================================"
    echo ""
    echo "$VLESS_LINK"
    echo ""
    echo "============================================================"
    echo ""
    echo "Protocol : VLESS"
    echo ""
    echo "Address  : $CLEAN_HOST"
    echo ""
    echo "Port     : 443"
    echo ""
    echo "UUID     : $UUID"
    echo ""
    echo "Network  : WebSocket"
    echo ""
    echo "Path     : $WS_PATH"
    echo ""
    echo "TLS      : enabled"
    echo ""
    echo "Host     : $CLEAN_HOST"
    echo ""
    echo "SNI      : $CLEAN_HOST"
    echo ""
    echo "Flow     : empty"
    echo ""
    echo "============================================================"
    echo ""

else

    echo ""
    echo "============================================================"
    echo " PUBLIC_HOST is not configured"
    echo "============================================================"
    echo ""
    echo "This is normal for the first deployment."
    echo ""
    echo "After Hostless gives you a public domain,"
    echo "add Environment Variable:"
    echo ""
    echo "PUBLIC_HOST=xxxx.hostless.app"
    echo ""
    echo "Then redeploy."
    echo ""
    echo "The complete vless:// node will be printed here."
    echo ""
    echo "============================================================"
    echo ""

fi


# ============================================================
# STEP 4
# 启动 sing-box
# ============================================================

echo ""
echo "[4/6] Starting sing-box..."
echo ""

"$SINGBOX" run \
    -c "$SINGBOX_CONFIG" &

SINGBOX_PID=$!


sleep 2


if ! kill -0 "$SINGBOX_PID" 2>/dev/null; then

    echo ""
    echo "============================================================"
    echo " ERROR: sing-box failed to start"
    echo "============================================================"
    echo ""

    exit 1

fi


echo ""
echo "sing-box started successfully"
echo "PID: $SINGBOX_PID"
echo ""


# ============================================================
# STEP 5
# 启动 Nginx
# ============================================================

echo ""
echo "[5/6] Starting nginx..."
echo ""

"$NGINX" \
    -c "$NGINX_CONFIG" \
    -g "daemon off;" &

NGINX_PID=$!


sleep 2


if ! kill -0 "$NGINX_PID" 2>/dev/null; then

    echo ""
    echo "============================================================"
    echo " ERROR: nginx failed to start"
    echo "============================================================"
    echo ""

    kill "$SINGBOX_PID" 2>/dev/null || true

    exit 1

fi


echo ""
echo "nginx started successfully"
echo "PID: $NGINX_PID"
echo ""


# ============================================================
# 启动完成
# ============================================================

echo ""
echo "============================================================"
echo ""
echo "        Hostless VLESS started successfully"
echo ""
echo "============================================================"
echo ""
echo "HTTP Port      : $PORT"
echo ""
echo "WebSocket Path : $WS_PATH"
echo ""
echo "Health Check   : /health"
echo ""
echo "sing-box Port  : $SINGBOX_PORT"
echo ""
echo "============================================================"
echo ""


# ============================================================
# 退出处理
# ============================================================

shutdown()
{

    echo ""
    echo "============================================================"
    echo "Shutdown signal received"
    echo "============================================================"
    echo ""


    if [ -n "${NGINX_PID:-}" ]; then

        kill "$NGINX_PID" 2>/dev/null || true

    fi


    if [ -n "${SINGBOX_PID:-}" ]; then

        kill "$SINGBOX_PID" 2>/dev/null || true

    fi


    if [ -n "${NGINX_PID:-}" ]; then

        wait "$NGINX_PID" 2>/dev/null || true

    fi


    if [ -n "${SINGBOX_PID:-}" ]; then

        wait "$SINGBOX_PID" 2>/dev/null || true

    fi


    echo ""
    echo "Hostless VLESS stopped."
    echo ""

    exit 0
}


trap shutdown TERM INT HUP


# ============================================================
# STEP 6
# 服务监控
# ============================================================

echo ""
echo "[6/6] Service monitoring started."
echo ""


while true
do

    # ========================================================
    # 检查 sing-box
    # ========================================================

    if ! kill -0 "$SINGBOX_PID" 2>/dev/null; then

        echo ""
        echo "============================================================"
        echo " ERROR: sing-box stopped unexpectedly"
        echo "============================================================"
        echo ""

        kill "$NGINX_PID" 2>/dev/null || true

        exit 1

    fi


    # ========================================================
    # 检查 nginx
    # ========================================================

    if ! kill -0 "$NGINX_PID" 2>/dev/null; then

        echo ""
        echo "============================================================"
        echo " ERROR: nginx stopped unexpectedly"
        echo "============================================================"
        echo ""

        kill "$SINGBOX_PID" 2>/dev/null || true

        exit 1

    fi


    sleep 10

done
