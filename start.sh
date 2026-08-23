#!/bin/sh

set -eu

# ============================================================
# Shulker DevSpace + sing-box
# VLESS Reality TCP + Hysteria2 UDP
# ============================================================

SINGBOX_VERSION="${SINGBOX_VERSION:-1.13.19}"

# 容器内部监听端口
VLESS_PORT="${VLESS_PORT:-4433}"
HY2_PORT="${HY2_PORT:-8443}"

# 公网信息
PUBLIC_IP="${PUBLIC_IP:-}"

# 如果 Shulker 公网映射端口和容器端口不同，可单独修改
PUBLIC_VLESS_PORT="${PUBLIC_VLESS_PORT:-$VLESS_PORT}"
PUBLIC_HY2_PORT="${PUBLIC_HY2_PORT:-$HY2_PORT}"

# Reality 参数
REALITY_SERVER="${REALITY_SERVER:-www.microsoft.com}"
REALITY_SERVER_PORT="${REALITY_SERVER_PORT:-443}"

# HY2 自签证书 SNI
HY2_SNI="${HY2_SNI:-www.bing.com}"

# ============================================================
# 状态目录
#
# 默认存在 /project 下。
#
# 如果创建了 Shulker Persistent Volume，
# 推荐挂载到 /data，然后设置：
#
# STATE_DIR=/data/shulker-singbox
#
# ============================================================

STATE_DIR="${STATE_DIR:-/project/.shulker-singbox}"

mkdir -p "$STATE_DIR"

chmod 700 "$STATE_DIR" 2>/dev/null || true

STATE_FILE="$STATE_DIR/state.env"
CONFIG="$STATE_DIR/config.json"

CERT_FILE="$STATE_DIR/hy2-cert.pem"
KEY_FILE="$STATE_DIR/hy2-key.pem"

SB="$STATE_DIR/sing-box"


# ============================================================
# 安装基础依赖
# ============================================================

install_dependencies() {

    NEED_INSTALL=0

    command -v tar >/dev/null 2>&1 || NEED_INSTALL=1
    command -v openssl >/dev/null 2>&1 || NEED_INSTALL=1

    if ! command -v curl >/dev/null 2>&1 && \
       ! command -v wget >/dev/null 2>&1; then
        NEED_INSTALL=1
    fi

    if [ "$NEED_INSTALL" = "0" ]; then
        return
    fi

    echo ""
    echo "[1/8] Installing dependencies..."
    echo ""

    if [ "$(id -u)" = "0" ]; then
        SUDO=""
    else
        SUDO="sudo"
    fi

    if command -v apt-get >/dev/null 2>&1; then

        $SUDO apt-get update

        $SUDO apt-get install -y \
            curl \
            ca-certificates \
            tar \
            openssl

    elif command -v apk >/dev/null 2>&1; then

        $SUDO apk add --no-cache \
            curl \
            ca-certificates \
            tar \
            openssl

    else

        echo "ERROR: Unsupported Linux image."
        echo "Please use Debian / Ubuntu / Alpine."
        exit 1
    fi
}


# ============================================================
# 下载 sing-box
# ============================================================

download_singbox() {

    if [ -x "$SB" ]; then
        return
    fi

    echo ""
    echo "[2/8] Downloading sing-box ${SINGBOX_VERSION}..."
    echo ""

    MACHINE="$(uname -m)"

    case "$MACHINE" in

        x86_64|amd64)
            ARCH="amd64"
            ;;

        aarch64|arm64)
            ARCH="arm64"
            ;;

        *)
            echo "ERROR: Unsupported architecture: $MACHINE"
            exit 1
            ;;
    esac

    FILE="sing-box-${SINGBOX_VERSION}-linux-${ARCH}"

    URL="https://github.com/SagerNet/sing-box/releases/download/v${SINGBOX_VERSION}/${FILE}.tar.gz"

    TMP="/tmp/sing-box.tar.gz"
    TMP_DIR="/tmp/sing-box-extract"

    rm -rf "$TMP_DIR"
    mkdir -p "$TMP_DIR"

    if command -v curl >/dev/null 2>&1; then

        curl \
            --fail \
            --location \
            --retry 3 \
            "$URL" \
            -o "$TMP"

    else

        wget \
            -O "$TMP" \
            "$URL"

    fi

    tar -xzf "$TMP" -C "$TMP_DIR"

    cp \
        "$TMP_DIR/$FILE/sing-box" \
        "$SB"

    chmod +x "$SB"

    rm -rf "$TMP" "$TMP_DIR"

    echo ""
    echo "sing-box installed:"
    "$SB" version
}


