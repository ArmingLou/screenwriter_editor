#!/bin/bash

# 这个脚本用于运行远程同步功能测试
# 它会尝试自动检测本机IP地址，并使用该IP地址运行测试

# 获取本机IP地址（适用于大多数Unix/Linux/macOS系统）
get_local_ip() {
  if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    IP=$(ifconfig | grep "inet " | grep -v 127.0.0.1 | awk '{print $2}' | head -n 1)
  else
    # Linux
    IP=$(hostname -I | awk '{print $1}')
  fi
  echo $IP
}

# 默认端口
PORT=${1:-8080}

# 密码（可选）
PASSWORD=$2

# 获取本机IP
IP=$(get_local_ip)

if [ -z "$IP" ]; then
  echo "无法自动检测IP地址，使用默认IP: 192.168.1.100"
  IP="192.168.1.100"
fi

echo "====================================================="
echo "  剧本编辑器远程同步功能测试"
echo "====================================================="
echo "使用IP地址: $IP"
echo "使用端口: $PORT"

if [ -n "$PASSWORD" ]; then
  echo "使用密码: $PASSWORD"
  PASSWORD_PARAM="DEVICE_PASSWORD=$PASSWORD"
else
  echo "未使用密码"
  PASSWORD_PARAM=""
fi

echo ""
echo "请确保:"
echo "1. 真机应用已启动"
echo "2. 远程同步服务已在真机上启动"
echo "3. 如果启用了密码验证，请确保提供正确的密码"
echo "4. 真机和PC在同一网络下"
echo "====================================================="
echo ""

# 运行测试
DEVICE_IP=$IP DEVICE_PORT=$PORT $PASSWORD_PARAM flutter test test/socket_integration_test.dart
