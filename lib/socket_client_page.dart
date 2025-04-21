import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'socket_client.dart';

class SocketClientPage extends StatefulWidget {
  const SocketClientPage({super.key});

  @override
  State<SocketClientPage> createState() => _SocketClientPageState();
}

class _SocketClientPageState extends State<SocketClientPage> {
  final SocketClient _socketClient = SocketClient();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _hostController = TextEditingController();
  final TextEditingController _portController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  List<RemoteServerConfig> _savedServers = [];
  bool _isLoading = true;
  bool _isEditing = false;

  // 事件订阅
  StreamSubscription<SocketClientEvent>? _eventSubscription;

  @override
  void initState() {
    super.initState();
    _loadSavedServers();

    // 监听SocketClient事件
    _eventSubscription = _socketClient.events.listen((event) {
      if (event.type == SocketClientEventType.error) {
        // 当发生错误时，刷新UI
        if (mounted) {
          setState(() {});
          _showSnackBar(event.errorMessage ?? '发生错误', color: Colors.red);
        }
      } else if (event.type == SocketClientEventType.disconnected) {
        // 当断开连接时，刷新UI
        if (mounted) {
          setState(() {});
        }
      }
    });
  }

  Future<void> _loadSavedServers() async {
    setState(() {
      _isLoading = true;
    });

    _savedServers = await _socketClient.loadSavedServers();

    setState(() {
      _isLoading = false;
    });
  }

  // 获取当前设备的局域网IP地址，优先选择192开头的IP
  Future<String?> _getLocalIpAddress() async {
    try {
      // 获取所有网络接口
      final interfaces = await NetworkInterface.list(
        includeLoopback: false, // 不包含回环接口
        includeLinkLocal: false, // 不包含链路本地地址
        type: InternetAddressType.IPv4, // 只考虑IPv4地址
      );

      // 存储所有可用的IP地址，按优先级分类
      List<String> ip192Addresses = [];
      List<String> otherPrivateAddresses = [];
      List<String> allAddresses = [];

      // 首先尝试找到无线网络接口
      for (var interface in interfaces) {
        if (interface.name.toLowerCase().contains('wlan') ||
            interface.name.toLowerCase().contains('wifi') ||
            interface.name.toLowerCase().contains('wireless')) {
          for (var addr in interface.addresses) {
            allAddresses.add(addr.address);

            if (addr.address.startsWith('192.168.')) {
              ip192Addresses.add(addr.address);
            } else if (addr.address.startsWith('10.') ||
                addr.address.startsWith('172.')) {
              otherPrivateAddresses.add(addr.address);
            }
          }
        }
      }

      // 如果没有找到无线网络，尝试找到任何局域网接口
      if (ip192Addresses.isEmpty && otherPrivateAddresses.isEmpty) {
        for (var interface in interfaces) {
          for (var addr in interface.addresses) {
            allAddresses.add(addr.address);

            if (addr.address.startsWith('192.168.')) {
              ip192Addresses.add(addr.address);
            } else if (addr.address.startsWith('10.') ||
                addr.address.startsWith('172.')) {
              otherPrivateAddresses.add(addr.address);
            }
          }
        }
      }

      // 按优先级返回IP地址
      if (ip192Addresses.isNotEmpty) {
        // 优先返回192开头的IP地址
        return ip192Addresses.first;
      } else if (otherPrivateAddresses.isNotEmpty) {
        // 其次返回其他私有IP地址
        return otherPrivateAddresses.first;
      } else if (allAddresses.isNotEmpty) {
        // 最后返回任何可用的IP地址
        return allAddresses.first;
      }

      // 如果上面都没有找到，尝试返回第一个接口的地址
      if (interfaces.isNotEmpty && interfaces.first.addresses.isNotEmpty) {
        return interfaces.first.addresses.first.address;
      }
    } catch (e) {
      debugPrint('Error getting local IP address: $e');
    }

    return null; // 如果无法获取IP地址，返回null
  }

