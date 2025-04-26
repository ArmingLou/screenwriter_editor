import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';
import 'auth_utils.dart';

/// 定义Socket客户端的状态
enum SocketClientStatus {
  disconnected,
  connecting,
  connected,
  error,
}

/// 定义Socket客户端的事件类型
enum SocketClientEventType {
  connected, // 连接成功
  disconnected, // 断开连接
  content, // 接收到内容
  error, // 发生错误
  auth, // 认证相关
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
  final bool isDefault;

  RemoteServerConfig({
    required this.name,
    required this.host,
    required this.port,
    this.password,
    this.isDefault = false,
  });

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'host': host,
      'port': port,
      'password': password,
      'isDefault': isDefault,
    };
  }

  factory RemoteServerConfig.fromJson(Map<String, dynamic> json) {
    return RemoteServerConfig(
      name: json['name'] as String,
      host: json['host'] as String,
      port: json['port'] as int,
      password: json['password'] as String?,
      isDefault: json['isDefault'] as bool? ?? false,
    );
  }

  // 创建一个新的配置实例，可以修改某些属性
  RemoteServerConfig copyWith({
    String? name,
    String? host,
    int? port,
    String? password,
    bool? isDefault,
  }) {
    return RemoteServerConfig(
      name: name ?? this.name,
      host: host ?? this.host,
      port: port ?? this.port,
      password: password ?? this.password,
      isDefault: isDefault ?? this.isDefault,
    );
  }
}

/// Socket客户端类
class SocketClient with WidgetsBindingObserver {
  // 单例模式
  static final SocketClient _instance = SocketClient._internal();
  factory SocketClient() => _instance;
  SocketClient._internal() {
    // 注册应用生命周期监听
    WidgetsBinding.instance.addObserver(this);
  }

  // WebSocket连接
  WebSocketChannel? _channel;

// 应用是否在前台
  bool _isAppInForeground = true;

  // 最后一次进入后台的时间
  DateTime? _lastBackgroundTime;
  StreamSubscription? _clientErrorSubscription;
  final checkDuaration = Duration(seconds: 30);
  final pingpongDuaration = Duration(seconds: 30);
  // bool pendingPing = false;
  // 同时用于判断是否有待处理的 ping（如果 _pingTimers[socket] 不为 null，则表示有待处理的 ping）
  Timer? _pingTimers;

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

  // 认证完成的 Completer
  Completer<bool>? _authCompleter;

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

      // 检查是否只有一个服务器，如果是，则自动将其设置为默认服务器
      if (_savedServers.length == 1 && !_savedServers[0].isDefault) {
        // 创建一个新的配置，将isDefault设为true
        final newConfig = _savedServers[0].copyWith(isDefault: true);

        // 更新服务器列表
        _savedServers[0] = newConfig;

        // 保存到SharedPreferences
        final updatedServersJson =
            _savedServers.map((server) => jsonEncode(server.toJson())).toList();
        await prefs.setStringList('socket_client_servers', updatedServersJson);
      }

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

      // 检查是否是第一个服务器，如果是，则自动将其设置为默认服务器
      bool isFirstServer = _savedServers.isEmpty;

      // 如果是第一个服务器或新配置被设置为默认，则清除其他配置的默认标记
      if (config.isDefault || isFirstServer) {
        // 如果是第一个服务器但未设置为默认，则将其设置为默认
        if (isFirstServer && !config.isDefault) {
          config = config.copyWith(isDefault: true);
        }

        // 清除其他配置的默认标记
        for (int i = 0; i < _savedServers.length; i++) {
          if (_savedServers[i].isDefault) {
            _savedServers[i] = _savedServers[i].copyWith(isDefault: false);
          }
        }
      }

      // 检查是否已存在相同IP和端口的配置
      final exactMatchIndex = _savedServers.indexWhere(
        (server) => server.host == config.host && server.port == config.port,
      );

      // 如果找到完全匹配的配置，直接更新
      if (exactMatchIndex >= 0) {
        _savedServers[exactMatchIndex] = config;
      } else {
        // 添加新配置
        _savedServers.add(config);
      }

