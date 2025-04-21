import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'socket_service.dart';

class SocketSettingsPage extends StatefulWidget {
  const SocketSettingsPage({Key? key}) : super(key: key);

  @override
  State<SocketSettingsPage> createState() => _SocketSettingsPageState();
}

class _SocketSettingsPageState extends State<SocketSettingsPage> {
  final TextEditingController _portController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final SocketService _socketService = SocketService();
  List<String> _ipAddresses = [];
  bool _isLoading = true;
  bool _autoStart = false; // 是否在应用启动时自动启动服务器
  bool _passwordEnabled = false; // 是否启用密码验证

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    setState(() {
      _isLoading = true;
    });

    // 加载保存的端口和自动启动设置
    final prefs = await SharedPreferences.getInstance();
    final savedPort = prefs.getInt('socket_port') ?? 8080;
    _portController.text = savedPort.toString();

    // 加载自动启动设置
    _autoStart = prefs.getBool('socket_auto_start') ?? false;

    // 加载密码设置
    final savedPassword = prefs.getString('socket_password') ?? '';
    _passwordController.text = savedPassword;
    _passwordEnabled = savedPassword.isNotEmpty;

    // 获取本地IP地址
    _ipAddresses = await _socketService.getLocalIpAddresses();

    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _saveSettings() async {
    final port = int.tryParse(_portController.text);
    if (port == null || port <= 0 || port > 65535) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('请输入有效的端口号 (1-65535)'),
            duration: Duration(seconds: 1),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    // 保存端口、密码和自动启动设置
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('socket_port', port);
    await prefs.setBool('socket_auto_start', _autoStart);

    // 保存密码设置
    final password = _passwordEnabled ? _passwordController.text : '';
    await prefs.setString('socket_password', password);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('设置已保存'),
          duration: Duration(seconds: 1),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _toggleServer() async {
    final port = int.tryParse(_portController.text);
    if (port == null || port <= 0 || port > 65535) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('请输入有效的端口号 (1-65535)'),
            duration: Duration(seconds: 1),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    if (_socketService.status.value == SocketServiceStatus.running) {
      await _socketService.stopServer();
    } else {
      // 获取密码（如果启用）
      final password = _passwordEnabled ? _passwordController.text : null;

      // 启动服务器
      final success =
          await _socketService.startServer(port, password: password);

      if (!success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('启动服务器失败: ${_socketService.errorMessage}'),
            duration: Duration(seconds: 1),
            backgroundColor: Colors.red,
          ),
        );
      } else if (success) {
        // 保存端口设置
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('socket_port', port);

        // 保存密码设置
        final savedPassword = _passwordEnabled ? _passwordController.text : '';
        await prefs.setString('socket_password', savedPassword);

        // 如果启动成功且自动启动选项已开启，保存自动启动设置
        await prefs.setBool('socket_auto_start', _autoStart);
      }
    }

