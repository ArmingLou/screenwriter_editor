import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'isolate_socket_service.dart';

/// 定义Socket服务的状态
enum SocketServiceStatus {
  stopped,
  starting,
  running,
  error,
}

/// 定义Socket服务的事件类型
enum SocketEventType {
  auth, // 认证
  fetch, // 获取编辑器内容
  push, // 推送内容到编辑器
  clientConnected, // 客户端连接
  clientDisconnected, // 客户端断开
  clientBanned, // 客户端被禁止
  blacklistChanged, // 黑名单变化
  serverError, // 服务器异常
}

/// Socket事件数据结构
class SocketEvent {
  final SocketEventType type;
  final String? content;
  final WebSocket? socket;

  SocketEvent({
    required this.type,
    this.content,
    this.socket,
  });
}

/// Socket服务类 - 使用 IsolateSocketServer 的适配器
class SocketService with WidgetsBindingObserver {
  // 单例模式
  static final SocketService _instance = SocketService._internal();
  factory SocketService() => _instance;

  SocketService._internal() {
    // 注册应用生命周期监听
    WidgetsBinding.instance.addObserver(this);

    // 初始化 IsolateSocketServer
    _isolateServer = IsolateSocketServer();

    // 监听 IsolateSocketServer 事件
    _isolateServer.events.listen(_handleIsolateServerEvent);
  }

  // IsolateSocketServer 实例
  late final IsolateSocketServer _isolateServer;

  // 状态映射
  final Map<IsolateSocketServerStatus, SocketServiceStatus> _statusMap = {
    IsolateSocketServerStatus.stopped: SocketServiceStatus.stopped,
    IsolateSocketServerStatus.starting: SocketServiceStatus.starting,
    IsolateSocketServerStatus.running: SocketServiceStatus.running,
    IsolateSocketServerStatus.error: SocketServiceStatus.error,
  };

  // 状态
  ValueNotifier<SocketServiceStatus> status =
      ValueNotifier<SocketServiceStatus>(SocketServiceStatus.stopped);

  // 错误信息
  String? errorMessage;

  // 临时黑名单（本次启动期间被禁止的客户端IP地址）
  final Set<String> _blacklistedIPs = {};

  // 已连接的客户端列表
  final List<Map<String, dynamic>> _connectedClients = [];

  // 事件流控制器
  final StreamController<SocketEvent> _eventController =
      StreamController<SocketEvent>.broadcast();

  // 事件流
  Stream<SocketEvent> get events => _eventController.stream;

  // 当前端口
  int? currentPort;

  // 访问密码
  String? _password;

  // 是否启用密码验证
  bool _passwordRequired = false;

  // 应用是否在前台
  bool _isAppInForeground = true;

  // 最后一次进入后台的时间
  DateTime? _lastBackgroundTime;

  /// 设置密码
  void setPassword(String? password) {
    _password = password;
    _passwordRequired = password != null && password.isNotEmpty;
  }

  /// 检查客户端是否已认证
  bool isClientAuthenticated(WebSocket socket) {
    // 在 Isolate 模式下，我们不直接访问 WebSocket 对象
    // 这个方法可能不再适用，但为了保持 API 兼容性，我们保留它
    return !_passwordRequired;
  }

  /// 启动Socket服务器
  /// [port] 服务器端口
  /// [password] 可选的访问密码，如果提供则启用密码验证
  Future<bool> startServer(int port, {String? password}) async {
    if (status.value == SocketServiceStatus.running) {
      return true;
    }

    // 设置密码
    setPassword(password);

    // 清理黑名单
    _blacklistedIPs.clear();

    // 更新状态
    status.value = SocketServiceStatus.starting;
    errorMessage = null;
    currentPort = port;

    // 启动 IsolateSocketServer
    final success = await _isolateServer.startServer(
      port: port,
      password: password,
      requirePassword: _passwordRequired,
    );

    if (!success) {
      errorMessage = _isolateServer.errorMessage;
      status.value = SocketServiceStatus.error;
    }

    return success;
  }

  /// 停止Socket服务器
  Future<void> stopServer() async {
    // 清空黑名单
    _blacklistedIPs.clear();

    // 清空已连接的客户端列表
    _connectedClients.clear();

    // 停止 IsolateSocketServer
    await _isolateServer.stopServer();

    // 更新状态
    status.value = SocketServiceStatus.stopped;
    currentPort = null;
  }

