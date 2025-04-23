import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/widgets.dart';

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

/// Socket服务类
class SocketService with WidgetsBindingObserver {
  // 单例模式
  static final SocketService _instance = SocketService._internal();
  factory SocketService() => _instance;
  SocketService._internal() {
    // 注册应用生命周期监听
    WidgetsBinding.instance.addObserver(this);
  }

  // 服务器实例
  HttpServer? _server;

  // 服务器异常监听器
  StreamSubscription? _serverErrorSubscription;

  // 应用是否在前台
  bool _isAppInForeground = true;

  // 最后一次进入后台的时间
  DateTime? _lastBackgroundTime;

  // 状态
  ValueNotifier<SocketServiceStatus> status =
      ValueNotifier<SocketServiceStatus>(SocketServiceStatus.stopped);

  // 错误信息
  String? errorMessage;

  // 连接的客户端
  final List<WebSocket> _clients = [];

  // 已认证的客户端
  final Set<WebSocket> _authenticatedClients = {};

  // 临时黑名单（本次启动期间被禁止的客户端IP地址）
  final Set<String> _blacklistedIPs = {};

  // 客户端IP地址映射
  final Map<WebSocket, String> _clientIPs = {};

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

  /// 设置密码
  void setPassword(String? password) {
    _password = password;
    _passwordRequired = password != null && password.isNotEmpty;
  }

  /// 检查客户端是否已认证
  bool isClientAuthenticated(WebSocket socket) {
    return !_passwordRequired || _authenticatedClients.contains(socket);
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

    // 清理已认证客户端列表
    _authenticatedClients.clear();

    status.value = SocketServiceStatus.starting;
    errorMessage = null;

    try {
      // 创建HTTP服务器
      // 使用 shared=true 允许在同一个地址和端口组合上多次绑定
      _server =
          await HttpServer.bind(InternetAddress.anyIPv4, port, shared: true);
      currentPort = port;

      // 监听连接
      _server!.listen(
        (HttpRequest request) {
          if (WebSocketTransformer.isUpgradeRequest(request)) {
            _handleWebSocketRequest(request);
          } else {
            _handleHttpRequest(request);
          }
        },
        onError: (error, stackTrace) {
          // 将错误传递给错误处理函数
          _handleServerError(error);
        },
        onDone: () {
          // 服务器完成时调用关闭处理
          _handleServerClosed();
        },
      );

      // 添加定期检查服务器状态
      _serverErrorSubscription =
          Stream.periodic(const Duration(seconds: 5)).listen(
        (_) async {
          // 如果应用在前台，执行定期检查
          if (_isAppInForeground &&
              status.value == SocketServiceStatus.running) {
            // 使用强制检查方法
            await _forceCheckServerStatus();
          }
        },
        onError: (error, stackTrace) {
          // 定期检查流发生错误
          debugPrint('Periodic check error: $error');
          // 不需要处理，因为这只是定期检查的错误，不影响服务器本身
        },
      );

      status.value = SocketServiceStatus.running;
      return true;
    } catch (e) {
      errorMessage = e.toString();
      status.value = SocketServiceStatus.error;
      return false;
    }
  }

  /// 停止Socket服务器
  Future<void> stopServer() async {
    // 清空黑名单
    _blacklistedIPs.clear();

    // 取消服务器错误监听
    await _serverErrorSubscription?.cancel();
    _serverErrorSubscription = null;

    if (_server != null) {
      // 关闭所有客户端连接
      for (var client in _clients) {
        await client.close();
      }
      _clients.clear();
      _clientIPs.clear();
      _authenticatedClients.clear();

      // 关闭服务器
      await _server!.close();
      _server = null;
      currentPort = null;
    }

    status.value = SocketServiceStatus.stopped;
  }

  /// 处理WebSocket请求
  void _handleWebSocketRequest(HttpRequest request) async {
    try {
      // 获取客户端IP地址
      final clientIP = request.connectionInfo?.remoteAddress.address;

      // 检查是否在黑名单中
      if (clientIP != null && _blacklistedIPs.contains(clientIP)) {
        // 如果在黑名单中，关闭连接
        request.response.statusCode = 403; // Forbidden
        await request.response.close();
        return;
      }

      final socket = await WebSocketTransformer.upgrade(request);
      _clients.add(socket);

      // 存储客户端IP地址
      if (clientIP != null) {
        _clientIPs[socket] = clientIP;
      }

      // 触发客户端连接事件
      _eventController.add(SocketEvent(
        type: SocketEventType.clientConnected,
        content: clientIP,
        socket: socket,
      ));

      // 监听消息
      socket.listen(
        (dynamic message) {
          _handleMessage(message, socket);
        },
        onDone: () {
          final ip = _clientIPs[socket];
          _clients.remove(socket);
          _authenticatedClients.remove(socket);
          _clientIPs.remove(socket);

          // 触发客户端断开事件
          _eventController.add(SocketEvent(
            type: SocketEventType.clientDisconnected,
            content: ip,
            socket: socket,
          ));
        },
        onError: (error, stackTrace) {
          final ip = _clientIPs[socket];
          _clients.remove(socket);
          _authenticatedClients.remove(socket);
          _clientIPs.remove(socket);

          // 触发客户端断开事件
          _eventController.add(SocketEvent(
            type: SocketEventType.clientDisconnected,
            content: ip,
            socket: socket,
          ));

          // 记录错误
          debugPrint('WebSocket error: $error');
        },
      );
    } catch (e) {
      debugPrint('WebSocket upgrade error: $e');
    }
  }