  void _showAddServerDialog({RemoteServerConfig? server}) {
    _isEditing = server != null;

    // 如果是编辑模式，填充现有数据
    if (_isEditing && server != null) {
      _nameController.text = server.name;
      _hostController.text = server.host;
      _portController.text = server.port.toString();
      _passwordController.text = server.password ?? '';
    } else {
      // 新建模式，清空输入框
      _nameController.clear();
      _hostController.clear(); // 先清空
      _portController.text = '8080'; // 默认端口
      _passwordController.clear();

      // 尝试获取当前局域网IP地址并自动填充
      // 使用Future.microtask确保在对话框显示后再获取IP地址
      Future.microtask(() async {
        final localIp = await _getLocalIpAddress();
        if (localIp != null && mounted) {
          setState(() {
            _hostController.text = localIp;
          });
        }
      });
    }

    // 显示对话框
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_isEditing ? '编辑服务器' : '添加新服务器'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: '名称',
                  hintText: '输入服务器名称',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _hostController,
                decoration: const InputDecoration(
                  labelText: 'IP地址',
                  hintText: '输入服务器IP地址',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _portController,
                decoration: const InputDecoration(
                  labelText: '端口',
                  hintText: '输入端口号',
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passwordController,
                decoration: const InputDecoration(
                  labelText: '密码 (可选)',
                  hintText: '如果需要密码验证，请输入',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              _saveServer();
              Navigator.of(context).pop();
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveServer() async {
    // 验证输入
    final name = _nameController.text.trim();
    final host = _hostController.text.trim();
    final portText = _portController.text.trim();
    final password = _passwordController.text.trim();

    if (name.isEmpty || host.isEmpty || portText.isEmpty) {
      _showSnackBar('请填写所有必填字段', color: Colors.red);
      return;
    }

    final port = int.tryParse(portText);
    if (port == null || port <= 0 || port > 65535) {
      _showSnackBar('请输入有效的端口号 (1-65535)', color: Colors.red);
      return;
    }

    // 创建服务器配置
    final config = RemoteServerConfig(
      name: name,
      host: host,
      port: port,
      password: password.isNotEmpty ? password : null,
    );

    // 保存配置
    final success = await _socketClient.saveServerConfig(config);

    if (success) {
      _showSnackBar('服务器配置已保存');
      _loadSavedServers(); // 重新加载列表
    } else {
      _showSnackBar('保存服务器配置失败', color: Colors.red);
    }
  }

  Future<void> _deleteServer(RemoteServerConfig server) async {
    // 确认删除
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除服务器'),
        content: Text('确定要删除服务器 "${server.name}" 吗？'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(false);
            },
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(true);
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final success = await _socketClient.deleteServerConfig(server);

      if (success) {
        _showSnackBar('服务器已删除');
        _loadSavedServers(); // 重新加载列表
      } else {
        _showSnackBar('删除服务器失败', color: Colors.red);
      }
    }
  }

  void _showSnackBar(String message, {Color color = Colors.green}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(message),
          backgroundColor: color,
          duration: const Duration(seconds: 1)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('远程同步客户端'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 连接状态
                    ValueListenableBuilder<SocketClientStatus>(
                      valueListenable: _socketClient.status,
                      builder: (context, status, child) {
                        Color statusColor;
                        String statusText;

                        switch (status) {
                          case SocketClientStatus.disconnected:
                            statusColor = Colors.grey;
                            statusText = '未连接';
                            break;
                          case SocketClientStatus.connecting:
                            statusColor = Colors.orange;
                            statusText = '连接中...';
                            break;
                          case SocketClientStatus.connected:
                            final server = _socketClient.currentServer;
                            statusColor = Colors.green;
                            statusText =
                                '已连接到 ${server?.name ?? '未知服务器'} (${server?.host}:${server?.port})';
                            break;
                          case SocketClientStatus.error:
                            statusColor = Colors.red;
                            statusText = '错误: ${_socketClient.errorMessage}';
                            break;
                        }

                        return Card(
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
                                    '状态: $statusText',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: statusColor,
                                    ),
                                  ),
                                ),
                                if (status == SocketClientStatus.connected)
                                  ElevatedButton(
                                    onPressed: () async {
                                      await _socketClient.disconnect();
                                      _showSnackBar('已断开连接');
                                      // 强制刷新UI，确保所有按钮状态更新
                                      setState(() {});
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.red,
                                      foregroundColor: Colors.white,
                                    ),
                                    child: const Text('断开连接'),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),

                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          '保存的远程服务器',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        ElevatedButton.icon(
                          onPressed: () {
                            _showAddServerDialog();
                          },
                          icon: const Icon(Icons.add),
                          label: const Text('添加远程服务器'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // 服务器列表
                    Expanded(
                      child: _savedServers.isEmpty
                          ? const Center(
                              child: Text('没有保存的远程服务器，点击"添加远程服务器"按钮添加'),
                            )
                          : ListView.builder(
                              itemCount: _savedServers.length,
                              itemBuilder: (context, index) {
                                final server = _savedServers[index];
                                final isConnected =
                                    _socketClient.status.value ==
                                            SocketClientStatus.connected &&
                                        _socketClient.currentServer?.host ==
                                            server.host &&
                                        _socketClient.currentServer?.port ==
                                            server.port;

                                // 检查是否有任何服务器处于连接中或已连接状态
                                // 注意：当连接失败时，状态会变为error，此时应该允许重新连接
                                final anyServerConnecting = _socketClient
                                            .status.value ==
                                        SocketClientStatus.connecting ||
                                    (_socketClient.status.value ==
                                            SocketClientStatus.connected &&
                                        _socketClient.currentServer != null);

                                return Card(
                                  color: isConnected
                                      ? Colors.green.withAlpha(25)
                                      : null,
                                  margin:
                                      const EdgeInsets.symmetric(vertical: 8),
                                  child: Padding(
                                    padding: const EdgeInsets.all(12.0),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        // 服务器信息部分
                                        Row(
                                          children: [
                                            Icon(
                                              Icons.computer,
                                              color: isConnected
                                                  ? Colors.green
                                                  : Colors.grey,
                                              size: 24,
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    server.name,
                                                    style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 16,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    '${server.host}:${server.port}${server.password != null ? ' (需要密码)' : ''}',
                                                    style: TextStyle(
                                                      color: Colors.grey[600],
                                                      fontSize: 14,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            // 状态标记
                                            if (isConnected)
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                        vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: Colors.green,
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                ),
                                                child: const Text(
                                                  '已连接',
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),

                                        const SizedBox(height: 16),

                                        // 操作按钮部分
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.end,
                                          children: [
                                            // 编辑按钮
                                            TextButton.icon(
                                              icon: const Icon(Icons.edit,
                                                  size: 18),
                                              label: const Text('编辑'),
                                              onPressed: () {
                                                _showAddServerDialog(
                                                    server: server);
                                              },
                                              style: TextButton.styleFrom(
                                                foregroundColor: Colors.blue,
                                              ),
                                            ),
                                            // 删除按钮
                                            TextButton.icon(
                                              icon: const Icon(Icons.delete,
                                                  size: 18),
                                              label: const Text('删除'),
                                              onPressed: () {
                                                _deleteServer(server);
                                              },
                                              style: TextButton.styleFrom(
                                                foregroundColor: Colors.red,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            // 连接按钮
                                            // 如果有其他服务器连接中或已连接，且当前服务器未连接，则添加提示
                                            Tooltip(
                                              message: (anyServerConnecting &&
                                                      !isConnected)
                                                  ? '已有服务器连接，请先断开当前连接'
                                                  : '',
                                              // 只在按钮禁用时显示提示
                                              triggerMode:
                                                  (anyServerConnecting &&
                                                          !isConnected)
                                                      ? TooltipTriggerMode.tap
                                                      : TooltipTriggerMode
                                                          .manual,
                                              child: ElevatedButton.icon(
                                                icon: Icon(
                                                  isConnected
                                                      ? Icons.link
                                                      : Icons.link_off,
                                                  size: 18,
                                                ),
                                                label: Text(
                                                    isConnected ? '断开' : '连接'),
                                                // 如果当前服务器已连接，则显示断开按钮
                                                // 如果有任何服务器处于连接中或已连接状态，且当前服务器未连接，则禁用按钮
                                                onPressed: isConnected
                                                    ? () async {
                                                        await _socketClient
                                                            .disconnect();
                                                        _showSnackBar('已断开连接');
                                                        // 强制刷新UI，确保所有按钮状态更新
                                                        setState(() {});
                                                      }
                                                    : (anyServerConnecting &&
                                                            !isConnected)
                                                        ? null // 如果有其他服务器连接中或已连接，则禁用按钮
                                                        : () async {
                                                            // 显示连接中的状态
                                                            setState(() {
                                                              // 状态已经在connect方法中设置为连接中
                                                            });

                                                            // 异步连接，不会阻塞UI
                                                            final success =
                                                                await _socketClient
                                                                    .connect(
                                                                        server);

                                                            if (success) {
                                                              // 连接成功，完成连接过程
                                                              await _socketClient
                                                                  .completeConnection();

                                                              if (mounted) {
                                                                _showSnackBar(
                                                                    '连接成功');
                                                                // 强制刷新UI，确保连接状态显示正确
                                                                setState(() {});
                                                              }
                                                            } else if (mounted) {
                                                              // 连接失败
                                                              _showSnackBar(
                                                                  '连接失败: ${_socketClient.errorMessage ?? "未知错误"}',
                                                                  color: Colors
                                                                      .red);

                                                              // 强制刷新UI，确保按钮状态更新
                                                              setState(() {});
                                                            }
                                                          },
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: isConnected
                                                      ? Colors.red
                                                      : Colors.blue,
                                                  foregroundColor: Colors.white,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),

                    const SizedBox(height: 16),
                    const Text(
                      '使用说明:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '1. 添加远程服务器配置\n'
                      '2. 连接到服务器\n'
                      '3. 连接成功后，返回编辑器界面\n'
                      '4. 使用推送/拉取功能同步内容',
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  @override
  void dispose() {
    // 取消事件订阅
    _eventSubscription?.cancel();

    _nameController.dispose();
    _hostController.dispose();
    _portController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}
