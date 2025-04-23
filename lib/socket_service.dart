import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

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
}

/// Socket事件数据结构
class SocketEvent {
  final SocketEventType type;
  final String? content;
  final WebSocket socket;

  SocketEvent({
    required this.type,
    this.content,
    required this.socket,
  });
}

/// Socket服务类
class SocketService {
  // 单例模式
  static final SocketService _instance = SocketService._internal();
  factory SocketService() => _instance;
  SocketService._internal();

  // 服务器实例
  HttpServer? _server;

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
      _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
      currentPort = port;

      // 监听连接
      _server!.listen((HttpRequest request) {
        if (WebSocketTransformer.isUpgradeRequest(request)) {
          _handleWebSocketRequest(request);
        } else {
          _handleHttpRequest(request);
        }
      });

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
        onError: (error) {
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
  void sendContent(String content, WebSocket socket) {
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

  /// 释放资源
  void dispose() {
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
      // 使用已存在的客户端或创建一个虚拟的客户端
      WebSocket? dummySocket;
      if (_clients.isNotEmpty) {
        dummySocket = _clients.first;
      } else {
        // 如果没有客户端，不触发事件
        return result;
      }

      _eventController.add(SocketEvent(
        type: SocketEventType.blacklistChanged,
        content: ip,
        socket: dummySocket,
      ));
    }
    return result;
  }
}