    // 强制刷新状态
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('远程同步服务端'),
      ),
      // 使用 resizeToAvoidBottomInset 确保键盘弹出时不会影响布局
      resizeToAvoidBottomInset: true,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                // 使用 SingleChildScrollView 添加垂直滚动功能
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // 使用 GestureDetector 来处理点击空白处隐藏键盘
                    return GestureDetector(
                      onTap: () => FocusScope.of(context).unfocus(),
                      child: Column(
                        children: [
                          Expanded(
                            child: SingleChildScrollView(
                              child: Column(
                                mainAxisSize: MainAxisSize.max,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // 服务器状态
                                  ValueListenableBuilder<SocketServiceStatus>(
                                    valueListenable: _socketService.status,
                                    builder: (context, status, child) {
                                      Color statusColor;
                                      String statusText;

                                      switch (status) {
                                        case SocketServiceStatus.stopped:
                                          statusColor = Colors.grey;
                                          statusText = '已停止';
                                          break;
                                        case SocketServiceStatus.starting:
                                          statusColor = Colors.orange;
                                          statusText = '启动中...';
                                          break;
                                        case SocketServiceStatus.running:
                                          statusColor = Colors.green;
                                          statusText =
                                              '运行中 (端口: ${_socketService.currentPort})';
                                          break;
                                        case SocketServiceStatus.error:
                                          statusColor = Colors.red;
                                          statusText =
                                              '错误: ${_socketService.errorMessage}';
                                          break;
                                      }

                                      return Card(
                                        // 使用颜色的透明度来创建背景色
                                        color: statusColor.withAlpha(25),
                                        child: Padding(
                                          padding: const EdgeInsets.all(16.0),
                                          child: Row(
                                            children: [
                                              Icon(Icons.circle,
                                                  color: statusColor, size: 16),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  '服务器状态: $statusText',
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    color: statusColor,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),

                                  const SizedBox(height: 24),
                                  const Text(
                                    '服务器设置',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 16),

                                  // 端口设置
                                  TextField(
                                    controller: _portController,
                                    decoration: const InputDecoration(
                                      labelText: '端口',
                                      hintText: '输入端口号 (例如: 8080)',
                                      border: OutlineInputBorder(),
                                    ),
                                    keyboardType: TextInputType.number,
                                    enabled: _socketService.status.value !=
                                        SocketServiceStatus.running,
                                  ),

                                  const SizedBox(height: 16),

                                  // 自动启动选项
                                  Card(
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 16.0, vertical: 8.0),
                                      child: Row(
                                        children: [
                                          const Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  '应用启动时自动启动服务器',
                                                  style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold),
                                                ),
                                                SizedBox(height: 4),
                                                Text(
                                                  '开启后，应用启动时将自动启动Socket服务器',
                                                  style: TextStyle(
                                                      fontSize: 12,
                                                      color: Colors.grey),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Switch(
                                            value: _autoStart,
                                            onChanged: (value) {
                                              setState(() {
                                                _autoStart = value;
                                              });
                                            },
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),

                                  const SizedBox(height: 16),

                                  // 密码验证选项
                                  Card(
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 16.0, vertical: 8.0),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              const Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      '启用密码验证',
                                                      style: TextStyle(
                                                          fontWeight:
                                                              FontWeight.bold),
                                                    ),
                                                    SizedBox(height: 4),
                                                    Text(
                                                      '开启后，客户端需要提供正确的密码才能连接',
                                                      style: TextStyle(
                                                          fontSize: 12,
                                                          color: Colors.grey),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              ValueListenableBuilder<
                                                  SocketServiceStatus>(
                                                valueListenable:
                                                    _socketService.status,
                                                builder:
                                                    (context, status, child) {
                                                  final isRunning = status ==
                                                      SocketServiceStatus
                                                          .running;
                                                  return Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      if (isRunning)
                                                        Tooltip(
                                                          message:
                                                              '服务运行时无法更改密码验证设置',
                                                          child: const Icon(
                                                            Icons.info_outline,
                                                            size: 16,
                                                            color:
                                                                Colors.orange,
                                                          ),
                                                        ),
                                                      const SizedBox(width: 8),
                                                      Switch(
                                                        value: _passwordEnabled,
                                                        onChanged: isRunning
                                                            ? null // 服务运行时禁用开关
                                                            : (value) {
                                                                setState(() {
                                                                  _passwordEnabled =
                                                                      value;
                                                                });
                                                              },
                                                      ),
                                                    ],
                                                  );
                                                },
                                              ),
                                            ],
                                          ),
                                          if (_passwordEnabled) ...[
                                            // 仅当启用密码验证时显示密码输入框
                                            const SizedBox(height: 16),
                                            TextField(
                                              controller: _passwordController,
                                              decoration: const InputDecoration(
                                                labelText: '访问密码',
                                                hintText: '输入访问密码',
                                                border: OutlineInputBorder(),
                                              ),
                                              // obscureText: true,  // 密码输入模式
                                              enabled: _socketService
                                                      .status.value !=
                                                  SocketServiceStatus.running,
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ),

                                  const SizedBox(height: 24),
                                  const Text(
                                    '连接信息',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 16),

                                  // IP地址列表
                                  Card(
                                    child: Padding(
                                      padding: const EdgeInsets.all(16.0),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            '可用IP地址:',
                                            style: TextStyle(
                                                fontWeight: FontWeight.bold),
                                          ),
                                          const SizedBox(height: 8),
                                          if (_ipAddresses.isEmpty)
                                            const Text('未找到IP地址')
                                          else
                                            Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: _ipAddresses.map((ip) {
                                                return Padding(
                                                  padding: const EdgeInsets
                                                      .symmetric(vertical: 4.0),
                                                  child: Row(
                                                    children: [
                                                      Text(ip),
                                                      const SizedBox(width: 8),
                                                      if (_socketService
                                                              .status.value ==
                                                          SocketServiceStatus
                                                              .running)
                                                        Text(
                                                          '(ws://$ip:${_socketService.currentPort})',
                                                          style: TextStyle(
                                                              color: Colors
                                                                  .blue[700]),
                                                        ),
                                                    ],
                                                  ),
                                                );
                                              }).toList(),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),

                                  const SizedBox(height: 16),
                                  const Text(
                                    '使用说明:',
                                    style:
                                        TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 8),
                                  const Text(
                                    '1. 设置端口并启动服务器\n'
                                    '2. 确保客户端和服务端在同一网络下\n'
                                    '3. 在客户端连接上面显示的WS地址\n'
                                    '4. 客户端使用推送/拉取功能同步内容',
                                  ),
                                  const SizedBox(height: 16),
                                ],
                              ),
                            ),
                          ),

                          const SizedBox(height: 16),
                          // 底部按钮
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              ElevatedButton(
                                onPressed: _saveSettings,
                                child: const Text('保存设置'),
                              ),
                              ValueListenableBuilder<SocketServiceStatus>(
                                valueListenable: _socketService.status,
                                builder: (context, status, child) {
                                  final isRunning =
                                      status == SocketServiceStatus.running;
                                  return ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor:
                                          isRunning ? Colors.red : Colors.green,
                                      foregroundColor: Colors.white,
                                    ),
                                    onPressed: _toggleServer,
                                    child: Text(isRunning ? '停止服务器' : '启动服务器'),
                                  );
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
    );
  }

  @override
  void dispose() {
    _portController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}