  /// 处理HTTP请求（提供简单的状态页面）
  void _handleHttpRequest(HttpRequest request) {
    // 检查是否在黑名单中
    // 获取客户端IP地址
    final clientIP = request.connectionInfo?.remoteAddress.address;
    if (clientIP != null && _blacklistedIPs.contains(clientIP)) {
      // 如果在黑名单中，关闭连接
      request.response.statusCode = 403; // Forbidden
      request.response.close();
      return;
    }

    final port = currentPort;
    final clientCount = _clients.length;
    final address = request.connectionInfo?.remoteAddress.address;
    final passwordStatus = _passwordRequired ? '已启用密码验证' : '未启用密码验证';

    request.response.headers.contentType = ContentType.html;
    request.response.write('''
      <!DOCTYPE html>
      <html>
        <head>
          <title>Screenwriter Editor Socket Server</title>
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <style>
            body { font-family: Arial, sans-serif; margin: 20px; }
            h1 { color: #333; }
            .status { padding: 10px; background-color: #e8f5e9; border-radius: 5px; }
          </style>
        </head>
        <body>
          <h1>Screenwriter Editor Socket Server</h1>
          <div class="status">
            <p>服务器正在运行，端口: $port</p>
            <p>连接客户端数: $clientCount</p>
            <p>安全状态: $passwordStatus</p>
          </div>
          <p>请使用WebSocket客户端连接到: ws://$address:$port</p>
        </body>
      </html>
    ''');
    request.response.close();
  }

  /// 处理接收到的消息
  void _handleMessage(dynamic message, WebSocket socket) {
    if (message is String) {
      try {
        final Map<String, dynamic> data = jsonDecode(message);
        final String type = data['type'];

        // 处理认证请求
        if (type == 'auth') {
          final String password = data['password'] ?? '';
          final bool authenticated =
              !_passwordRequired || password == _password;

          if (authenticated) {
            _authenticatedClients.add(socket);
          }

          // 发送认证响应
          socket.add(jsonEncode({
            'type': 'auth_response',
            'success': authenticated,
            'message': authenticated ? '认证成功' : '密码错误',
          }));

          // 触发认证事件
          _eventController.add(SocketEvent(
            type: SocketEventType.auth,
            content: authenticated ? 'success' : 'failed',
            socket: socket,
          ));

          return;
        }

        // 如果需要密码验证但客户端未认证，拒绝请求
        if (_passwordRequired && !_authenticatedClients.contains(socket)) {
          socket.add(jsonEncode({
            'type': 'error',
            'message': '需要认证，请先发送auth请求',
          }));
          return;
        }

        // 处理其他请求
        if (type == 'fetch') {
          _eventController.add(SocketEvent(
            type: SocketEventType.fetch,
            socket: socket,
          ));
        } else if (type == 'push') {
          final String content = data['content'] ?? '';
          _eventController.add(SocketEvent(
            type: SocketEventType.push,
            content: content,
            socket: socket,
          ));
        }
      } catch (e) {
        // 使用日志而非直接打印
        debugPrint('Error parsing message: $e');
      }
    }
  }

  /// 发送编辑器内容到客户端
  void sendContent(String content, WebSocket? socket) {
    if (socket == null) {
      debugPrint('无法发送内容，socket 为 null');
      return;
    }

    final response = jsonEncode({
      'type': 'content',
      'content': content,
    });

    socket.add(response);
  }

