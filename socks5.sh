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

SERVICE_NAME="sing-box-socks5"
SERVICE_SYSTEMD="/etc/systemd/system/${SERVICE_NAME}.service"
SERVICE_OPENRC="/etc/init.d/${SERVICE_NAME}"

SB_VERSION="1.12.13"
SB_VER="v${SB_VERSION}"

########################
# 颜色工具
########################
green(){ echo -e "\e[1;32m$1\033[0m"; }
yellow(){ echo -e "\e[1;33m$1\033[0m"; }
red(){ echo -e "\e[31m$1\033[0m"; }
blue(){ echo -e "\e[1;34m$1\033[0m"; }

########################
# 工具函数
########################
gen_username() { tr -dc 'A-Za-z0-9' </dev/urandom | head -c 10; }
gen_password() { tr -dc 'A-Za-z0-9!@#%^_+' </dev/urandom | head -c 12; }

check_port_free() {
  ss -lntH | grep -E "(:|\])$1\b" >/dev/null && return 1 || return 0
}

########################
# init 系统检测
########################
detect_init_system() {
  if command -v systemctl >/dev/null 2>&1 && pidof systemd >/dev/null 2>&1; then
    INIT_SYSTEM="systemd"
  elif command -v rc-service >/dev/null 2>&1; then
    INIT_SYSTEM="openrc"
  else
    INIT_SYSTEM=""
  fi
}

########################
# 非交互兜底校验
########################
ensure_required_env() {
  red "❌ 缺少必要参数：PORT"
  red "👉 当前环境无法进行交互输入"
  yellow "👉 示例：PORT=1080 bash socks5.sh"
  exit 1
}

########################
# 停止旧服务
########################
stop_existing_service() {
  detect_init_system

  case "$INIT_SYSTEM" in
    systemd)
      systemctl is-active --quiet "$SERVICE_NAME" && systemctl stop "$SERVICE_NAME"
      ;;
    openrc)
      rc-service "$SERVICE_NAME" status >/dev/null 2>&1 && rc-service "$SERVICE_NAME" stop
      ;;
  esac
}

########################
# 参数处理
########################
handle_params() {

  ########################
  # 安装模式判定
  ########################
  if [[ -n "$PORT" || -n "$USERNAME" || -n "$PASSWORD" ]]; then
    NON_INTERACTIVE=1
    yellow "👉 非交互式安装"
  else
    NON_INTERACTIVE=0
    yellow "👉 交互式安装"
  fi

  ########################
  # PORT 处理
  ########################
  if [[ "$NON_INTERACTIVE" == "1" && -z "$PORT" ]]; then
    ensure_required_env
  fi

  while :; do
    if [[ -z "$PORT" ]]; then
      read -rp "请输入端口号: " PORT
    fi

    if ! [[ "$PORT" =~ ^[0-9]+$ ]] || ((PORT < 1 || PORT > 65535)); then
      red "❌ 端口必须是 1-65535 的数字"
      [[ "$NON_INTERACTIVE" == "1" ]] && exit 1
      PORT=""
      continue
    fi

    if ! check_port_free "$PORT"; then
      red "❌ 端口被占用，请重新输入"
      [[ "$NON_INTERACTIVE" == "1" ]] && exit 1
      PORT=""
      continue
    fi

    break
  done

  ########################
  # USERNAME / PASSWORD
  ########################
  if [[ "$NON_INTERACTIVE" == "1" ]]; then
    USERNAME="${USERNAME:-$(gen_username)}"
    PASSWORD="${PASSWORD:-$(gen_password)}"
  else
    read -rp "用户名（回车自动生成）: " INPUT_USERNAME
    USERNAME="${INPUT_USERNAME:-$(gen_username)}"
    read -rp "密码（回车自动生成）: " INPUT_PASSWORD
    PASSWORD="${INPUT_PASSWORD:-$(gen_password)}"
  fi
}