      // 如果添加/更新后只有一个服务器，确保它是默认服务器
      if (_savedServers.length == 1 && !_savedServers[0].isDefault) {
        _savedServers[0] = _savedServers[0].copyWith(isDefault: true);
      }

      // 保存到SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final serversJson =
          _savedServers.map((server) => jsonEncode(server.toJson())).toList();

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

      // 检查是否删除的是默认服务器
      bool wasDefault = false;
      for (var server in _savedServers) {
        if (server.host == config.host && server.port == config.port && server.isDefault) {
          wasDefault = true;
          break;
        }
      }

      // 移除匹配的配置
      _savedServers.removeWhere(
        (server) => server.host == config.host && server.port == config.port,
      );

      // 如果删除的是默认服务器，且还有其他服务器，则将第一个服务器设为默认
      if (wasDefault && _savedServers.isNotEmpty) {
        _savedServers[0] = _savedServers[0].copyWith(isDefault: true);
      }

      // 如果删除后只剩一个服务器，则自动将其设置为默认服务器
      if (_savedServers.length == 1 && !_savedServers[0].isDefault) {
        _savedServers[0] = _savedServers[0].copyWith(isDefault: true);
      }

      // 保存到SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final serversJson =
          _savedServers.map((server) => jsonEncode(server.toJson())).toList();