# ============================================================
# 读取以前生成的参数
# ============================================================

load_state() {

    # 保存用户环境变量，环境变量优先于 state.env
    ENV_UUID="${UUID:-}"
    ENV_PRIVATE_KEY="${PRIVATE_KEY:-}"
    ENV_PUBLIC_KEY="${PUBLIC_KEY:-}"
    ENV_SHORT_ID="${SHORT_ID:-}"
    ENV_HY2_PASSWORD="${HY2_PASSWORD:-}"

    UUID=""
    PRIVATE_KEY=""
    PUBLIC_KEY=""
    SHORT_ID=""
    HY2_PASSWORD=""

    if [ -f "$STATE_FILE" ]; then

        # shellcheck disable=SC1090
        . "$STATE_FILE"

    fi

    [ -n "$ENV_UUID" ] && UUID="$ENV_UUID"
    [ -n "$ENV_PRIVATE_KEY" ] && PRIVATE_KEY="$ENV_PRIVATE_KEY"
    [ -n "$ENV_PUBLIC_KEY" ] && PUBLIC_KEY="$ENV_PUBLIC_KEY"
    [ -n "$ENV_SHORT_ID" ] && SHORT_ID="$ENV_SHORT_ID"
    [ -n "$ENV_HY2_PASSWORD" ] && HY2_PASSWORD="$ENV_HY2_PASSWORD"
}


# ============================================================
# 自动生成 UUID / Reality / HY2 密码
# ============================================================

generate_credentials() {

    echo ""
    echo "[3/8] Preparing credentials..."
    echo ""

    if [ -z "$UUID" ]; then

        UUID="$("$SB" generate uuid)"

    fi


    if [ -z "$PRIVATE_KEY" ] || [ -z "$PUBLIC_KEY" ]; then

        KEYPAIR="$("$SB" generate reality-keypair)"

        PRIVATE_KEY="$(
            printf '%s\n' "$KEYPAIR" |
            awk -F': ' '/PrivateKey:/ {print $2}'
        )"

        PUBLIC_KEY="$(
            printf '%s\n' "$KEYPAIR" |
            awk -F': ' '/PublicKey:/ {print $2}'
        )"

        if [ -z "$PRIVATE_KEY" ] || [ -z "$PUBLIC_KEY" ]; then

            echo "ERROR: Failed to generate Reality keypair."
            echo "$KEYPAIR"
            exit 1

        fi
    fi


    if [ -z "$SHORT_ID" ]; then

        # Reality short_id：8 位十六进制
        SHORT_ID="$(openssl rand -hex 4)"

    fi


    if [ -z "$HY2_PASSWORD" ]; then

        # 使用纯十六进制，方便直接放进 URL
        HY2_PASSWORD="$(openssl rand -hex 16)"

    fi


    # 保存，避免普通重启后参数改变
    umask 077

    cat > "$STATE_FILE" <<EOF
UUID='$UUID'
PRIVATE_KEY='$PRIVATE_KEY'
PUBLIC_KEY='$PUBLIC_KEY'
SHORT_ID='$SHORT_ID'
HY2_PASSWORD='$HY2_PASSWORD'
EOF

    chmod 600 "$STATE_FILE" 2>/dev/null || true
}


# ============================================================
# HY2 自签证书
# ============================================================

generate_hy2_certificate() {

    if [ -s "$CERT_FILE" ] && [ -s "$KEY_FILE" ]; then
        return
    fi

    echo ""
    echo "[4/8] Generating Hysteria2 TLS certificate..."
    echo ""

    openssl req \
        -x509 \
        -newkey rsa:2048 \
        -nodes \
        -sha256 \
        -days 3650 \
        -keyout "$KEY_FILE" \
        -out "$CERT_FILE" \
        -subj "/CN=${HY2_SNI}"

    chmod 600 "$KEY_FILE" 2>/dev/null || true
}


# ============================================================
# 生成 sing-box 配置
# ============================================================