########################
# 安装依赖
########################
install_deps() {
  local need_install=0
  for bin in curl tar gzip jq ss; do
    command -v "$bin" >/dev/null 2>&1 || need_install=1
  done

  [[ "$need_install" == "0" ]] && return 0

  yellow "👉 正在安装依赖..."

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
# 安装 sing-box
########################

install_singbox() {
  mkdir -p "$INSTALL_DIR"

  case "$(uname -m)" in
    x86_64)  SB_ARCH="amd64" ;;
    aarch64) SB_ARCH="arm64" ;;
    armv7l)  SB_ARCH="armv7" ;;
    *)
      red "❌ 不支持的架构: $(uname -m)"
      exit 1
      ;;
  esac

  TMP_DIR=$(mktemp -d)
  trap 'rm -rf "$TMP_DIR"' EXIT

  URL="https://github.com/SagerNet/sing-box/releases/download/${SB_VER}/sing-box-${SB_VERSION}-linux-${SB_ARCH}.tar.gz"

  yellow "👉 下载 sing-box ${SB_VERSION} (${SB_ARCH})"

  curl -fL \
    --retry 3 \
    --retry-delay 2 \
    --connect-timeout 10 \
    -o "$TMP_DIR/sb.tgz" "$URL" \
    || {
      red "❌ sing-box 下载失败"
      red "👉 请检查网络或 GitHub 访问是否正常"
      exit 1
    }

  tar -xf "$TMP_DIR/sb.tgz" -C "$TMP_DIR" \
    || {
      red "❌ sing-box 解压失败，文件可能损坏"
      exit 1
    }

  cp "$TMP_DIR"/sing-box-*/sing-box "$BIN_FILE" \
    || {
      red "❌ 未找到 sing-box 可执行文件"
      exit 1
    }

  chmod +x "$BIN_FILE"

  rm -rf "$TMP_DIR"
  trap - EXIT

  green "✅ sing-box ${SB_VERSION} 安装完成"
}


########################
# 生成配置
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
        { "username": "$USERNAME", "password": "$PASSWORD" }
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
# service 模板
########################
write_systemd_service() {
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
}

write_openrc_service() {
  cat > "$SERVICE_OPENRC" <<EOF
#!/sbin/openrc-run
name="$SERVICE_NAME"
command="$BIN_FILE"
command_args="run -c $CONFIG_FILE"
command_background="no"

depend() { need net; }
EOF
  chmod +x "$SERVICE_OPENRC"
}

########################
# 启动服务
########################
enable_and_start_service() {
  case "$INIT_SYSTEM" in
    systemd)
      systemctl daemon-reload
      systemctl enable "$SERVICE_NAME"
      systemctl restart "$SERVICE_NAME"
      ;;
    openrc)
      rc-update add "$SERVICE_NAME" default
      rc-service "$SERVICE_NAME" restart
      ;;
    *)
      red "❌ 未识别的 init 系统"
      exit 1
      ;;
  esac
}

start_service() {
  detect_init_system

  case "$INIT_SYSTEM" in
    systemd) write_systemd_service ;;
    openrc)  write_openrc_service ;;
  esac

  enable_and_start_service
}

########################
# 管理命令提示
########################
print_manage_commands() {
  echo
  yellow "管理命令："

  if [[ "$INIT_SYSTEM" == "systemd" ]]; then
    green "查看状态:  systemctl status $SERVICE_NAME"
    green "重启服务:  systemctl restart $SERVICE_NAME"
    green "查看日志:  journalctl -u $SERVICE_NAME -f"
  else
    green "查看状态:  rc-service $SERVICE_NAME status"
    green "重启服务:  rc-service $SERVICE_NAME restart"
    green "查看日志:  tail -f $LOG_FILE"
  fi
}

########################
# 节点信息
########################
show_node() {
  PORT=$(jq -r '.inbounds[0].listen_port' "$CONFIG_FILE")
  USERNAME=$(jq -r '.inbounds[0].users[0].username' "$CONFIG_FILE")
  PASSWORD=$(jq -r '.inbounds[0].users[0].password' "$CONFIG_FILE")

  IP_V4=$(curl -s4 --max-time 3 ipv4.ip.sb || true)
  IP_V6=$(curl -s6 --max-time 3 ipv6.ip.sb || true)

  echo
  green "👉 Socks5 节点信息"
  [[ -n "$IP_V4" ]] && blue   "IPv4: socks5://$USERNAME:$PASSWORD@$IP_V4:$PORT"
  [[ -n "$IP_V6" ]] && yellow "IPv6: socks5://$USERNAME:$PASSWORD@[$IP_V6]:$PORT"

  print_manage_commands
}



########################
# 卸载
########################
uninstall() {
  stop_existing_service
  rm -f "$SERVICE_SYSTEMD" "$SERVICE_OPENRC"
  rm -rf "$INSTALL_DIR"
  green "✅ socks5 已卸载"
  exit 0
}

########################
# main
########################
main() {
  case "${1:-}" in
    uninstall) uninstall ;;
    node) show_node; exit 0 ;;
  esac

  handle_params
  stop_existing_service
  install_deps
  install_singbox
  generate_config
  start_service
  show_node
  print_manage_commands
}

main "$@"