  /// 广播消息到所有客户端
  void broadcast(String message) {
    for (var client in _clients) {
      client.add(message);
    }
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

  /// 处理服务器错误
  void _handleServerError(dynamic error) async {
    if (status.value == SocketServiceStatus.error &&
        status.value == SocketServiceStatus.stopped) {
      return;
    }
    debugPrint('Server error: $error');

    // 设置错误信息
    errorMessage = error.toString();

    // 如果有客户端连接，创建一个虚拟的WebSocket用于事件通知
    WebSocket? dummySocket;
    if (_clients.isNotEmpty) {
      dummySocket = _clients.first;
    }

    // 发送服务器错误事件，即使没有客户端也发送
    _eventController.add(SocketEvent(
      type: SocketEventType.serverError,
      content: errorMessage,
      socket: dummySocket,
    ));

    // 停止服务器
    await stopServer();

    // 更新状态
    status.value = SocketServiceStatus.error;
  }

  /// 处理服务器关闭
  void _handleServerClosed() {
    // 如果当前状态不是错误或已停止，则认为是异常关闭
    if (status.value != SocketServiceStatus.error &&
        status.value != SocketServiceStatus.stopped) {
      errorMessage = '服务器意外关闭';
      _handleServerError(errorMessage!);
    }
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
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
        // 应用进入后台
        _isAppInForeground = false;
        _lastBackgroundTime = DateTime.now();
        debugPrint(
            'App went to background at ${_lastBackgroundTime!.toIso8601String()}');
        break;
      case AppLifecycleState.detached:
        // 应用完全分离，可能被系统终止
        _isAppInForeground = false;
        debugPrint('App detached');
        break;
      default:
        break;
    }
  }

  /// 强制检查服务器状态，特别用于从后台恢复时
  Future<void> _forceCheckServerStatus() async {
    // 如果服务器实例为空，触发关闭事件
    if (_server == null) {
      _handleServerClosed();
      return;
    }

    // 获取当前端口
    int? port;
    try {
      port = _server!.port;
    } catch (e) {
      // 无法获取端口，服务器可能已关闭
      debugPrint('Cannot get server port: $e');
      _handleServerError('无法获取服务器端口，服务器可能已关闭');
      return;
    }

    // 尝试连接到服务器
    bool canConnect = false;
    try {
      // 使用超短的超时时间，快速检测服务器是否响应
      final socket = await Socket.connect('127.0.0.1', port,
          timeout: const Duration(milliseconds: 200));
      await socket.close();
      canConnect = true;
      debugPrint('Successfully connected to server on port $port');
    } catch (e) {
      // 无法连接到服务器，尝试创建一个新的服务器实例
      debugPrint('Cannot connect to server: $e');
    }

    // 如果无法连接，则认为服务器已停止
    if (!canConnect) {
      debugPrint('Cannot connect to server, considering it stopped');
      _handleServerError('服务器已停止监听，无法接受连接');
    }
  }

  /// 释放资源
  void dispose() {
    // 移除应用生命周期监听
    WidgetsBinding.instance.removeObserver(this);

    stopServer();
    _eventController.close();
  }

  /// 获取已连接的客户端信息
  List<Map<String, dynamic>> getConnectedClients() {
    List<Map<String, dynamic>> clientsInfo = [];

    for (var socket in _clients) {
      final ip = _clientIPs[socket] ?? '未知IP';
      final authenticated = _authenticatedClients.contains(socket);

      clientsInfo.add({
        'socket': socket,
        'ip': ip,
        'authenticated': authenticated,
      });
    }

    return clientsInfo;
  }

  /// 断开特定客户端连接
  Future<bool> disconnectClient(WebSocket socket) async {
    try {
      if (_clients.contains(socket)) {
        await socket.close();
        _clients.remove(socket);
        _authenticatedClients.remove(socket);
        _clientIPs.remove(socket);
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Error disconnecting client: $e');
      return false;
    }
  }

  /// 禁止客户端（断开连接并加入黑名单）
  Future<bool> banClient(WebSocket socket) async {
    try {
      final ip = _clientIPs[socket];
      if (ip != null) {
        await disconnectClient(socket);
        _blacklistedIPs.add(ip);

        // 触发客户端被禁止事件
        _eventController.add(SocketEvent(
          type: SocketEventType.clientBanned,
          content: ip,
          socket: socket,
        ));

        // 触发黑名单变化事件
        _eventController.add(SocketEvent(
          type: SocketEventType.blacklistChanged,
          content: null,
          socket: socket,
        ));

        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Error banning client: $e');
      return false;
    }
  }

  /// 获取已禁止的客户端列表
  List<String> getBannedIPs() {
    return _blacklistedIPs.toList();
  }

  /// 清空黑名单
  void clearBlacklist() {
    _blacklistedIPs.clear();
  }

  /// 从黑名单中移除指定IP地址
  bool removeFromBlacklist(String ip) {
    final result = _blacklistedIPs.remove(ip);
    if (result) {
      // 触发黑名单变化事件
      // 使用已存在的客户端或传递 null
      WebSocket? dummySocket = _clients.isNotEmpty ? _clients.first : null;

      _eventController.add(SocketEvent(
        type: SocketEventType.blacklistChanged,
        content: ip,
        socket: dummySocket,
      ));
    }
    return result;
  }
}
