# 剧本编辑器测试

本目录包含剧本编辑器应用的测试文件。

## 远程同步功能测试

`socket_integration_test.dart` 文件包含了测试远程同步功能的测试用例，它模拟VSCode扩展连接到真实设备上运行的剧本编辑器应用。

### 运行测试前的准备

1. 在真实设备（Android或iOS）上安装并运行剧本编辑器应用
2. 在应用中点击同步图标，打开远程同步设置页面
3. 设置端口（默认为8080）并启动Socket服务
4. 如果需要，启用密码验证并设置访问密码
5. 记下设备的IP地址（在设置页面上显示）

### 运行测试

```bash
# 使用默认IP地址(192.168.1.100)和端口(8080)，无密码
flutter test test/socket_integration_test.dart

# 指定设备IP地址和端口
DEVICE_IP=192.168.1.123 DEVICE_PORT=8888 flutter test test/socket_integration_test.dart

# 指定设备IP地址、端口和密码
DEVICE_IP=192.168.1.123 DEVICE_PORT=8888 DEVICE_PASSWORD=secret flutter test test/socket_integration_test.dart
```

### 测试内容

测试包含三个测试用例，每个用例都支持密码验证：

1. **测试连接到真机并发送fetch请求**：
   - 连接到真机上的WebSocket服务
   - 如果需要，发送认证请求并验证
   - 发送fetch请求获取编辑器内容
   - 验证是否成功接收到内容

2. **测试向真机发送push请求**：
   - 连接到真机上的WebSocket服务
   - 如果需要，发送认证请求并验证
   - 发送push请求，推送测试剧本内容
   - 在真机上检查编辑器内容是否已更新

3. **测试先fetch再push的完整流程**：
   - 连接到真机上的WebSocket服务
   - 如果需要，发送认证请求并验证
   - 先发送fetch请求获取原始内容
   - 在原始内容的基础上添加注释
   - 发送push请求，将修改后的内容推送回去
   - 在真机上检查编辑器内容是否已更新

### 密码验证流程

当启用密码验证时，测试用例会执行以下流程：

1. 连接到WebSocket服务
2. 发送认证请求，包含密码
   ```json
   {
     "type": "auth",
     "password": "your_password"
   }
   ```
3. 等待认证响应
   ```json
   {
     "type": "auth_response",
     "success": true,
     "message": "认证成功"
   }
   ```
4. 认证成功后继续测试，失败则终止测试

### 注意事项

- 测试需要真机和PC在同一网络下
- 确保防火墙未阻止指定端口
- 如果启用了密码验证，请确保提供正确的密码
- 如果测试失败，请检查IP地址、端口和密码是否正确
- 测试过程中会在控制台输出详细信息，帮助诊断问题

## 其他测试

- `socket_service_test.dart`：Socket服务的单元测试
