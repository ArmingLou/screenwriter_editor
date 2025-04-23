import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// 定义Socket客户端的状态
enum SocketClientStatus {
  disconnected,
  connecting,
  connected,
  error,
}

/// 定义Socket客户端的事件类型
enum SocketClientEventType {
  connected,  // 连接成功
  disconnected, // 断开连接
  content,    // 接收到内容
  error,      // 发生错误
  auth,       // 认证相关
}

/// Socket客户端事件数据结构
class SocketClientEvent {
  final SocketClientEventType type;
  final String? content;
  final String? errorMessage;

  SocketClientEvent({
    required this.type,
    this.content,
    this.errorMessage,
  });
}

/// 远程服务器配置
class RemoteServerConfig {
  final String name;
  final String host;
  final int port;
  final String? password;

  RemoteServerConfig({
    required this.name,
    required this.host,
    required this.port,
    this.password,
  });

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'host': host,
      'port': port,
      'password': password,
    };
  }

  factory RemoteServerConfig.fromJson(Map<String, dynamic> json) {
    return RemoteServerConfig(
      name: json['name'] as String,
      host: json['host'] as String,
      port: json['port'] as int,
      password: json['password'] as String?,
    );
  }
}

/// Socket客户端类
class SocketClient {
  // 单例模式
  static final SocketClient _instance = SocketClient._internal();
  factory SocketClient() => _instance;
  SocketClient._internal();

  // WebSocket连接
  WebSocketChannel? _channel;

  // 状态
  ValueNotifier<SocketClientStatus> status =
      ValueNotifier<SocketClientStatus>(SocketClientStatus.disconnected);

  // 错误信息
  String? errorMessage;

  // 当前连接的服务器配置
  RemoteServerConfig? currentServer;

  // 事件流控制器
  final StreamController<SocketClientEvent> _eventController =
      StreamController<SocketClientEvent>.broadcast();

  // 事件流
  Stream<SocketClientEvent> get events => _eventController.stream;

  // 保存的服务器配置列表
  List<RemoteServerConfig> _savedServers = [];

  /// 加载保存的服务器配置
  Future<List<RemoteServerConfig>> loadSavedServers() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final serversJson = prefs.getStringList('socket_client_servers') ?? [];

      _savedServers = serversJson
          .map((json) => RemoteServerConfig.fromJson(jsonDecode(json)))
          .toList();