generate_config() {

    echo ""
    echo "[5/8] Creating sing-box configuration..."
    echo ""

    cat > "$CONFIG" <<EOF
{
  "log": {
    "level": "info",
    "timestamp": true
  },

  "inbounds": [

    {
      "type": "vless",
      "tag": "vless-reality",

      "listen": "0.0.0.0",
      "listen_port": ${VLESS_PORT},

      "users": [
        {
          "name": "shulker",
          "uuid": "${UUID}",
          "flow": "xtls-rprx-vision"
        }
      ],

      "tls": {
        "enabled": true,
        "server_name": "${REALITY_SERVER}",

        "reality": {
          "enabled": true,

          "handshake": {
            "server": "${REALITY_SERVER}",
            "server_port": ${REALITY_SERVER_PORT}
          },

          "private_key": "${PRIVATE_KEY}",

          "short_id": [
            "${SHORT_ID}"
          ]
        }
      }
    },

    {
      "type": "hysteria2",
      "tag": "hy2",

      "listen": "0.0.0.0",
      "listen_port": ${HY2_PORT},

      "users": [
        {
          "name": "shulker",
          "password": "${HY2_PASSWORD}"
        }
      ],

      "tls": {
        "enabled": true,
        "certificate_path": "${CERT_FILE}",
        "key_path": "${KEY_FILE}"
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

    chmod 600 "$CONFIG" 2>/dev/null || true
}


# ============================================================
# 检查配置
# ============================================================

check_config() {

    echo ""
    echo "[6/8] Checking configuration..."
    echo ""

    "$SB" check -c "$CONFIG"

    echo ""
    echo "Configuration OK"
}


# ============================================================
# 输出节点
# ============================================================

print_nodes() {

    echo ""
    echo "============================================================"
    echo "               Shulker sing-box 双节点"
    echo "============================================================"
    echo ""

    echo "UUID:"
    echo "$UUID"
    echo ""

    echo "Reality Public Key:"
    echo "$PUBLIC_KEY"
    echo ""

    echo "Reality Short ID:"
    echo "$SHORT_ID"
    echo ""

    echo "HY2 Password:"
    echo "$HY2_PASSWORD"
    echo ""

    echo "------------------------------------------------------------"

    if [ -n "$PUBLIC_IP" ]; then

        VLESS_LINK="vless://${UUID}@${PUBLIC_IP}:${PUBLIC_VLESS_PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${REALITY_SERVER}&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=tcp#Shulker-VLESS-Reality"

        HY2_LINK="hysteria2://${HY2_PASSWORD}@${PUBLIC_IP}:${PUBLIC_HY2_PORT}/?sni=${HY2_SNI}&insecure=1#Shulker-HY2"

        echo ""
        echo "【VLESS Reality】"
        echo ""
        echo "$VLESS_LINK"

        echo ""
        echo "------------------------------------------------------------"
        echo ""
        echo "【Hysteria2】"
        echo ""
        echo "$HY2_LINK"

        echo ""
        echo "============================================================"
        echo ""
        echo "VLESS Reality:"
        echo "Address    : $PUBLIC_IP"
        echo "Port       : $PUBLIC_VLESS_PORT"
        echo "UUID       : $UUID"
        echo "Flow       : xtls-rprx-vision"
        echo "Security   : reality"
        echo "SNI        : $REALITY_SERVER"
        echo "Public Key : $PUBLIC_KEY"
        echo "Short ID   : $SHORT_ID"
        echo "Fingerprint: chrome"
        echo ""
        echo "Hysteria2:"
        echo "Address    : $PUBLIC_IP"
        echo "Port       : $PUBLIC_HY2_PORT"
        echo "Password   : $HY2_PASSWORD"
        echo "SNI        : $HY2_SNI"
        echo "TLS insecure: true"
        echo ""

    else

        echo ""
        echo "PUBLIC_IP 尚未设置。"
        echo ""
        echo "请先在 Shulker Port Manager 创建公网端口，"
        echo "获得公网 IP 后添加："
        echo ""
        echo "PUBLIC_IP=你的公网IP"
        echo ""
        echo "然后 Restart。"
        echo ""
        echo "脚本会自动打印完整 VLESS + HY2 节点。"
        echo ""

    fi

    echo "============================================================"
}


# ============================================================
# Main
# ============================================================

install_dependencies

download_singbox

load_state

generate_credentials

generate_hy2_certificate

generate_config

check_config

print_nodes

echo ""
echo "[7/8] VLESS TCP port : $VLESS_PORT"
echo "[7/8] HY2 UDP port   : $HY2_PORT"
echo ""

echo "[8/8] Starting sing-box..."
echo ""

exec "$SB" run -c "$CONFIG"
