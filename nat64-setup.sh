#!/bin/bash

set -e

# 设定参数
ROUTE_PREFIX="64:ff9b::/96"
GATEWAY="2001:67c:2960:6464::"
NETDEV="venet0"
SERVICE_FILE="/etc/systemd/system/nat64-route.service"
RESOLVED_CONF="/etc/systemd/resolved.conf"

function install_nat64() {
  echo "🔧 开始配置 NAT64..."

  echo "📄 写入 $RESOLVED_CONF..."
  cat > "$RESOLVED_CONF" <<EOF
[Resolve]
DNS=$GATEWAY
FallbackDNS=2001:4860:4860::64
EOF

  echo "📄 创建 $SERVICE_FILE..."
  cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Add NAT64 route
After=network.target

[Service]
Type=oneshot
ExecStart=/sbin/ip -6 route replace $ROUTE_PREFIX via $GATEWAY dev $NETDEV
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

  echo "🔄 重新加载 systemd..."
  systemctl daemon-reexec
  systemctl daemon-reload

  echo "📌 启用并启动 NAT64 服务..."
  systemctl enable nat64-route.service
  systemctl start nat64-route.service

  echo "✅ 当前 IPv6 路由表："
  ip -6 route show | grep "$ROUTE_PREFIX" || echo "⚠️ 未找到 NAT64 路由"

  echo -e "\n✅ NAT64 安装完成，可执行 reboot 验证是否持久化："
  echo "  reboot"
}

function uninstall_nat64() {
  echo "🧹 正在卸载 NAT64 配置..."

  echo "🧼 删除 NAT64 路由..."
  ip -6 route delete "$ROUTE_PREFIX" || true

  echo "🧼 停止并禁用服务..."
  systemctl disable --now nat64-route.service || true

  echo "🗑️ 删除服务文件..."
  rm -f "$SERVICE_FILE"

  echo "🔄 重新加载 systemd..."
  systemctl daemon-reexec
  systemctl daemon-reload

  echo "📄 当前 DNS 配置内容如下，请视需要手动修改："
  cat "$RESOLVED_CONF" || echo "(文件不存在)"

  echo -e "\n✅ 卸载完成，如需恢复默认 DNS，可手动编辑："
  echo "  nano $RESOLVED_CONF"
  echo "  systemctl restart systemd-resolved"
}

# 参数判断
if [[ "$1" == "uninstall" ]]; then
  uninstall_nat64
else
  install_nat64
fi