  /// 处理 IsolateSocketServer 事件
  void _handleIsolateServerEvent(IsolateSocketServerEvent event) {
    switch (event.type) {
      case IsolateSocketServerEventType.started:
        status.value = SocketServiceStatus.running;
        break;

      case IsolateSocketServerEventType.stopped:
        status.value = SocketServiceStatus.stopped;
        currentPort = null;
        break;

      case IsolateSocketServerEventType.error:
        errorMessage = event.errorMessage;
        status.value = SocketServiceStatus.error;

        // 发送服务器错误事件
        _eventController.add(SocketEvent(
          type: SocketEventType.serverError,
          content: errorMessage,
        ));

        // 记录错误日志，便于调试
        debugPrint('服务器错误: $errorMessage');
        break;

      case IsolateSocketServerEventType.clientConnected:
        // 添加到已连接客户端列表
        if (event.clientIP != null) {
          _connectedClients.add({
            'ip': event.clientIP!,
            'connectTime': DateTime.now().millisecondsSinceEpoch,
          });

          // 添加调试日志
          debugPrint('客户端已连接: ${event.clientIP}');
          debugPrint('当前已连接客户端数量: ${_connectedClients.length}');
        } else {
          debugPrint('警告: 收到客户端连接事件，但 clientIP 为空');
        }

        // 发送客户端连接事件
        _eventController.add(SocketEvent(
          type: SocketEventType.clientConnected,
          content: event.clientIP,
        ));
        break;

      case IsolateSocketServerEventType.clientDisconnected:
        // 从已连接客户端列表中移除
        if (event.clientIP != null) {
          _connectedClients.removeWhere((client) => client['ip'] == event.clientIP);
        }

        // 发送客户端断开连接事件
        _eventController.add(SocketEvent(
          type: SocketEventType.clientDisconnected,
          content: event.clientIP,
        ));
        break;

      case IsolateSocketServerEventType.fetch:
        // 发送获取内容事件
        // 注意：在 Isolate 模式下，我们不能直接传递 WebSocket 对象
        // 而是将客户端 IP 地址作为 content 传递
        if (event.clientIP != null) {
          debugPrint('收到获取内容请求: ${event.clientIP}');
          _eventController.add(SocketEvent(
            type: SocketEventType.fetch,
            content: event.clientIP,
          ));
        } else {
          debugPrint('警告: 收到获取内容请求，但 clientIP 为空');
        }
        break;

      case IsolateSocketServerEventType.push:
        // 发送推送内容事件
        _eventController.add(SocketEvent(
          type: SocketEventType.push,
          content: event.content,
        ));
        break;

      case IsolateSocketServerEventType.auth:
        // 处理认证事件
        // 在 Isolate 模式下，我们通过 event.content 和 event.clientIP 获取认证结果和客户端 IP
        final success = event.content == 'true' || event.content == 'success';
        final clientIP = event.clientIP ?? '未知客户端';

        // 发送认证事件
        _eventController.add(SocketEvent(
          type: SocketEventType.auth,
          content: '${success ? 'success' : 'failed'}:$clientIP',
        ));

        // 添加调试日志
        debugPrint('客户端认证${success ? '成功' : '失败'}: $clientIP');
        break;

      case IsolateSocketServerEventType.blacklistUpdated:
        // 处理黑名单更新事件
        try {
          final blacklist = jsonDecode(event.content ?? '[]') as List;

          // 更新本地黑名单
          _blacklistedIPs.clear();
          for (var ip in blacklist) {
            if (ip is String) {
              _blacklistedIPs.add(ip);
            }
          }

          // 发送黑名单变化事件
          _eventController.add(SocketEvent(
            type: SocketEventType.blacklistChanged,
            content: jsonEncode(_blacklistedIPs.toList()),
          ));

          debugPrint('黑名单已更新: $_blacklistedIPs');
        } catch (e) {
          debugPrint('解析黑名单更新事件失败: $e');
        }
        break;
    }
  }

