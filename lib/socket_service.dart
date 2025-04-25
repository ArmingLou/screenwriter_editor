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

  final checkDuaration = Duration(seconds: 30);
  final pingpongDuaration =
      Duration(seconds: 30); // 经调试，即使正常连接，ping - pong 时间差 iOS 可能都高达 20多秒

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

  // 客户端 ping 超时计时器
  // 同时用于判断是否有待处理的 ping（如果 _pingTimers[socket] 不为 null，则表示有待处理的 ping）
  final Map<WebSocket, Timer> _pingTimers = {};

  // 注意：我们不需要额外的集合来跟踪已处理的断开连接客户端
  // 可以直接通过检查 _clients 是否包含对应的 socket 来判断是否已经处理过

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

      // if (Platform.isIOS) {
        // 添加定期检查服务器状态
        _serverErrorSubscription = Stream.periodic(checkDuaration).listen(
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
      // }

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

      // 取消所有 ping 计时器
      for (var timer in _pingTimers.values) {
        timer.cancel();
      }

      // 清理所有集合
      _clients.clear();
      _clientIPs.clear();
      _authenticatedClients.clear();
      _pingTimers.clear();

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

      // 初始化时不需要设置 ping 状态，因为我们使用 _pingTimers 来判断是否有待处理的 ping

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
          // 清理客户端资源并触发断开连接事件
          disconnectClient(socket, reason: "连接关闭");
        },
        onError: (error, stackTrace) {
          // 清理客户端资源并触发断开连接事件
          disconnectClient(socket, reason: "连接错误");

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
        } else if (type == 'pong') {
          // 处理 pong 响应
          final int timestamp = data['timestamp'] ?? 0;
          final int roundTripTime =
              DateTime.now().millisecondsSinceEpoch - timestamp;

          // 取消该客户端的 ping 超时计时器
          _pingTimers[socket]?.cancel();
          _pingTimers.remove(socket);

          // 取消该客户端的 ping 超时计时器表示已响应 ping

          debugPrint(
              '收到客户端 pong 响应: ${_clientIPs[socket] ?? "未知IP"}, 往返时间: $roundTripTime ms');
        } else if (type == 'ping') {
          // 处理 ping 消息，立即回复 pong 消息
          final int timestamp = data['timestamp'] ?? 0;
          socket.add(jsonEncode({
            'type': 'pong',
            'timestamp': timestamp,
          }));
          debugPrint('收到客户端 ping 消息，已回复 pong 响应，时间戳: $timestamp');
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
    // 判断平台
    // if (!Platform.isIOS) {
    //   return;
    // }

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

  /// 强制检查服务器状态，特别用于从后台恢复时。 
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
      return;
    }

    // 检查已连接客户端是否由于各种原因断开连接，而服务端没有收到通知
    List<WebSocket> disconnectedSockets = [];

    // 首先收集所有断开连接的客户端，避免在遍历过程中修改集合
    // 注意：由于我们在 Timer 回调中会从 _clients 中移除已处理的客户端
    // 所以这里不需要额外的检查来避免重复处理
    for (var socket in _clients) {
      try {
        // 检查 WebSocket 的状态
        if (socket.readyState != WebSocket.open) {
          disconnectedSockets.add(socket);
          debugPrint(
              '检测到客户端断开连接: ${_clientIPs[socket] ?? "未知IP"}, 状态: ${socket.readyState}');

          // 取消该客户端的 ping 超时计时器
          _pingTimers[socket]?.cancel();
          _pingTimers.remove(socket);
        } else {
          // 如果客户端已经有一个待处理的 ping，不要发送新的 ping
          if (_pingTimers.containsKey(socket)) {
            debugPrint(
                '客户端 ${_clientIPs[socket] ?? "未知IP"} 有一个待处理的 ping，跳过发送新的 ping');
            continue;
          }

          // 尝试发送一个 ping 消息来检测连接是否仍然有效
          try {
            final timestamp = DateTime.now().millisecondsSinceEpoch;

            // 发送 ping 消息
            socket.add(jsonEncode({
              'type': 'ping',
              'timestamp': timestamp,
            }));

            // 设置计时器表示该客户端有一个待处理的 ping

            // 设置 3 秒超时计时器
            _pingTimers[socket]?.cancel(); // 取消之前的计时器（如果有）
            _pingTimers[socket] = Timer(pingpongDuaration, () async {
              // 如果 3 秒后客户端仍然存在，认为客户端已断开连接
              if (_clients.contains(socket)) {
                debugPrint(
                    '客户端 ${_clientIPs[socket] ?? "未知IP"} 未在 30 秒内响应 ping，认为已断开连接');

                // 由于这是在异步的 Timer 回调中，我们需要直接处理断开连接的客户端
                // 而不是添加到 disconnectedSockets 列表中

                // 清理客户端资源并触发断开连接事件
                await disconnectClient(socket, reason: "ping 超时");
              }
            });

            debugPrint(
                '向客户端 ${_clientIPs[socket] ?? "未知IP"} 发送 ping 消息，等待 pong 响应');
          } catch (pingError) {
            // 如果发送 ping 消息失败，认为客户端已断开连接
            disconnectedSockets.add(socket);
            debugPrint(
                '发送 ping 消息失败，客户端可能已断开连接: ${_clientIPs[socket] ?? "未知IP"}, 错误: $pingError');
          }
        }
      } catch (e) {
        // 如果访问 socket 属性时发生异常，认为客户端已断开连接
        disconnectedSockets.add(socket);
        debugPrint(
            '检测客户端状态时发生异常，客户端可能已断开连接: ${_clientIPs[socket] ?? "未知IP"}, 错误: $e');
      }
    }

    // 处理所有断开连接的客户端
    _handleDisconnectedClients(disconnectedSockets);
  }

  /// 清理客户端资源并触发断开连接事件
  /// 返回客户端的IP地址
  String? _cleanupClient(WebSocket socket,
      {bool notifyDisconnect = true, String? reason}) {
    if (!_clients.contains(socket)) {
      return null; // 客户端已经被处理过
    }

    // 获取客户端 IP
    final ip = _clientIPs[socket];

    // 从列表中移除
    _clients.remove(socket);
    _authenticatedClients.remove(socket);
    _clientIPs.remove(socket);

    // 清理 ping 状态
    _pingTimers[socket]?.cancel();
    _pingTimers.remove(socket);

    // 触发客户端断开连接事件
    if (notifyDisconnect) {
      _eventController.add(SocketEvent(
        type: SocketEventType.clientDisconnected,
        content: ip,
        socket: socket,
      ));
    }

    final logReason = reason != null ? "（$reason）" : "";
    debugPrint('客户端已从列表中移除$logReason: ${ip ?? "未知IP"}');

    return ip;
  }

  /// 处理断开连接的客户端
  void _handleDisconnectedClients(List<WebSocket> disconnectedSockets) async {
    if (disconnectedSockets.isEmpty) return;

    int count = 0;
    for (var socket in disconnectedSockets) {
      final suc = await disconnectClient(socket);
      if (suc) {
        count++;
      }
    }

    // 如果有客户端断开连接，记录日志
    if (count > 0) {
      debugPrint('共有 $count 个客户端被检测到断开连接并已移除');
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
  Future<bool> disconnectClient(WebSocket socket,
      {bool notifyDisconnect = true, String? reason}) async {
    try {
      if (_clients.contains(socket)) {
        await socket.close();
        final ip = _cleanupClient(socket,
            reason: reason, notifyDisconnect: notifyDisconnect);
        return ip != null;
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
