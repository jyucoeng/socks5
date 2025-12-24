#!/bin/bash
# sing-box socks5 脚本
# - 固定 sing-box 版本
# - IPv6 自动检测
# - 多架构
# - 自动重启（当前socks5服务支持系统重启后自动拉起socks5服务）
# 用法如下：
# 1、安装：
#   PORT=端口号 USERNAME=用户名 PASSWORD=密码 bash <(curl -Ls https://raw.githubusercontent.com/jyucoeng/socks5/refs/heads/main/socks5.sh)
#   
# 2、卸载：
#   bash <(curl -Ls https://raw.githubusercontent.com/jyucoeng/socks5/refs/heads/main/socks5.sh) uninstall
#
# 3、命令行中如何测试socks5串通不通？？只要选下方的命令执行，成功返回ip就代表成功，不用在意是否返回的是什么ip，比如你明明是ipv6环境的服务器确返回了一个ipv4.这种情况其实也是对的。
#  curl --socks5-hostname "ipv4:端口号"  -U 用户名:密码 http://ip.sb
#  curl -6 --socks5-hostname "[ipv6]:端口号" -U 用户名:密码 http://ip.sb
#
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
blue(){ echo -e "\e[1;34m$1\033[0m"; }

gen_username() { tr -dc 'A-Za-z0-9' </dev/urandom | head -c 10; }
gen_password() { tr -dc 'A-Za-z0-9!@#%^_+' </dev/urandom | head -c 10; }
gen_port()     { shuf -i 20000-50000 -n 1; }

check_port_free() {
  ss -lnt 2>/dev/null | awk '{print $4}' | grep -q ":$1$"
  [[ $? -ne 0 ]]
}

########################
# 卸载
########################
uninstall() {
  echo "[INFO] 卸载 socks5..."

  if command -v systemctl >/dev/null 2>&1; then
    systemctl stop sing-box-socks5 2>/dev/null
    systemctl disable sing-box-socks5 2>/dev/null
    rm -f "$SERVICE_SYSTEMD"
    systemctl daemon-reload
  elif command -v rc-service >/dev/null 2>&1; then
    rc-service sing-box-socks5 stop 2>/dev/null
    rc-update del sing-box-socks5 default 2>/dev/null
    rm -f "$SERVICE_OPENRC"
  fi

  rm -rf "$INSTALL_DIR"
  green "✅ socks5 已卸载"
  exit 0
}

########################
# 参数处理（略，与你当前一致）
########################
# 👉 这里保持你现在已经验证通过的 handle_params()
# （为简洁省略，逻辑不变）

########################
# 启动服务（重点增强）
########################
start_service() {

  # -------- systemd --------
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
StandardOutput=append:$LOG_FILE
StandardError=append:$LOG_FILE

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable sing-box-socks5
    systemctl restart sing-box-socks5

    green "✅ 已通过 systemd 启动（支持重启自启）"
    return
  fi

  # -------- OpenRC（Alpine） --------
  if command -v rc-service >/dev/null 2>&1; then
    cat > "$SERVICE_OPENRC" <<EOF
#!/sbin/openrc-run

name="sing-box-socks5"
command="$BIN_FILE"
command_args="run -c $CONFIG_FILE"
command_background="yes"
pidfile="/run/sing-box-socks5.pid"
output_log="$LOG_FILE"
error_log="$LOG_FILE"

depend() {
  need net
}
EOF

    chmod +x "$SERVICE_OPENRC"
    rc-update add sing-box-socks5 default
    rc-service sing-box-socks5 restart

    green "✅ 已通过 OpenRC 启动（Alpine，支持重启自启）"
    return
  fi

  echo "❌ 未识别的 init 系统（systemd / OpenRC 均不存在）"
  exit 1
}

########################
# main
########################
main() {
  [[ "${1:-}" == "uninstall" ]] && uninstall

  handle_params
  install_deps
  install_singbox
  generate_config
  start_service

  IP_V4=$(curl -s4 ipv4.ip.sb 2>/dev/null)
  IP_V6=$(curl -s6 ipv6.ip.sb 2>/dev/null)

  echo
  green "✅ Socks5 服务已启动"
  [[ -n "$IP_V4" ]] && blue "IPv4: socks5://$USERNAME:$PASSWORD@$IP_V4:$PORT"
  [[ -n "$IP_V6" ]] && yellow "IPv6: socks5://$USERNAME:$PASSWORD@[$IP_V6]:$PORT"
   echo
  yellow "管理命令："
  green "查看状态:  systemctl status sing-box-socks5"
  green "重启服务:   systemctl restart sing-box-socks5"
  green "查看日志:   journalctl -u sing-box-socks5 -f"
}

main "$@"
