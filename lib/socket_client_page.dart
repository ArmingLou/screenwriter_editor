import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'socket_client.dart';

/// IP冲突处理选项
enum IpConflictAction {
  replace, // 替换冲突的服务器
  cancel, // 取消操作
}

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
  bool _useFullScroll = false; // 是否使用整体滚动布局
  RemoteServerConfig? _originalServer; // 保存原始服务器配置，用于编辑模式

  // 创建焦点节点来管理输入框的焦点
  final FocusNode _nameFocusNode = FocusNode();
  final FocusNode _hostFocusNode = FocusNode();
  final FocusNode _portFocusNode = FocusNode();
  final FocusNode _passwordFocusNode = FocusNode();

  // 固定部分的高度估计
  final double _statusCardHeight = 80.0; // 状态卡片高度估计
  final double _bottomInfoHeight = 100.0; // 底部信息高度估计

  // 屏幕方向变化观察者
  _OrientationObserver? _observer;

  // 事件订阅
  StreamSubscription<SocketClientEvent>? _eventSubscription;

  // 判断布局模式
  void _determineLayoutMode() {
    if (!mounted) return; // 避免在组件卸载后调用

    // 获取屏幕高度（不受键盘弹出影响）
    final screenHeight = MediaQuery.of(context).size.height;

    // 计算可用高度，不考虑键盘高度
    // 因为我们已经设置了 resizeToAvoidBottomInset: true，允许布局自动调整以适应键盘
    final availableHeight =
        screenHeight - _statusCardHeight - _bottomInfoHeight - 32; // 32是上下间距

    // 判断是否需要整体滚动，使用固定阈值
    final needsFullScroll = availableHeight < 200;

    // 只有当布局模式变化时才触发重建
    if (needsFullScroll != _useFullScroll) {
      setState(() {
        _useFullScroll = needsFullScroll;
      });
    }
  }

  @override
  void initState() {
    super.initState();

    // 添加屏幕方向变化监听，只在屏幕方向变化时重新判断布局
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _determineLayoutMode();
    });

    // 添加屏幕方向变化监听
    _observer = _OrientationObserver(this);
    WidgetsBinding.instance.addObserver(_observer!);

    _loadSavedServers();

    // 监听SocketClient事件
    _eventSubscription = _socketClient.events.listen((event) {
      if (event.type == SocketClientEventType.error) {
        // 当发生错误时，刷新UI
        if (mounted) {
          setState(() {});
          // final errorMsg = event.errorMessage ?? '发生错误';
          // _showSnackBar(errorMsg, color: Colors.red);
        }
      } else if (event.type == SocketClientEventType.disconnected) {
        // 当断开连接时，刷新UI
        if (mounted) {
          setState(() {});
        }
      } else if (event.type == SocketClientEventType.connected) {
        // 当连接成功时，刷新UI
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

    // 加载服务器列表
    _savedServers = await _socketClient.loadSavedServers();

    // 对服务器列表进行排序，将默认服务器排在最前面
    _savedServers.sort((a, b) {
      if (a.isDefault && !b.isDefault) {
        return -1; // a是默认服务器，排在前面
      } else if (!a.isDefault && b.isDefault) {
        return 1; // b是默认服务器，排在前面
      } else {
        return 0; // 保持原有顺序
      }
    });

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

            if (addr.address.startsWith('192.')) {
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

            if (addr.address.startsWith('192.')) {
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

      // 保存原始服务器信息，用于在保存时检查是否为默认服务器
      _originalServer = server;
    } else {
      // 新建模式，清空输入框
      _nameController.clear();
      _hostController.clear(); // 先清空
      _portController.text = '8080'; // 默认端口
      _passwordController.clear();

      // 清除原始服务器信息
      _originalServer = null;

      // 尝试获取当前局域网IP地址并自动填充
      // 使用Future.microtask确保在对话框显示后再获取IP地址
      Future.microtask(() async {
        final localIp = await _getLocalIpAddress();
        if (localIp != null && mounted) {
          setState(() {
            _hostController.text =
                localIp.substring(0, localIp.lastIndexOf('.') + 1);
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
                focusNode: _nameFocusNode,
                decoration: const InputDecoration(
                  labelText: '名称 (可选)',
                  hintText: '输入服务器名称',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _hostController,
                focusNode: _hostFocusNode,
                decoration: const InputDecoration(
                  labelText: 'IP地址',
                  hintText: '输入服务器IP地址',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _portController,
                focusNode: _portFocusNode,
                decoration: const InputDecoration(
                  labelText: '端口',
                  hintText: '输入端口号',
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passwordController,
                focusNode: _passwordFocusNode,
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

    if (host.isEmpty || portText.isEmpty) {
      _showSnackBar('请填写所有必填字段', color: Colors.red);
      return;
    }

    final port = int.tryParse(portText);
    if (port == null || port <= 0 || port > 65535) {
      _showSnackBar('请输入有效的端口号 (1-65535)', color: Colors.red);
      return;
    }

    // 确定是否应该设置为默认服务器
    bool shouldBeDefault = false;

    // 如果是编辑模式，检查原服务器是否为默认服务器
    if (_isEditing && _originalServer != null) {
      shouldBeDefault = _originalServer!.isDefault;

      // 如果IP地址或端口发生了变化，需要删除旧的服务器配置
      if (_originalServer!.host != host || _originalServer!.port != port) {
        // 创建一个临时变量，用于删除旧的服务器配置
        final oldServer = _originalServer!;

        // 删除旧的服务器配置
        await _socketClient.deleteServerConfig(oldServer);
      }
    }

    // 创建服务器配置
    var config = RemoteServerConfig(
      name: name,
      host: host,
      port: port,
      password: password.isNotEmpty ? password : null,
      isDefault: shouldBeDefault, // 如果原来是默认服务器，保持默认状态
    );

    // 检查IP冲突
    final conflictServers = await _checkIpConflict(config);

    if (conflictServers.isNotEmpty) {
      // 检查冲突的服务器中是否有默认服务器
      bool hasDefaultInConflicts =
          conflictServers.any((server) => server.isDefault);

      // 如果有冲突，显示确认对话框
      final action = await _showIpConflictDialog(conflictServers, config);

      if (action == IpConflictAction.cancel) {
        // 用户选择取消操作
        return;
      } else if (action == IpConflictAction.replace) {
        // 如果冲突的服务器中有默认服务器，新服务器也应该是默认服务器
        if (hasDefaultInConflicts) {
          config = config.copyWith(isDefault: true);
        }

        // 用户选择替换，需要删除冲突的服务器
        await _socketClient.deleteServerConfigs(conflictServers);
      }
    }

    // 保存配置
    final success = await _socketClient.saveServerConfig(config);

    if (success) {
      _showSnackBar('服务器配置已保存');
      _loadSavedServers(); // 重新加载列表
    } else {
      _showSnackBar('保存服务器配置失败', color: Colors.red);
    }
  }

  /// 检查IP冲突
  ///
  /// 返回与给定配置IP地址相同的服务器列表
  Future<List<RemoteServerConfig>> _checkIpConflict(
      RemoteServerConfig config) async {
    // 加载所有保存的服务器
    final allServers = await _socketClient.loadSavedServers();

    // 查找IP相同的服务器（不考虑端口）
    final conflictServers = allServers.where((server) {
      // 如果是编辑模式，排除原始服务器
      if (_isEditing && _originalServer != null) {
        // 排除完全相同的服务器（IP和端口都相同）
        if (server.host == _originalServer!.host &&
            server.port == _originalServer!.port) {
          return false;
        }
        // 注意：如果IP或端口发生了变化，我们已经在_saveServer中删除了旧的服务器配置
      }

      // 检查IP是否相同
      return server.host == config.host;
    }).toList();

    return conflictServers;
  }

  /// 显示IP冲突确认对话框
  Future<IpConflictAction> _showIpConflictDialog(
      List<RemoteServerConfig> conflictServers,
      RemoteServerConfig newConfig) async {
    final result = await showDialog<IpConflictAction>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('IP地址冲突'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('IP地址 "${newConfig.host}" 已存在于以下服务器配置中:'),
              const SizedBox(height: 12),
              ...conflictServers.map((server) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                        '• ${server.name} (${server.host}:${server.port})'),
                  )),
              const SizedBox(height: 12),
              const Text('是否要替换这些配置？'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(IpConflictAction.cancel);
            },
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(IpConflictAction.replace);
            },
            style: TextButton.styleFrom(
              foregroundColor: Colors.red,
            ),
            child: const Text('替换'),
          ),
        ],
      ),
    );

    return result ?? IpConflictAction.cancel;
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

  // 状态卡片
  Widget _buildStatusCard() {
    return ValueListenableBuilder<SocketClientStatus>(
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
                Icon(Icons.circle, color: statusColor, size: 16),
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
                      // _showSnackBar('已断开连接');
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
    );
  }

  // 底部信息
  Widget _buildBottomInfo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '使用说明:',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text(
          '1. 添加远程服务器\n'
          '2. 返回编辑器界面，使用推送/拉取功能同步内容',
        ),
      ],
    );
  }

  // 主要内容
  Widget _buildMainContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              '远程服务器',
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
        _savedServers.isEmpty
            ? const Center(
                child: Text('没有远程服务器，点击"添加远程服务器"按钮添加'),
              )
            : ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _savedServers.length,
                itemBuilder: (context, index) {
                  final server = _savedServers[index];
                  final isConnected = _socketClient.status.value ==
                          SocketClientStatus.connected &&
                      _socketClient.currentServer?.host == server.host &&
                      _socketClient.currentServer?.port == server.port;

                  // 检查是否有任何服务器处于连接中或已连接状态
                  // 注意：当连接失败时，状态会变为error，此时应该允许重新连接
                  final anyServerConnecting = _socketClient.status.value ==
                          SocketClientStatus.connecting ||
                      (_socketClient.status.value ==
                              SocketClientStatus.connected &&
                          _socketClient.currentServer != null);

                  return Card(
                    color: isConnected ? Colors.green.withAlpha(25) : null,
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 服务器信息部分
                          Row(
                            children: [
                              Icon(
                                Icons.computer,
                                color: isConnected ? Colors.green : Colors.grey,
                                size: 24,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          server.name,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                          ),
                                        ),
                                        if (server.isDefault)
                                          Container(
                                            margin:
                                                const EdgeInsets.only(left: 8),
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Colors.blue,
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: const Text(
                                              '默认',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        if (!server.isDefault) const Spacer(),
                                        if (!server.isDefault)
                                          TextButton.icon(
                                            icon: const Icon(Icons.star_outline,
                                                size: 18),
                                            label: const Text('设为默认'),
                                            onPressed: () async {
                                              final success =
                                                  await _socketClient
                                                      .setDefaultServer(server);
                                              if (success) {
                                                _showSnackBar('已设置为默认服务器');
                                                _loadSavedServers(); // 重新加载列表
                                              } else {
                                                _showSnackBar('设置默认服务器失败',
                                                    color: Colors.red);
                                              }
                                            },
                                            style: TextButton.styleFrom(
                                              foregroundColor: Colors.orange,
                                              minimumSize:
                                                  Size(0, 20), // 设置最小高度
                                              padding: EdgeInsets.symmetric(
                                                  horizontal: 8,
                                                  vertical: 0), // 减小内边距
                                              tapTargetSize:
                                                  MaterialTapTargetSize
                                                      .shrinkWrap, // 减小点击区域
                                            ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${server.host}:${server.port}${server.password != null ? '  [${server.password}]' : '  [无密码]'}',
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
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.green,
                                    borderRadius: BorderRadius.circular(12),
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
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              // 编辑按钮
                              TextButton.icon(
                                icon: const Icon(Icons.edit, size: 18),
                                label: const Text('编辑'),
                                onPressed: () {
                                  _showAddServerDialog(server: server);
                                },
                                style: TextButton.styleFrom(
                                  foregroundColor: Colors.blue,
                                ),
                              ),
                              // 删除按钮
                              TextButton.icon(
                                icon: const Icon(Icons.delete, size: 18),
                                label: const Text('删除'),
                                onPressed: () {
                                  _deleteServer(server);
                                },
                                style: TextButton.styleFrom(
                                  foregroundColor: Colors.red,
                                ),
                              ),
                              const SizedBox(width: 8),

                              // 连接/断开连接按钮 (仅对默认服务器显示)
                              Tooltip(
                                message: (anyServerConnecting && !isConnected)
                                    ? '已有服务器连接，请先断开当前连接'
                                    : '',
                                // 只在按钮禁用时显示提示
                                triggerMode:
                                    (anyServerConnecting && !isConnected)
                                        ? TooltipTriggerMode.tap
                                        : TooltipTriggerMode.manual,
                                child: ElevatedButton.icon(
                                  icon: Icon(
                                    isConnected ? Icons.link : Icons.link_off,
                                    size: 18,
                                  ),
                                  label: Text(isConnected ? '断开' : '连接'),
                                  // 如果当前服务器已连接，则显示断开按钮
                                  // 如果有任何服务器处于连接中或已连接状态，且当前服务器未连接，则禁用按钮
                                  onPressed: isConnected
                                      ? () async {
                                          await _socketClient.disconnect();
                                          // _showSnackBar('已断开连接');
                                          // 强制刷新UI，确保所有按钮状态更新
                                          setState(() {});
                                        }
                                      : (anyServerConnecting && !isConnected)
                                          ? null // 如果有其他服务器连接中或已连接，则禁用按钮
                                          : () async {
                                              // 显示连接中的状态
                                              setState(() {
                                                // 状态已经在connect方法中设置为连接中
                                              });

                                              // 异步连接，不会阻塞UI
                                              // 使用带回调的通用连接方法
                                              await _socketClient
                                                  .connectComplete(
                                                server,
                                                onSuccess: () {
                                                  if (mounted) {
                                                    // 连接成功，刷新UI
                                                    setState(() {});
                                                  }
                                                },
                                                // onFailure: (error) {
                                                //   if (mounted) {
                                                //     _showSnackBar(
                                                //       '连接失败: $error',
                                                //       color: Colors.red,
                                                //     );
                                                //     setState(() {});
                                                //   }
                                                // },
                                              );
                                            },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor:
                                        isConnected ? Colors.red : Colors.blue,
                                    foregroundColor: Colors.white,
                                  ),
                                ),
                              ),
                              // 根据是否为默认服务器显示不同的按钮
                              // if (!server.isDefault)
                              //   // 设为默认按钮 (仅对非默认服务器显示)
                              //   ElevatedButton.icon(
                              //     icon:
                              //         const Icon(Icons.star_outline, size: 18),
                              //     label: const Text('设为默认'),
                              //     onPressed: () async {
                              //       final success = await _socketClient
                              //           .setDefaultServer(server);
                              //       if (success) {
                              //         _showSnackBar('已设置为默认服务器');
                              //         _loadSavedServers(); // 重新加载列表
                              //       } else {
                              //         _showSnackBar('设置默认服务器失败',
                              //             color: Colors.red);
                              //       }
                              //     },
                              //     style: ElevatedButton.styleFrom(
                              //       backgroundColor: Colors.orange,
                              //       foregroundColor: Colors.white,
                              //     ),
                              //   ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('远程同步 · 客户端'),
      ),
      // 设置 resizeToAvoidBottomInset 为 true，允许布局自动调整以适应键盘
      // 这样键盘弹出时底部按钮组会上升，中间可滚动部分会适应新的高度
      resizeToAvoidBottomInset: true,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                // 根据 _useFullScroll 变量决定布局方式
                child: _useFullScroll
                    // 当空间不足时，整个界面可滚动
                    ? SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildStatusCard(),
                            const SizedBox(height: 24),
                            _buildMainContent(),
                            const SizedBox(height: 24),
                            _buildBottomInfo(),
                          ],
                        ),
                      )
                    // 当空间足够时，只有中间内容可滚动
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 顶部状态卡片，固定在顶部
                          _buildStatusCard(),
                          const SizedBox(height: 16),
                          // 中间内容可滚动
                          Expanded(
                            child: SingleChildScrollView(
                              child: _buildMainContent(),
                            ),
                          ),
                          const SizedBox(height: 16),
                          // 底部信息，固定在底部
                          _buildBottomInfo(),
                        ],
                      ),
              ),
            ),
    );
  }

  @override
  void dispose() {
    // 移除屏幕方向变化监听
    if (_observer != null) {
      WidgetsBinding.instance.removeObserver(_observer!);
    }

    // 取消事件订阅
    _eventSubscription?.cancel();

    // 释放资源
    _nameController.dispose();
    _hostController.dispose();
    _portController.dispose();
    _passwordController.dispose();

    // 释放焦点节点
    _nameFocusNode.dispose();
    _hostFocusNode.dispose();
    _portFocusNode.dispose();
    _passwordFocusNode.dispose();

    super.dispose();
  }
}

// 屏幕尺寸变化观察者类
class _OrientationObserver extends WidgetsBindingObserver {
  final _SocketClientPageState state;

  _OrientationObserver(this.state);

  @override
  void didChangeMetrics() {
    // 屏幕尺寸变化时重新判断布局
    // 使用 addPostFrameCallback 确保在布局完成后调用
    WidgetsBinding.instance.addPostFrameCallback((_) {
      state._determineLayoutMode();
    });
  }
}