      return _savedServers;
    } catch (e) {
      debugPrint('Error loading saved servers: $e');
      return [];
    }
  }

  /// 保存服务器配置
  Future<bool> saveServerConfig(RemoteServerConfig config) async {
    try {
      // 加载现有配置
      await loadSavedServers();

      // 检查是否已存在相同配置
      final existingIndex = _savedServers.indexWhere(
        (server) => server.host == config.host && server.port == config.port,
      );

      if (existingIndex >= 0) {
        // 更新现有配置
        _savedServers[existingIndex] = config;
      } else {
        // 添加新配置
        _savedServers.add(config);
      }

      // 保存到SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final serversJson = _savedServers
          .map((server) => jsonEncode(server.toJson()))
          .toList();

      await prefs.setStringList('socket_client_servers', serversJson);
      return true;
    } catch (e) {
      debugPrint('Error saving server config: $e');
      return false;
    }
  }

  /// 删除服务器配置
  Future<bool> deleteServerConfig(RemoteServerConfig config) async {
    try {
      // 加载现有配置
      await loadSavedServers();

      // 移除匹配的配置
      _savedServers.removeWhere(
        (server) => server.host == config.host && server.port == config.port,
      );

      // 保存到SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final serversJson = _savedServers
          .map((server) => jsonEncode(server.toJson()))
          .toList();

      await prefs.setStringList('socket_client_servers', serversJson);
      return true;
    } catch (e) {
      debugPrint('Error deleting server config: $e');
      return false;
    }
  }

  /// 连接到远程服务器
  /// 返回一个Future，表示连接是否已启动（不一定表示连接成功）
  Future<bool> connect(RemoteServerConfig server) async {
    if (status.value == SocketClientStatus.connected) {
      await disconnect();
    }

    // 立即更新状态为连接中，这样UI可以立即响应
    status.value = SocketClientStatus.connecting;
    errorMessage = null;
    currentServer = server;

    // 使用计算隔离执行连接操作，避免阻塞UI线程
    return compute<Map<String, dynamic>, bool>(_connectInIsolate, {
      'host': server.host,
      'port': server.port,
      'password': server.password,
    }).then((success) {
      return success;
    }).catchError((e) {
      // 使用_handleError方法处理错误，避免重复触发错误事件
      _handleError(e.toString());
      return false;
    });
  }

  /// 在隔离中执行连接操作
  static Future<bool> _connectInIsolate(Map<String, dynamic> params) async {
    try {
      final host = params['host'] as String;
      final port = params['port'] as int;
      // password在主线程中使用，这里只检查连接性

      // 构建WebSocket URL
      final wsUrl = 'ws://$host:$port';

      // 尝试连接，但不实际建立连接，只是检查是否可达
      // 实际连接将在主线程中创建
      final uri = Uri.parse(wsUrl);
      final socket = await Socket.connect(uri.host, uri.port, timeout: const Duration(seconds: 5));
      await socket.close();

      return true;
    } catch (e) {
      return Future.error(e);
    }
  }

  /// 完成连接过程（在主线程中调用）
  Future<bool> completeConnection() async {
    if (status.value != SocketClientStatus.connecting || currentServer == null) {
      return false;
    }

    try {
      final server = currentServer!;
      final wsUrl = 'ws://${server.host}:${server.port}';

      // 创建WebSocket连接
      // 使用 HttpClient 先检查是否被禁止（403）
      final httpClient = HttpClient();
      httpClient.connectionTimeout = const Duration(seconds: 5);

      try {
        // 先发送 HTTP 请求检查服务器状态
        final request = await httpClient.getUrl(Uri.parse('http://${server.host}:${server.port}'));
        final response = await request.close();

        // 如果返回 403，表示客户端被禁止
        if (response.statusCode == 403) {
          throw Exception('连接被服务器拒绝：您的 IP 地址已被禁止');
        }

        // 关闭响应流
        await response.drain<void>();
      } catch (e) {
        // 如果是 403 错误，直接抛出
        if (e.toString().contains('403')) {
          throw Exception('连接被服务器拒绝：您的 IP 地址已被禁止');
        }
        // 其他 HTTP 错误可以忽略，因为服务器可能不支持 HTTP 请求
        // 继续尝试 WebSocket 连接
      } finally {
        httpClient.close();
      }

      // 创建WebSocket连接
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));

      // 等待一下，确保连接已经完全建立
      // 这里增加超时检测，避免连接卡住
      bool connectionEstablished = false;
      final connectionFuture = _channel!.ready.timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          throw TimeoutException('WebSocket 连接超时');
        },
      ).then((_) {
        connectionEstablished = true;
      });

      // 监听消息
      _channel!.stream.listen(
        (dynamic message) {
          _handleMessage(message);
        },
        onDone: () {
          // 如果连接还没建立就断开，可能是被服务器拒绝
          if (!connectionEstablished) {
            // 如果当前状态不是错误，才触发错误事件
            // 这样可以避免重复触发错误事件
            if (status.value != SocketClientStatus.error) {
              _handleError('连接被服务器关闭，可能是您的 IP 地址已被禁止');
            } else {
              // 如果已经处于错误状态，只更新状态而不触发新的错误事件
              errorMessage = '连接被服务器关闭，可能是您的 IP 地址已被禁止';
  ;
              _channel = null;
              currentServer = null;
            }
          } else {
            _handleDisconnect();
          }
        },
        onError: (error) {
          // 如果当前状态不是错误，才触发错误事件
          if (status.value != SocketClientStatus.error) {
            _handleError(error.toString());
          }
        },
      );

      // 等待连接建立
      await connectionFuture;

      // 更新状态为已连接，这样认证请求才能发送
      status.value = SocketClientStatus.connected;

      // 如果有密码，发送密码；如果没有，发送空密码
      if (server.password != null && server.password!.isNotEmpty) {
        _sendAuthRequest(server.password!);
      } else {
        _sendAuthRequest('');
      }

      // 发送连接成功事件
      _eventController.add(SocketClientEvent(
        type: SocketClientEventType.connected,
      ));

      return true;
    } catch (e) {
      // 使用_handleError方法处理错误，避免重复触发错误事件
      _handleError(e.toString());
      return false;
    }
  }

  /// 断开连接
  Future<void> disconnect() async {
    if (_channel != null) {
      await _channel!.sink.close();
      _channel = null;
    }

    status.value = SocketClientStatus.disconnected;
    currentServer = null;

    _eventController.add(SocketClientEvent(
      type: SocketClientEventType.disconnected,
    ));
  }

  /// 发送认证请求
  void _sendAuthRequest(String password) {
    debugPrint('准备发送认证请求: 密码="$password", 密码长度=${password.length}');

    if (_channel == null) {
      debugPrint('无法发送认证请求: WebSocket通道为空');
      return;
    }

    if (status.value != SocketClientStatus.connected) {
      debugPrint('无法发送认证请求: 当前状态不是已连接 (${status.value})');
      return;
    }

    final authRequest = jsonEncode({
      'type': 'auth',
      'password': password,
    });

    debugPrint('发送认证请求: $authRequest');
    _channel!.sink.add(authRequest);
    debugPrint('认证请求已发送');
  }

  /// 发送获取内容请求
  void fetchContent() {
    if (_channel == null || status.value != SocketClientStatus.connected) {
      return;
    }

    final fetchRequest = jsonEncode({
      'type': 'fetch',
    });

    _channel!.sink.add(fetchRequest);
  }

  /// 发送推送内容请求
  void pushContent(String content) {
    if (_channel == null || status.value != SocketClientStatus.connected) {
      return;
    }

    final pushRequest = jsonEncode({
      'type': 'push',
      'content': content,
    });

    _channel!.sink.add(pushRequest);
  }

  /// 处理接收到的消息
  void _handleMessage(dynamic message) {
    if (message is String) {
      try {
        final Map<String, dynamic> data = jsonDecode(message);
        final String type = data['type'];

        if (type == 'auth_response') {
          debugPrint('收到认证响应: $data');
          final bool success = data['success'] ?? false;
          if (success) {
            debugPrint('认证成功');
            _eventController.add(SocketClientEvent(
              type: SocketClientEventType.auth,
              content: 'success',
            ));
          } else {
            final message = data['message'] ?? '未知原因';
            debugPrint('认证失败: $message');
            _handleError('认证失败: $message');
            // 认证失败时主动断开连接
            debugPrint('认证失败，主动断开连接');
            disconnect();
          }
        } else if (type == 'content') {
          final String content = data['content'] ?? '';
          _eventController.add(SocketClientEvent(
            type: SocketClientEventType.content,
            content: content,
          ));
        } else if (type == 'error') {
          _handleError(data['message'] ?? '未知错误');
        }
      } catch (e) {
        debugPrint('Error parsing message: $e');
      }
    }
  }

  /// 处理断开连接
  void _handleDisconnect() {
    // 如果当前状态是错误，不要覆盖错误状态
    if (status.value != SocketClientStatus.error) {
      status.value = SocketClientStatus.disconnected;
    }

    _channel = null;
    currentServer = null;

    _eventController.add(SocketClientEvent(
      type: SocketClientEventType.disconnected,
    ));
  }

  /// 处理错误
  void _handleError(String error) {
    // 如果错误消息相同，不重复触发错误事件
    if (errorMessage == error) {
      return;
    }

    errorMessage = error;
    status.value = SocketClientStatus.error;

    _eventController.add(SocketClientEvent(
      type: SocketClientEventType.error,
      errorMessage: error,
    ));
  }

  /// 释放资源
  void dispose() {
    disconnect();
    _eventController.close();
  }
}
