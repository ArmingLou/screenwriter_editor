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
  auth,  // 认证
  fetch, // 获取编辑器内容
  push,  // 推送内容到编辑器
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
    if (_server != null) {
      // 关闭所有客户端连接
      for (var client in _clients) {
        await client.close();
      }
      _clients.clear();

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
      final socket = await WebSocketTransformer.upgrade(request);
      _clients.add(socket);

      // 监听消息
      socket.listen(
        (dynamic message) {
          _handleMessage(message, socket);
        },
        onDone: () {
          _clients.remove(socket);
          _authenticatedClients.remove(socket);
        },
        onError: (error) {
          _clients.remove(socket);
          _authenticatedClients.remove(socket);
        },
      );
    } catch (e) {
      debugPrint('WebSocket upgrade error: $e');
    }
  }

  /// 处理HTTP请求（提供简单的状态页面）
  void _handleHttpRequest(HttpRequest request) {
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
          final bool authenticated = !_passwordRequired || password == _password;

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
}