      await prefs.setStringList('socket_client_servers', serversJson);
      return true;
    } catch (e) {
      debugPrint('Error deleting server config: $e');
      return false;
    }
  }

  /// 批量删除服务器配置
  Future<bool> deleteServerConfigs(List<RemoteServerConfig> configs) async {
    try {
      // 加载现有配置
      await loadSavedServers();

      // 检查是否有默认服务器被删除
      bool deletedDefault = false;

      // 遍历要删除的配置
      for (var config in configs) {
        // 检查是否删除的是默认服务器
        for (var server in _savedServers) {
          if (server.host == config.host && server.port == config.port && server.isDefault) {
            deletedDefault = true;
            break;
          }
        }

        // 移除匹配的配置
        _savedServers.removeWhere(
          (server) => server.host == config.host && server.port == config.port,
        );
      }

      // 如果删除的是默认服务器，且还有其他服务器，则将第一个服务器设为默认
      if (deletedDefault && _savedServers.isNotEmpty) {
        _savedServers[0] = _savedServers[0].copyWith(isDefault: true);
      }

      // 如果删除后只剩一个服务器，则自动将其设置为默认服务器
      if (_savedServers.length == 1 && !_savedServers[0].isDefault) {
        _savedServers[0] = _savedServers[0].copyWith(isDefault: true);
      }

      // 保存到SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final serversJson =
          _savedServers.map((server) => jsonEncode(server.toJson())).toList();

      await prefs.setStringList('socket_client_servers', serversJson);
      return true;
    } catch (e) {
      debugPrint('Error deleting server configs: $e');
      return false;
    }
  }

  /// 获取默认服务器配置
  Future<RemoteServerConfig?> getDefaultServer() async {
    // 加载现有配置
    await loadSavedServers();

    // 查找默认服务器
    for (var server in _savedServers) {
      if (server.isDefault) {
        return server;
      }
    }

    // 如果没有默认服务器但有服务器配置，则返回第一个
    if (_savedServers.isNotEmpty) {
      return _savedServers.first;
    }

    // 没有服务器配置
    return null;
  }

  /// 设置默认服务器
  Future<bool> setDefaultServer(RemoteServerConfig config) async {
    // 创建一个新的配置，将isDefault设为true
    final newConfig = config.copyWith(isDefault: true);

    // 保存配置
    return await saveServerConfig(newConfig);
  }

  /// 完整的连接过程，包括初始连接和完成连接
  /// 可以被配置页和主页菜单共用
  ///
  /// [server] 要连接的服务器配置
  /// [onSuccess] 连接成功后的回调函数，可选
  /// [onFailure] 连接失败后的回调函数，可选
  ///
  /// 返回连接是否成功
  ///
  /// 注意：onSuccess 回调只会在收到 auth_response 并且认证成功后才会被调用
  Future<bool> connectComplete(
    RemoteServerConfig server, {
    Function()? onSuccess,
    Function(String error)? onFailure,
  }) async {
    try {
      // 先调用 connect 方法
      final connectSuccess = await connect(server);
      if (connectSuccess) {
        // 如果连接成功，再调用 completeConnection 方法完成连接过程
        // completeConnection 方法会等待认证完成
        final completeSuccess = await completeConnection();
        if (completeSuccess) {
          // 连接完全成功（包括认证成功），调用成功回调
          if (onSuccess != null) {
            onSuccess();
          }
          return true;
        } else {
          // 完成连接过程失败（可能是认证失败）
          if (onFailure != null) {
            onFailure('完成连接过程失败');
          }
          return false;
        }
      } else {
        // 初始连接失败
        if (onFailure != null) {
          onFailure('初始连接失败');
        }
        return false;
      }
    } catch (e) {
      // 连接过程发生异常
      if (onFailure != null) {
        onFailure('连接过程发生异常: ${e.toString()}');
      }
      return false;
    }
  }

  /// 连接到默认服务器
  ///
  /// [onSuccess] 连接成功后的回调函数，可选
  /// [onFailure] 连接失败后的回调函数，可选
  ///
  /// 返回连接是否成功
  Future<bool> connectToDefaultServer({
    Function()? onSuccess,
    Function(String error)? onFailure,
  }) async {
    final defaultServer = await getDefaultServer();
    if (defaultServer != null) {
      // 使用通用的连接方法
      return await connectComplete(
        defaultServer,
        onSuccess: onSuccess,
        onFailure: onFailure,
      );
    } else {
      // 没有默认服务器
      if (onFailure != null) {
        onFailure('没有默认服务器');
      }
      return false;
    }
  }

  /// 连接并执行操作
  ///
  /// 如果已连接，直接执行操作
  /// 如果未连接，先连接再执行操作
  ///
  /// [action] 要执行的操作
  /// [onConnectionFailure] 连接失败时的回调
  /// [server] 要连接的服务器，如果为null则使用默认服务器
  Future<void> connectAndExecute({
    required Function() action,
    Function(String error)? onConnectionFailure,
    RemoteServerConfig? server,
  }) async {
    // 检查当前连接状态
    if (status.value == SocketClientStatus.connected) {
      // 已连接，直接执行操作
      action();
    } else {
      // 未连接，先连接再执行操作
      if (server != null) {
        // 使用指定的服务器
        await connectComplete(
          server,
          onSuccess: action,
          onFailure: onConnectionFailure,
        );
      } else {
        // 使用默认服务器
        await connectToDefaultServer(
          onSuccess: action,
          onFailure: onConnectionFailure,
        );
      }
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
      final socket = await Socket.connect(uri.host, uri.port,
          timeout: const Duration(seconds: 5));
      await socket.close();

      return true;
    } catch (e) {
      return Future.error(e);
    }
  }

  // 移除了获取盐值的方法，改为使用 AuthUtils.getSaltSync() 获取盐值

  /// 从 WebSocketException 的错误消息中提取 HTTP 状态码
  ///
  /// 例如，从 "Connection to 'http://example.com' was not upgraded to websocket, HTTP status code: 403" 中提取 403
  ///
  /// 返回提取到的状态码，如果无法提取则返回 null
  int? _extractStatusCodeFromError(String errorMessage) {
    // 首先尝试匹配最精确的模式

    // 1. 匹配 "HTTP status code: XXX" 模式，这是最常见的格式
    final statusCodeRegex = RegExp(r'HTTP status code: (\d+)');
    final statusCodeMatch = statusCodeRegex.firstMatch(errorMessage);
    if (statusCodeMatch != null && statusCodeMatch.groupCount >= 1) {
      try {
        final int statusCode = int.parse(statusCodeMatch.group(1)!);
        if (statusCode >= 100 && statusCode < 600) {
          return statusCode;
        }
      } catch (e) {
        debugPrint('Error parsing status code: $e');
      }
    }

    // 2. 尝试其他可能的模式，按优先级排序
    final List<RegExp> patterns = [
      // 匹配 "Status code XXX" 或 "status code XXX" 模式
      RegExp(r'[sS]tatus code[:]?\s+(\d+)'),
      // 匹配 "HTTP XXX" 模式，但避免匹配 URL 中的 "http://"
      RegExp(r'HTTP\s+(\d+)'),
      // 匹配 "code: XXX" 或 "code XXX" 模式
      RegExp(r'code[:]?\s+(\d+)'),
      // 匹配 "XXX Unauthorized" 或 "XXX Forbidden" 等 HTTP 状态描述
      RegExp(r'(\d+)\s+(Unauthorized|Forbidden|Not Found|Internal Server Error)'),
    ];

    // 尝试每种模式
    for (final RegExp pattern in patterns) {
      final Match? match = pattern.firstMatch(errorMessage);
      if (match != null && match.groupCount >= 1) {
        try {
          final int statusCode = int.parse(match.group(1)!);
          // 只接受有效的 HTTP 状态码（100-599）
          if (statusCode >= 100 && statusCode < 600) {
            return statusCode;
          }
        } catch (e) {
          debugPrint('Error parsing status code: $e');
        }
      }
    }

    // 如果错误消息包含特定的关键词，返回相应的状态码
    if (errorMessage.toLowerCase().contains('unauthorized') ||
        errorMessage.toLowerCase().contains('authentication failed')) {
      return 401;
    } else if (errorMessage.toLowerCase().contains('forbidden') ||
               errorMessage.toLowerCase().contains('blacklist')) {
      return 403;
    } else if (errorMessage.toLowerCase().contains('not found')) {
      return 404;
    } else if (errorMessage.toLowerCase().contains('timeout')) {
      return 408; // Request Timeout
    }

    // 无法提取状态码
    return null;
  }

  /// 完成连接过程（在主线程中调用）
  Future<bool> completeConnection() async {
    if (status.value != SocketClientStatus.connecting ||
        currentServer == null) {
      return false;
    }

    try {
      final server = currentServer!;

      // 构建WebSocket URL
      final wsUrl = 'ws://${server.host}:${server.port}';

      // 准备连接
      Uri uri = Uri.parse(wsUrl);

      // 如果需要密码，准备认证头部
      if (server.password != null && server.password!.isNotEmpty) {
        // 获取盐值，优先使用自定义盐值（如果启用了），否则使用固定盐值
        // 使用 getSaltSync 方法获取盐值，优先使用自定义盐值（如果启用了）
        final salt = AuthUtils.getSaltSync();

        // 生成时间戳
        final timestamp = DateTime.now().millisecondsSinceEpoch;

        // 生成 token
        final token = AuthUtils.generateToken(server.password!, salt, timestamp);

        // 准备认证头部
        final Map<String, String> headers = {
          'Authorization': 'Bearer $token',
          'X-Auth-Timestamp': timestamp.toString(),
        };

        // 创建带认证头部的WebSocket连接
        _channel = IOWebSocketChannel.connect(
          uri,
          headers: headers,
        );
      } else {
        // 创建WebSocket连接（不带认证头部）
        _channel = IOWebSocketChannel.connect(uri);
      }

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
          if (connectionEstablished) {
            _handleDisconnect();
          }
          // onError 回调后 onDone 还会回调一次。
        },
        onError: (error) {
          // 如果当前已经建立连接，才触发错误事件。 否则是 _channel!.ready 的重复错误回调，已经在 下面 try catch 处理过一次_channel!.ready. 的错误回调了，这里不重复处理
          if (connectionEstablished) {
            _handleError(error.toString());
          }
        },
      );

      // 等待连接建立
      await connectionFuture; // 一般连接超时等失败，就卡在这里，不会往下了，catch 返回。也应该回调不了_channel!.stream.listen ，因为没有实际连接成功。

      // 更新状态为已连接，这样认证请求才能发送
      status.value = SocketClientStatus.connected;

      // 创建认证完成的 Completer
      _authCompleter = Completer<bool>();

      // 认证现在在握手阶段完成，不需要发送单独的认证消息
      // 直接完成认证 Completer
      if (_authCompleter != null && !_authCompleter!.isCompleted) {
        _authCompleter!.complete(true);
      }

      // 发送连接成功事件
      _eventController.add(SocketClientEvent(
        type: SocketClientEventType.connected,
      ));

      // 发送认证成功事件
      _eventController.add(SocketClientEvent(
        type: SocketClientEventType.auth,
        content: 'success',
      ));

      // if (Platform.isIOS) {
        _clientErrorSubscription = Stream.periodic(checkDuaration).listen(
          (_) async {
            // 如果应用在前台，执行定期检查
            if (_isAppInForeground &&
                status.value == SocketClientStatus.connected) {
              // 使用强制检查方法
              await _forceCheckClinetStatus();
            }
          },
          onError: (error, stackTrace) {
            // 定期检查流发生错误
            debugPrint('Periodic check error: $error');
            // 不需要处理，因为这只是定期检查的错误，不影响服务器本身
          },
        );
      // }

      debugPrint('连接成功，连接过程完成');
      return true;
    } catch (e) {
      // 一般是 403 黑名单。 或者 _channel!.ready 失败。
      // 使用_handleError方法处理错误，避免重复触发错误事件
      if(e.runtimeType == TimeoutException){
        _handleError('连接超时');
        return false;
      } else if(e.runtimeType == WebSocketException){
        // 尝试从 WebSocketException 的错误消息中解析 HTTP 状态码
        final String errorMessage = e.toString();
        debugPrint('WebSocketException: $errorMessage');

        // 测试特定的错误消息格式
        final testMessage = "WebSocketException: Connection to 'http://172.20.10.2:8080#' was not upgraded to websocket, HTTP status code: 403";
        final testStatusCode = _extractStatusCodeFromError(testMessage);
        debugPrint('测试消息提取的状态码: ${testStatusCode ?? "无法提取"}');

        int? statusCode = _extractStatusCodeFromError(errorMessage);
        debugPrint('提取到的 HTTP 状态码: ${statusCode ?? "无法提取"}');

        if(statusCode == 401) {
          _handleError('连接失败，授权失败');
        } else if(statusCode == 403) {
          _handleError('连接失败，您已被加入黑名单');
        } else if(statusCode != null) {
          _handleError('连接失败: HTTP $statusCode');
        } else {
          _handleError('连接失败: $errorMessage');
        }
        return false;
      }
      _handleError(e.toString());
      return false;
    }
  }

  /// 断开连接
  Future<void> disconnect() async {
    // 如果认证 Completer 尚未完成，则完成它（失败）
    if (_authCompleter != null && !_authCompleter!.isCompleted) {
      _authCompleter!.complete(false);
    }

    if (_channel != null) {
      await _channel!.sink.close(); // 会在在 _channel!.stream 的 onDone 回调中处理
      // _channel = null;
    }

    // status.value = SocketClientStatus.disconnected;
    // currentServer = null;

    // _eventController.add(SocketClientEvent(
    //   type: SocketClientEventType.disconnected,
    // ));
  }

  // 旧的认证请求方法已移除，现在认证在握手阶段完成

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

        if (type == 'content') {
          final String content = data['content'] ?? '';
          _eventController.add(SocketClientEvent(
            type: SocketClientEventType.content,
            content: content,
          ));
        } else if (type == 'error') {
          _handleError(data['message'] ?? '未知错误');
        } else if (type == 'ping') {
          // 处理 ping 消息，立即回复 pong 消息
          final int timestamp = data['timestamp'] ?? 0;
          _sendPongResponse(timestamp);
          debugPrint('收到服务端 ping 消息，已回复 pong 响应，时间戳: $timestamp');
        } else if (type == 'pong') {
          // pendingPing = false;
          _pingTimers?.cancel();
          _pingTimers = null;
          final int timestamp = data['timestamp'] ?? 0;
          final int roundTripTime =
              DateTime.now().millisecondsSinceEpoch - timestamp;
          debugPrint('收到服务端 pong 响应，往返时间: $roundTripTime ms');
        }
      } catch (e) {
        debugPrint('Error parsing message: $e');
      }
    }
  }

  /// 发送 pong 响应
  void _sendPongResponse(int timestamp) {
    if (_channel == null || status.value != SocketClientStatus.connected) {
      debugPrint('无法发送 pong 响应: WebSocket通道为空或未连接');
      return;
    }

    final pongResponse = jsonEncode({
      'type': 'pong',
      'timestamp': timestamp,
    });

    _channel!.sink.add(pongResponse);
  }

  void _sendPing() {
    if (_channel == null || status.value != SocketClientStatus.connected) {
      debugPrint('无法发送 ping 消息: WebSocket通道为空或未连接');
      return;
    }

    final timestamp = DateTime.now().millisecondsSinceEpoch;

    final pingreq = jsonEncode({
      'type': 'ping',
      'timestamp': timestamp,
    });

    _channel!.sink.add(pingreq);
  }

  /// 处理断开连接
  void _handleDisconnect() async {
    // 如果当前状态是错误，不要覆盖错误状态
    if (status.value != SocketClientStatus.error) {
      status.value = SocketClientStatus.disconnected;
    }

    // 取消服务器错误监听
    await _clientErrorSubscription?.cancel();
    _clientErrorSubscription = null;

    // pendingPing = false;
    _pingTimers?.cancel();
    _pingTimers = null;

    // 如果认证 Completer 尚未完成，则完成它（失败）
    if (_authCompleter != null && !_authCompleter!.isCompleted) {
      _authCompleter!.complete(false);
    }
    _authCompleter = null;

    _channel = null;
    currentServer = null;

    _eventController.add(SocketClientEvent(
      type: SocketClientEventType.disconnected,
    ));
  }

  /// 处理错误， 不一定是连接错误，不一定断开当前连接
  void _handleError(String error) {
    // 如果错误消息相同，不重复触发错误事件
    if (errorMessage == error) {
      return;
    }

    errorMessage = error;
    status.value = SocketClientStatus.error;

    // 如果认证 Completer 尚未完成，则完成它（失败）
    if (_authCompleter != null && !_authCompleter!.isCompleted) {
      _authCompleter!.complete(false);
    }

    _eventController.add(SocketClientEvent(
      type: SocketClientEventType.error,
      errorMessage: error,
    ));
  }

  /// 释放资源
  void dispose() {
    // 移除应用生命周期监听
    WidgetsBinding.instance.removeObserver(this);

    disconnect();
    _eventController.close();

    // 取消服务器错误监听
    _clientErrorSubscription?.cancel();
    _clientErrorSubscription = null;

    _pingTimers?.cancel();
    _pingTimers = null;
  }

  /// 应用生命周期变化回调
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
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
            status.value == SocketClientStatus.connected) {
          final difference =
              now.difference(_lastBackgroundTime!).inMilliseconds;

          // 如果应用在后台运行时间超过限制，自动检查服务器状态
          debugPrint('App was in background for $difference ms');

          // 无论后台运行时间多长，都强制检查服务器状态
          // 因为 iOS 在后台可能会暂停定时器，导致服务器状态检测失效
          _forceCheckClinetStatus();
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

  // 强制检查服务器状态，特别用于从后台恢复时。
  Future<void> _forceCheckClinetStatus() async {
    if (_channel == null) {
      return;
    }

    // 添加定期检查状态, 只需要发一个 ping ，如果连接有异常会回调 _channel!.stream.listen
    if (_pingTimers != null) {
      // 已经有正在等待回应的ping
      return;
    }
    // pendingPing = true;
    _pingTimers?.cancel();
    _pingTimers = Timer(pingpongDuaration, () async {
      // 如果 3 秒后客户端仍然存在，认为客户端已断开连接
      debugPrint('服务端 未在 30 秒内响应 ping，认为已断开连接');

      // 由于这是在异步的 Timer 回调中，我们需要直接处理断开连接的客户端
      // 而不是添加到 disconnectedSockets 列表中

      // 清理客户端资源并触发断开连接事件
      await disconnect();
    });
    _sendPing();
  }
}
