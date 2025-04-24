import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'isolate_socket_client.dart';

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

/// Socket客户端类 - 使用 IsolateSocketClient 的适配器
class SocketClient {
  // 单例模式
  static final SocketClient _instance = SocketClient._internal();
  factory SocketClient() => _instance;

  SocketClient._internal() {
    // 初始化 IsolateSocketClient
    _isolateClient = IsolateSocketClient();

    // 监听 IsolateSocketClient 事件
    _isolateClient.events.listen(_handleIsolateClientEvent);

    // 监听 IsolateSocketClient 状态变化
    _isolateClient.status.addListener(_handleIsolateClientStatusChange);
  }

  // IsolateSocketClient 实例
  late final IsolateSocketClient _isolateClient;

  // 状态映射
  final Map<IsolateSocketStatus, SocketClientStatus> _statusMap = {
    IsolateSocketStatus.disconnected: SocketClientStatus.disconnected,
    IsolateSocketStatus.connecting: SocketClientStatus.connecting,
    IsolateSocketStatus.connected: SocketClientStatus.connected,
    IsolateSocketStatus.error: SocketClientStatus.error,
  };

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
        (server) => server.host == config.host,
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

      // 移除匹配的配置
      _savedServers.removeWhere(
        (server) => server.host == config.host && server.port == config.port,
      );

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

  /// 连接到远程服务器
  Future<bool> connect(RemoteServerConfig server) async {
    if (status.value == SocketClientStatus.connected) {
      await disconnect();
    }

    // 更新当前服务器配置
    currentServer = server;

    // 连接到服务器
    final success = await _isolateClient.connect(
      server.host,
      server.port,
      password: server.password,
    );

    return success;
  }

  /// 完成连接过程（在主线程中调用）
  Future<bool> completeConnection() async {
    // 在 Isolate 模式下，连接过程已经在 connect 方法中完成
    // 这个方法保留是为了保持 API 兼容性
    return status.value == SocketClientStatus.connected;
  }

  /// 断开连接
  Future<void> disconnect() async {
    await _isolateClient.disconnect();
  }

  /// 发送获取内容请求
  void fetchContent() {
    _isolateClient.fetchContent();
  }

  /// 发送推送内容请求
  void pushContent(String content) {
    _isolateClient.pushContent(content);
  }

  /// 处理 IsolateSocketClient 事件
  void _handleIsolateClientEvent(IsolateSocketEvent event) {
    switch (event.type) {
      case IsolateSocketEventType.connected:
        _eventController.add(SocketClientEvent(
          type: SocketClientEventType.connected,
        ));
        break;

      case IsolateSocketEventType.disconnected:
        _eventController.add(SocketClientEvent(
          type: SocketClientEventType.disconnected,
        ));
        break;

      case IsolateSocketEventType.content:
        _eventController.add(SocketClientEvent(
          type: SocketClientEventType.content,
          content: event.content,
        ));
        break;

      case IsolateSocketEventType.error:
        errorMessage = event.errorMessage;
        _eventController.add(SocketClientEvent(
          type: SocketClientEventType.error,
          errorMessage: event.errorMessage,
        ));
        break;

      case IsolateSocketEventType.auth:
        _eventController.add(SocketClientEvent(
          type: SocketClientEventType.auth,
          content: event.content,
        ));
        break;
    }
  }

  /// 处理 IsolateSocketClient 状态变化
  void _handleIsolateClientStatusChange() {
    // 将 IsolateSocketStatus 映射到 SocketClientStatus
    final isolateStatus = _isolateClient.status.value;
    final clientStatus = _statusMap[isolateStatus]!;

    // 更新状态
    status.value = clientStatus;

    // 更新错误信息
    if (isolateStatus == IsolateSocketStatus.error) {
      errorMessage = _isolateClient.errorMessage;
    }
  }

  /// 释放资源
  void dispose() {
    disconnect();
    _eventController.close();
    _isolateClient.dispose();
  }
}
