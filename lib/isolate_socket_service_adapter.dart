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
        break;

      case IsolateSocketServerEventType.clientConnected:
        // 发送客户端连接事件
        _eventController.add(SocketEvent(
          type: SocketEventType.clientConnected,
          content: event.clientIP,
        ));
        break;

      case IsolateSocketServerEventType.clientDisconnected:
        // 发送客户端断开连接事件
        _eventController.add(SocketEvent(
          type: SocketEventType.clientDisconnected,
          content: event.clientIP,
        ));
        break;

      case IsolateSocketServerEventType.fetch:
        // 发送获取内容事件
        _eventController.add(SocketEvent(
          type: SocketEventType.fetch,
          content: event.clientIP,
        ));
        break;

      case IsolateSocketServerEventType.push:
        // 发送推送内容事件
        _eventController.add(SocketEvent(
          type: SocketEventType.push,
          content: event.content,
        ));
        break;

      // 注意：IsolateSocketServerEventType 中没有 auth 类型
      // 如果需要处理认证事件，可以在这里添加相应的代码
      // 暂时不处理认证事件
      /*
      case IsolateSocketServerEventType.auth:
        // 发送认证事件
        _eventController.add(SocketEvent(
          type: SocketEventType.auth,
          content: event.content,
        ));
        break;
      */
    }
  }

  /// 发送编辑器内容到客户端
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

  /// 获取客户端 IP 地址
  String? _getClientIP(WebSocket socket) {
    // 在 Isolate 模式下，我们不直接访问 WebSocket 对象
    // 这个方法可能不再适用，但为了保持 API 兼容性，我们保留它
    return null;
  }

  /// 断开客户端连接
  void disconnectClient(WebSocket socket, {String? reason}) {
    // 在 Isolate 模式下，我们不直接访问 WebSocket 对象
    // 这个方法可能不再适用，但为了保持 API 兼容性，我们保留它
    debugPrint('断开客户端连接: $reason');
  }

  /// 禁止客户端 IP 地址
  void banClientIP(String ip) {
    if (!_blacklistedIPs.contains(ip)) {
      _blacklistedIPs.add(ip);

      // 通知 IsolateSocketServer 断开该 IP 的连接
      _isolateServer.disconnectClient(ip);

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
    }
  }

  /// 解除客户端 IP 地址禁止
  void unbanClientIP(String ip) {
    if (_blacklistedIPs.contains(ip)) {
      _blacklistedIPs.remove(ip);

      // 发送黑名单变化事件
      _eventController.add(SocketEvent(
        type: SocketEventType.blacklistChanged,
        content: jsonEncode(_blacklistedIPs.toList()),
      ));
    }
  }

  /// 获取黑名单列表
  List<String> getBlacklist() {
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
