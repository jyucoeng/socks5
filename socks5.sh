#!/bin/bash
# sing-box socks5 脚本
# - 固定 sing-box 版本
# - IPv6 自动检测
# - 多架构
# - 自动重启（当前socks5服务支持系统重启后自动拉起socks5服务）
# 用法如下：
# 1、安装（PORT为必填,用户名/密码不填会自动生成）：
#   PORT=端口号 USERNAME=用户名 PASSWORD=密码 bash <(curl -Ls https://raw.githubusercontent.com/jyucoeng/socks5/refs/heads/main/socks5.sh)
#   
# 2、卸载：
#   bash <(curl -Ls https://raw.githubusercontent.com/jyucoeng/socks5/refs/heads/main/socks5.sh) uninstall
#
# 3、命令行中如何测试socks5串通不通？？只要选下方的命令执行，成功返回ip就代表成功，不用在意是否返回的是什么ip，比如你明明是ipv6环境的服务器确返回了一个ipv4.这种情况其实也是对的。
#  curl --socks5-hostname "ipv4:端口号"  -U 用户名:密码 http://ip.sb
#  curl -6 --socks5-hostname "[ipv6]:端口号" -U 用户名:密码 http://ip.sb
#
set -e

########################
# root 校验
########################
[ "$(id -u)" -ne 0 ] && { echo "❌ 请使用 root 运行"; exit 1; }

########################
# 全局常量
########################
INSTALL_DIR="/usr/local/sb"
CONFIG_FILE="$INSTALL_DIR/config.json"
BIN_FILE="$INSTALL_DIR/sing-box-socks5"
LOG_FILE="$INSTALL_DIR/run.log"

SERVICE_SYSTEMD="/etc/systemd/system/sing-box-socks5.service"
SERVICE_OPENRC="/etc/init.d/sing-box-socks5"

SB_VERSION="1.12.13"
SB_VER="v${SB_VERSION}"

########################
# 工具函数
########################
green(){ echo -e "\e[1;32m$1\033[0m"; }
yellow(){ echo -e "\e[1;33m$1\033[0m"; }
red(){ echo -e "\e[31m$1\033[0m"; }
blue(){ echo -e "\e[1;34m$1\033[0m"; }

gen_username() { tr -dc 'A-Za-z0-9' </dev/urandom | head -c 10; }
gen_password() { tr -dc 'A-Za-z0-9!@#%^_+' </dev/urandom | head -c 12; }

check_port_free() {
  ss -lntH | grep -E "(:|\])$1\b" >/dev/null && return 1 || return 0
}

########################
# 停止旧服务（覆盖安装关键）
########################
stop_existing_service() {
  if command -v systemctl >/dev/null 2>&1; then
    systemctl is-active --quiet sing-box-socks5 && {
      yellow "👉 停止已存在的 sing-box-socks5（systemd）"
      systemctl stop sing-box-socks5
    }
  elif command -v rc-service >/dev/null 2>&1; then
    rc-service sing-box-socks5 status >/dev/null 2>&1 && {
      yellow "👉 停止已存在的 sing-box-socks5（OpenRC）"
      rc-service sing-box-socks5 stop
    }
  fi
}

########################
# 参数处理
########################
handle_params() {

  # 非 TTY 保护
  if [[ ! -t 0 && -z "$PORT" ]]; then
    red "❌ 当前为非交互环境，且未指定 PORT，无法继续"
    exit 1
  fi

  # 非交互判定
  if [[ -n "$PORT" || -n "$USERNAME" || -n "$PASSWORD" ]]; then
    NON_INTERACTIVE=1
    yellow "👉 非交互式安装（检测到环境变量）"
  else
    NON_INTERACTIVE=0
    yellow "👉 交互式安装"
  fi

  ########################
  # PORT（强制人工确认 + 校验）
  ########################
  if [[ -z "$PORT" ]]; then
    red "❗ 必须指定端口号"
    while :; do
      read -rp "请输入端口号: " PORT

      [[ "$PORT" =~ ^[0-9]+$ ]] && (( PORT >= 1 && PORT <= 65535 )) || {
        red "❌ 端口必须是 1-65535 的数字"
        PORT=""
        continue
      }

      check_port_free "$PORT" && break
      red "❌ 端口被占用，请重新输入"
    done
  else
    [[ "$PORT" =~ ^[0-9]+$ ]] && (( PORT >= 1 && PORT <= 65535 )) || {
      red "❌ PORT 必须是 1-65535 的数字"
      exit 1
    }
  fi

  ########################
  # USERNAME / PASSWORD
  ########################
  if [[ "$NON_INTERACTIVE" == "1" ]]; then
    USERNAME="${USERNAME:-$(gen_username)}"
    PASSWORD="${PASSWORD:-$(gen_password)}"
  else
    read -rp "请输入用户名（直接回车自动生成）: " INPUT_USERNAME
    USERNAME="${INPUT_USERNAME:-$(gen_username)}"

    read -rp "请输入密码（直接回车自动生成）: " INPUT_PASSWORD
    PASSWORD="${INPUT_PASSWORD:-$(gen_password)}"
  fi
}