  /// 发送编辑器内容到客户端 (通过 WebSocket 对象)
  void sendContent(String content, WebSocket? socket) {
    // 在 Isolate 模式下，我们不直接访问 WebSocket 对象
    // 而是通过客户端 IP 地址来标识客户端
    if (socket == null) {
      debugPrint('无法发送内容，socket 为 null');
      return;
    }

    // 获取客户端 IP 地址
    final clientIP = _getClientIP(socket);
    if (clientIP == null) {
      debugPrint('无法发送内容，无法获取客户端 IP 地址');
      return;
    }

    // 发送内容到客户端
    _isolateServer.sendContentToClient(clientIP, content);
  }

  /// 发送编辑器内容到客户端 (通过 IP 地址)
  void sendContentToClient(String clientIP, String content) {
    if (status.value != SocketServiceStatus.running) {
      debugPrint('无法发送内容，服务器未运行');
      return;
    }

    // 发送内容到客户端
    debugPrint('发送内容到客户端: $clientIP');
    _isolateServer.sendContentToClient(clientIP, content);
  }

  /// 广播消息到所有客户端
  void broadcast(String message) {
    _isolateServer.sendContentToAll(message);
  }

  /// 获取本地IP地址
  Future<List<String>> getLocalIpAddresses() async {
    List<String> addresses = [];

    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );

      for (var interface in interfaces) {
        for (var addr in interface.addresses) {
          addresses.add(addr.address);
        }
      }
    } catch (e) {
      debugPrint('Error getting IP addresses: $e');
    }

    return addresses;
  }

  /// 应用生命周期变化回调
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        // 应用恢复到前台
        _isAppInForeground = true;
        final now = DateTime.now();
        debugPrint('App resumed to foreground at ${now.toIso8601String()}');

        // 检查应用在后台运行的时间
        if (_lastBackgroundTime != null &&
            status.value == SocketServiceStatus.running) {
          final difference =
              now.difference(_lastBackgroundTime!).inMilliseconds;

          // 如果应用在后台运行时间超过限制，自动检查服务器状态
          debugPrint('App was in background for $difference ms');

          // 无论后台运行时间多长，都强制检查服务器状态
          // 因为 iOS 在后台可能会暂停定时器，导致服务器状态检测失效
          _forceCheckServerStatus();
        }
        break;

      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        // 应用进入后台
        _isAppInForeground = false;
        _lastBackgroundTime = DateTime.now();
        debugPrint('App went to background at ${_lastBackgroundTime!.toIso8601String()}');
        break;
    }
  }

  /// 模拟服务器异常停止，用于测试
  void simulateServerError(String errorMsg) {
    if (status.value != SocketServiceStatus.running) {
      debugPrint('服务器未运行，无法模拟异常停止');
      return;
    }

    debugPrint('模拟服务器异常停止: $errorMsg');

    // 设置错误信息
    errorMessage = errorMsg;

    // 更新状态
    status.value = SocketServiceStatus.error;

    // 发送服务器错误事件
    _eventController.add(SocketEvent(
      type: SocketEventType.serverError,
      content: errorMsg,
    ));
  }

  /// 强制检查服务器状态，特别用于从后台恢复时
  Future<void> _forceCheckServerStatus() async {
    // 如果服务器不在运行状态，不需要检查
    if (status.value != SocketServiceStatus.running) {
      return;
    }

    debugPrint('强制检查服务器状态...');

    // 获取当前端口
    final port = currentPort;
    if (port == null) {
      debugPrint('无法获取服务器端口，服务器可能已关闭');
      errorMessage = '无法获取服务器端口，服务器可能已关闭';
      status.value = SocketServiceStatus.error;

      // 发送服务器错误事件
      _eventController.add(SocketEvent(
        type: SocketEventType.serverError,
        content: errorMessage,
      ));
      return;
    }

    // 添加调试日志，确保错误事件被正确发送
    debugPrint('服务器端口: $port');

    // 尝试连接到服务器
    try {
      // 使用超短的超时时间，快速检测服务器是否响应
      final socket = await Socket.connect('127.0.0.1', port,
          timeout: const Duration(milliseconds: 200));
      await socket.close();
      debugPrint('成功连接到服务器，端口: $port');
      // 连接成功，服务器正常运行
      return;
    } catch (e) {
      // 无法连接到服务器
      debugPrint('无法连接到服务器: $e');

      // 尝试创建一个测试服务器，看看端口是否被占用
      try {
        // 使用 shared: true 参数，如果端口被占用但可以共享，则不会抛出异常
        final testServer = await HttpServer.bind(InternetAddress.anyIPv4, port, shared: true);
        await testServer.close();

        // 如果能够创建测试服务器，说明原来的服务器已经停止
        debugPrint('能够创建测试服务器，原服务器可能已停止');
        errorMessage = '服务器可能已意外停止';
        status.value = SocketServiceStatus.error;

        // 发送服务器错误事件
        _eventController.add(SocketEvent(
          type: SocketEventType.serverError,
          content: errorMessage,
        ));
      } catch (e2) {
        // 如果无法创建测试服务器，可能是端口被其他应用占用
        // 或者服务器仍在运行但无法连接
        debugPrint('无法创建测试服务器: $e2');

        // 尝试重新启动服务器
        debugPrint('尝试重新启动服务器...');
        await stopServer();
        final success = await startServer(port, password: _password);

        if (success) {
          debugPrint('服务器重新启动成功');
        } else {
          debugPrint('服务器重新启动失败');
        }
      }
    }
  }

  /// 获取客户端 IP 地址
  String? _getClientIP(WebSocket socket) {
    // 在 Isolate 模式下，我们不直接访问 WebSocket 对象
    // 这个方法可能不再适用，但为了保持 API 兼容性，我们保留它
    return null;
  }

  /// 断开客户端连接 (旧方法，保持兼容性)
  void disconnectClient(WebSocket socket, {String? reason}) {
    // 在 Isolate 模式下，我们不直接访问 WebSocket 对象
    // 这个方法可能不再适用，但为了保持 API 兼容性，我们保留它
    debugPrint('断开客户端连接: $reason');
  }

  /// 断开客户端连接 (通过IP地址)
  void disconnectClientByIP(String clientIP) {
    _isolateServer.disconnectClient(clientIP);
  }

  /// 禁止客户端 IP 地址
  void banClientIP(String ip) {
    if (!_blacklistedIPs.contains(ip)) {
      _blacklistedIPs.add(ip);

      // 通知 IsolateSocketServer 禁止该 IP 的连接
      _isolateServer.banClient(ip);

      // 发送黑名单变化事件
      _eventController.add(SocketEvent(
        type: SocketEventType.blacklistChanged,
        content: jsonEncode(_blacklistedIPs.toList()),
      ));

      // 发送客户端被禁止事件
      _eventController.add(SocketEvent(
        type: SocketEventType.clientBanned,
        content: ip,
      ));

      debugPrint('已将客户端 $ip 添加到黑名单');
    }
  }

  /// 解除客户端 IP 地址禁止
  void unbanClientIP(String ip) {
    if (_blacklistedIPs.contains(ip)) {
      _blacklistedIPs.remove(ip);

      // 通知 IsolateSocketServer 解除禁止该 IP 的连接
      _isolateServer.unbanClient(ip);

      // 发送黑名单变化事件
      _eventController.add(SocketEvent(
        type: SocketEventType.blacklistChanged,
        content: jsonEncode(_blacklistedIPs.toList()),
      ));

      debugPrint('已将客户端 $ip 从黑名单中移除');
    }
  }

  /// 获取黑名单列表
  List<String> getBlacklist() {
    return _blacklistedIPs.toList();
  }

  /// 获取已连接的客户端信息
  List<Map<String, dynamic>> getConnectedClients() {
    // 添加调试日志
    debugPrint('获取已连接的客户端列表: ${_connectedClients.length} 个客户端');
    for (var client in _connectedClients) {
      debugPrint('  客户端: ${client['ip']}');
    }

    // 返回维护的客户端列表的副本
    return List<Map<String, dynamic>>.from(_connectedClients);
  }

  /// 获取已禁止的客户端列表
  List<String> getBannedIPs() {
    return _blacklistedIPs.toList();
  }

  /// 获取客户端数量
  int get clientCount => _isolateServer.clientCount;

  /// 释放资源
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    stopServer();
    _eventController.close();
    _isolateServer.dispose();
  }
}