########################
# 安装依赖
########################
install_deps() {
  if command -v apt >/dev/null 2>&1; then
    apt update -y
    apt install -y curl tar gzip jq iproute2
  elif command -v yum >/dev/null 2>&1; then
    yum install -y curl tar gzip jq iproute
  elif command -v apk >/dev/null 2>&1; then
    apk add --no-cache curl tar gzip jq iproute2
  else
    red "❌ 不支持的系统"
    exit 1
  fi
}

########################
# 安装 sing-box（失败自动清理）
########################
install_singbox() {
  mkdir -p "$INSTALL_DIR"

  ARCH=$(uname -m)
  case "$ARCH" in
    x86_64)  SB_ARCH="amd64" ;;
    aarch64) SB_ARCH="arm64" ;;
    armv7l)  SB_ARCH="armv7" ;;
    *) red "❌ 不支持的架构: $ARCH"; exit 1 ;;
  esac

  TMP_DIR=$(mktemp -d)
  trap 'rm -rf "$TMP_DIR"' EXIT

  URL="https://github.com/SagerNet/sing-box/releases/download/${SB_VER}/sing-box-${SB_VERSION}-linux-${SB_ARCH}.tar.gz"

  curl -L -o "$TMP_DIR/sb.tgz" "$URL"
  tar -xf "$TMP_DIR/sb.tgz" -C "$TMP_DIR"

  cp "$TMP_DIR"/sing-box-*/sing-box "$BIN_FILE"
  chmod +x "$BIN_FILE"

  rm -rf "$TMP_DIR"
  trap - EXIT
}

########################
# 生成配置（原子写入）
########################
generate_config() {
  TMP_CFG=$(mktemp)
  cat > "$TMP_CFG" <<EOF
{
  "log": {
    "level": "info",
    "output": "$LOG_FILE"
  },
  "inbounds": [
    {
      "type": "socks",
      "listen": "::",
      "listen_port": $PORT,
      "users": [
        {
          "username": "$USERNAME",
          "password": "$PASSWORD"
        }
      ]
    }
  ],
  "outbounds": [
    { "type": "direct" }
  ]
}
EOF
  mv "$TMP_CFG" "$CONFIG_FILE"
}

########################
# 启动服务（systemd / OpenRC）
########################
start_service() {

  if command -v systemctl >/dev/null 2>&1; then
    cat > "$SERVICE_SYSTEMD" <<EOF
[Unit]
Description=Sing-box Socks5 Service
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=$BIN_FILE run -c $CONFIG_FILE
Restart=always
RestartSec=3
LimitNOFILE=1048576
WorkingDirectory=$INSTALL_DIR

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable sing-box-socks5
    systemctl restart sing-box-socks5
    INIT_SYSTEM="systemd"
    return
  fi

  if command -v rc-service >/dev/null 2>&1; then
    cat > "$SERVICE_OPENRC" <<EOF
#!/sbin/openrc-run

name="sing-box-socks5"
command="$BIN_FILE"
command_args="run -c $CONFIG_FILE"
command_background="no"

depend() {
  need net
}
EOF

    chmod +x "$SERVICE_OPENRC"
    rc-update add sing-box-socks5 default
    rc-service sing-box-socks5 restart
    INIT_SYSTEM="openrc"
    return
  fi

  red "❌ 未识别的 init 系统"
  exit 1
}

########################
# main
########################
main() {
  handle_params
  stop_existing_service
  install_deps
  install_singbox
  generate_config
  start_service

  IP_V4=$(curl -s4 --max-time 3 ipv4.ip.sb || true)
  IP_V6=$(curl -s6 --max-time 3 ipv6.ip.sb || true)

  echo
  green "✅ Socks5 服务已启动"
  [[ -n "$IP_V4" ]] && blue   "IPv4: socks5://$USERNAME:$PASSWORD@$IP_V4:$PORT"
  [[ -n "$IP_V6" ]] && yellow "IPv6: socks5://$USERNAME:$PASSWORD@[$IP_V6]:$PORT"

  echo
  yellow "管理命令："
  if [[ "$INIT_SYSTEM" == "systemd" ]]; then
    green "查看状态:  systemctl status sing-box-socks5"
    green "重启服务:   systemctl restart sing-box-socks5"
    green "查看日志:   journalctl -u sing-box-socks5 -f"
  else
    green "查看状态:  rc-service sing-box-socks5 status"
    green "重启服务:   rc-service sing-box-socks5 restart"
    green "查看日志:   tail -f $LOG_FILE"
  fi
}

main "$@"
