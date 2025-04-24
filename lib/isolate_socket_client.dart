import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// 定义Socket客户端的状态
enum IsolateSocketStatus {
  disconnected,
  connecting,
  connected,
  error,
}

/// 定义Socket客户端的事件类型
enum IsolateSocketEventType {
  connected,    // 连接成功
  disconnected, // 断开连接
  content,      // 接收到内容
  error,        // 发生错误
  auth,         // 认证相关
}

/// Socket客户端事件数据结构
class IsolateSocketEvent {
  final IsolateSocketEventType type;
  final String? content;
  final String? errorMessage;

  IsolateSocketEvent({
    required this.type,
    this.content,
    this.errorMessage,
  });
}

/// 消息类型定义，用于 Isolate 之间通信
class IsolateMessage {
  final String type;
  final Map<String, dynamic> data;

  IsolateMessage({
    required this.type,
    required this.data,
  });

  Map<String, dynamic> toMap() {
    return {
      'type': type,
      'data': data,
    };
  }

  factory IsolateMessage.fromMap(Map<String, dynamic> map) {
    return IsolateMessage(
      type: map['type'],
      data: map['data'],
    );
  }
}

/// 在 Isolate 中运行的 WebSocket 客户端
class IsolateSocketClient {
  // 单例模式
  static final IsolateSocketClient _instance = IsolateSocketClient._internal();
  factory IsolateSocketClient() => _instance;
  IsolateSocketClient._internal();

  // 状态
  final ValueNotifier<IsolateSocketStatus> status =
      ValueNotifier<IsolateSocketStatus>(IsolateSocketStatus.disconnected);

  // 错误信息
  String? errorMessage;

  // 当前连接的服务器信息（用于重连）
  String? _lastConnectedHost;
  int? _lastConnectedPort;
  String? _lastConnectedPassword;

  // 事件流控制器
  final StreamController<IsolateSocketEvent> _eventController =
      StreamController<IsolateSocketEvent>.broadcast();

  // 事件流
  Stream<IsolateSocketEvent> get events => _eventController.stream;

  // WebSocket Isolate
  Isolate? _webSocketIsolate;
  ReceivePort? _receivePort;
  SendPort? _sendPort;
  Completer<bool>? _connectionCompleter;

  /// 初始化 WebSocket Isolate
  Future<void> _initializeIsolate() async {
    // 清理旧的资源
    if (_webSocketIsolate != null) {
      _webSocketIsolate!.kill(priority: Isolate.immediate);
      _webSocketIsolate = null;
    }

    if (_receivePort != null) {
      _receivePort!.close();
      _receivePort = null;
    }

    // 创建新的接收端口
    _receivePort = ReceivePort();

    // 创建一个 Completer 来等待 SendPort
    final completer = Completer<SendPort>();

    // 创建一个本地变量来存储监听器
    final receivePort = _receivePort!;

    // 监听来自 WebSocket Isolate 的消息
    receivePort.listen((message) {
      if (!completer.isCompleted && message is SendPort) {
        // 第一条消息是 SendPort
        completer.complete(message);
        _sendPort = message;
      } else {
        // 其他消息交给消息处理函数
        _handleIsolateMessage(message);
      }
    });

    // 创建 WebSocket Isolate
    _webSocketIsolate = await Isolate.spawn(
      _webSocketIsolateEntry,
      receivePort.sendPort,
    );

    // 等待 SendPort
    await completer.future;

    debugPrint('WebSocket Isolate 初始化完成');
  }

  /// 处理来自 WebSocket Isolate 的消息
  void _handleIsolateMessage(dynamic message) {
    if (message is! Map) return;

    final type = message['type'];
    if (type is! String) return;

    final data = message['data'];
    if (data is! Map) return;

    switch (type) {
      case 'status':
        final statusValue = data['status'] is int ? data['status'] as int : null;
        if (statusValue != null) {
          status.value = IsolateSocketStatus.values[statusValue];
          debugPrint('状态更新: ${status.value}');
        }
        break;

      case 'error':
        final error = data['message'] is String ? data['message'] as String : null;
        if (error != null) {
          errorMessage = error;
          status.value = IsolateSocketStatus.error;
          _eventController.add(IsolateSocketEvent(
            type: IsolateSocketEventType.error,
            errorMessage: error,
          ));
          debugPrint('错误: $error');
        }
        break;

      case 'connected':
        _eventController.add(IsolateSocketEvent(
          type: IsolateSocketEventType.connected,
        ));

        // 如果有等待连接的 Completer，完成它
        _connectionCompleter?.complete(true);
        _connectionCompleter = null;
        break;

      case 'disconnected':
        // 更新状态为断开连接
        status.value = IsolateSocketStatus.disconnected;

        _eventController.add(IsolateSocketEvent(
          type: IsolateSocketEventType.disconnected,
        ));

        debugPrint('连接已断开');
        break;

      case 'auth_response':
        final success = data['success'] is bool ? data['success'] as bool : null;
        if (success == true) {
          _eventController.add(IsolateSocketEvent(
            type: IsolateSocketEventType.auth,
            content: 'success',
          ));
        } else {
          final message = data['message'] is String ? data['message'] as String : '未知原因';
          _eventController.add(IsolateSocketEvent(
            type: IsolateSocketEventType.error,
            errorMessage: '认证失败: $message',
          ));
        }
        break;

      case 'content':
        final content = data['content'] is String ? data['content'] as String : null;
        if (content != null) {
          _eventController.add(IsolateSocketEvent(
            type: IsolateSocketEventType.content,
            content: content,
          ));
        }
        break;

      case 'log':
        final logMessage = data['message'] is String ? data['message'] as String : null;
        if (logMessage != null) {
          debugPrint('[WebSocket Isolate] $logMessage');
        }
        break;
    }
  }

  /// 连接到服务器
  Future<bool> connect(String host, int port, {String? password}) async {
    // 如果已经连接，先断开
    if (status.value == IsolateSocketStatus.connected) {
      await disconnect();
    }

    // 保存当前连接信息
    _lastConnectedHost = host;
    _lastConnectedPort = port;
    _lastConnectedPassword = password;

    // 更新状态为连接中
    status.value = IsolateSocketStatus.connecting;
    errorMessage = null;

    // 初始化 WebSocket Isolate
    await _initializeIsolate();

    // 创建连接完成器
    _connectionCompleter = Completer<bool>();

    // 发送连接命令到 WebSocket Isolate
    _sendPort?.send({
      'type': 'connect',
      'data': {
        'host': host,
        'port': port,
        'password': password,
      },
    });

    // 等待连接结果，设置超时
    try {
      return await _connectionCompleter!.future.timeout(
        const Duration(seconds: 3), // 减少超时时间，因为连接拒绝错误会立即被捕获
        onTimeout: () {
          // 只有当状态不是错误时才更新状态和发送错误事件
          // 这样可以避免重复发送错误事件
          if (status.value != IsolateSocketStatus.error) {
            errorMessage = '连接超时，服务器可能未响应';
            status.value = IsolateSocketStatus.error;
            _eventController.add(IsolateSocketEvent(
              type: IsolateSocketEventType.error,
              errorMessage: '连接超时，服务器可能未响应',
            ));

            // 确保 UI 更新
            debugPrint('连接超时，状态已更新为错误');
          }

          return false;
        },
      );
    } catch (e) {
      // 只有当状态不是错误时才更新状态和发送错误事件
      // 这样可以避免重复发送错误事件
      if (status.value != IsolateSocketStatus.error) {
        errorMessage = e.toString();
        status.value = IsolateSocketStatus.error;
        _eventController.add(IsolateSocketEvent(
          type: IsolateSocketEventType.error,
          errorMessage: e.toString(),
        ));

        // 确保 UI 更新
        debugPrint('连接错误: $e，状态已更新为错误');
      }

      return false;
    }
  }

  /// 断开连接
  Future<void> disconnect() async {
    if (status.value == IsolateSocketStatus.disconnected) return;

    // 发送断开连接命令到 WebSocket Isolate
    _sendPort?.send({
      'type': 'disconnect',
      'data': {},
    });

    // 主动更新状态为断开连接
    status.value = IsolateSocketStatus.disconnected;

    // 发送断开连接事件
    _eventController.add(IsolateSocketEvent(
      type: IsolateSocketEventType.disconnected,
    ));

    // 清除当前连接信息
    _lastConnectedHost = null;
    _lastConnectedPort = null;
    _lastConnectedPassword = null;
  }

  /// 发送获取内容请求
  void fetchContent() {
    if (status.value != IsolateSocketStatus.connected) return;

    // 发送获取内容命令到 WebSocket Isolate
    _sendPort?.send({
      'type': 'fetch',
      'data': {},
    });
  }

  /// 发送推送内容请求
  void pushContent(String content) {
    if (status.value != IsolateSocketStatus.connected) return;

    // 发送推送内容命令到 WebSocket Isolate
    _sendPort?.send({
      'type': 'push',
      'data': {
        'content': content,
      },
    });
  }

  /// 重新连接到上一次连接的服务器
  Future<bool> reconnect() async {
    if (_lastConnectedHost == null || _lastConnectedPort == null) {
      return false;
    }

    return await connect(
      _lastConnectedHost!,
      _lastConnectedPort!,
      password: _lastConnectedPassword,
    );
  }

  /// 释放资源
  void dispose() {
    disconnect();

    // 关闭 WebSocket Isolate
    if (_webSocketIsolate != null) {
      _webSocketIsolate!.kill(priority: Isolate.immediate);
      _webSocketIsolate = null;
    }

    // 关闭接收端口
    if (_receivePort != null) {
      _receivePort!.close();
      _receivePort = null;
    }

    // 关闭事件控制器
    _eventController.close();
  }

  /// WebSocket Isolate 入口函数
  static void _webSocketIsolateEntry(SendPort mainSendPort) {
    // 创建接收端口
    final receivePort = ReceivePort();

    // 发送 SendPort 到主 Isolate
    mainSendPort.send(receivePort.sendPort);

    // WebSocket 连接
    WebSocketChannel? channel;
    IsolateSocketStatus status = IsolateSocketStatus.disconnected;

    // 发送日志到主 Isolate
    void log(String message) {
      mainSendPort.send({
        'type': 'log',
        'data': {
          'message': message,
        },
      });
    }

    // 更新状态并通知主 Isolate
    void updateStatus(IsolateSocketStatus newStatus) {
      status = newStatus;
      mainSendPort.send({
        'type': 'status',
        'data': {
          'status': newStatus.index,
        },
      });
    }

    // 发送错误到主 Isolate
    void sendError(String message) {
      mainSendPort.send({
        'type': 'error',
        'data': {
          'message': message,
        },
      });
    }

    // 处理 WebSocket 消息
    void handleWebSocketMessage(dynamic message) {
      if (message is String) {
        try {
          // 快速检查是否是 ping 消息
          if (message.contains('"type":"ping"')) {
            // 使用正则表达式快速提取时间戳
            final regExp = RegExp(r'"timestamp":(\d+)');
            final match = regExp.firstMatch(message);
            if (match != null && match.groupCount >= 1) {
              final timestamp = int.parse(match.group(1)!);

              // 直接发送 pong 响应
              if (channel != null && status == IsolateSocketStatus.connected) {
                channel!.sink.add(jsonEncode({
                  'type': 'pong',
                  'timestamp': timestamp,
                }));

                log('收到 ping 消息，已回复 pong 响应，时间戳: $timestamp');
              }
              return;
            }
          }

          // 处理其他消息类型
          final data = jsonDecode(message);
          final type = data['type'];

          switch (type) {
            case 'auth_response':
              final success = data['success'] is bool ? data['success'] as bool : false;
              if (success) {
                log('认证成功');
                mainSendPort.send({
                  'type': 'auth_response',
                  'data': {
                    'success': true,
                  },
                });
              } else {
                final errorMessage = data['message'] is String ? data['message'] as String : '未知原因';
                log('认证失败: $errorMessage');
                mainSendPort.send({
                  'type': 'auth_response',
                  'data': {
                    'success': false,
                    'message': errorMessage,
                  },
                });
              }
              break;

            case 'content':
              final content = data['content'] is String ? data['content'] as String : '';
              mainSendPort.send({
                'type': 'content',
                'data': {
                  'content': content,
                },
              });
              break;

            case 'error':
              final errorMessage = data['message'] is String ? data['message'] as String : '未知错误';
              sendError(errorMessage);
              break;

            case 'ping':
              // 备用处理 ping 消息
              final timestamp = data['timestamp'] is int ? data['timestamp'] as int : 0;
              if (channel != null && status == IsolateSocketStatus.connected) {
                channel!.sink.add(jsonEncode({
                  'type': 'pong',
                  'timestamp': timestamp,
                }));

                log('收到 ping 消息（备用处理），已回复 pong 响应，时间戳: $timestamp');
              }
              break;

            default:
              log('收到未知类型的消息: $type');
          }
        } catch (e) {
          log('解析消息错误: $e');
        }
      }
    }

    // 监听来自主 Isolate 的命令
    receivePort.listen((message) {
      if (message is! Map) return;

      final type = message['type'];
      if (type is! String) return;

      final data = message['data'];
      if (data is! Map) return;

      switch (type) {
        case 'connect':
          final host = data['host'] is String ? data['host'] as String : null;
          final port = data['port'] is int ? data['port'] as int : null;
          final password = data['password'] is String ? data['password'] as String : null;

          if (host == null || port == null) {
            sendError('连接参数无效');
            return;
          }

          // 断开现有连接
          if (channel != null) {
            channel!.sink.close();
            channel = null;
          }

          // 更新状态为连接中
          updateStatus(IsolateSocketStatus.connecting);

          // 尝试连接
          try {
            final wsUrl = 'ws://$host:$port';
            log('正在连接到 $wsUrl');

            // 检查 IP 地址是否为本地回环地址
            if (host == '127.0.0.1' || host == 'localhost') {
              log('警告：正在尝试连接到本地回环地址，这可能无法在移动设备上正常工作');
            }

            // 创建 WebSocket 连接，添加超时处理
            // 使用更详细的日志记录
            log('开始创建 WebSocket 连接...');

            // 使用 IOWebSocketChannel.connect
            log('使用 IOWebSocketChannel.connect 创建连接');

            // 添加更多连接选项
            final uri = Uri.parse(wsUrl);
            log('连接 URI: $uri');
            log('主机: ${uri.host}, 端口: ${uri.port}');

            // 设置一个标志，用于检测是否收到了服务器的响应
            bool receivedResponse = false;

            // 使用更简单的连接方式
            try {
              channel = IOWebSocketChannel.connect(
                uri,
                pingInterval: const Duration(seconds: 30),
                headers: {
                  'Connection': 'Upgrade',
                  'Upgrade': 'websocket',
                },
              );
            } catch (e) {
              // 立即处理连接错误
              log('WebSocket 连接失败: $e');

              // 构建友好的错误消息
              String errorMsg = '连接失败';
              if (e.toString().contains('Connection refused')) {
                errorMsg = '服务器可能未启动';
              } else if (e.toString().contains('Network is unreachable')) {
                errorMsg = '网络不可达: 请检查网络连接和服务器地址';
              } else {
                errorMsg = '连接失败: ${e.toString()}';
              }

              // 更新状态为错误
              updateStatus(IsolateSocketStatus.error);

              // 发送错误到主线程（只发送一次）
              sendError(errorMsg);

              // 注意：我们不再发送额外的错误事件
              // 错误已经通过 sendError 函数发送，会在主线程中处理

              // 直接返回，不执行后续代码
              return;
            }

            // 确保 channel 不为空
            if (channel == null) {
              throw Exception('WebSocket 连接创建失败');
            }

            // 设置一个监听器，用于检测服务器的响应
            final responseCompleter = Completer<bool>();
            final subscription = channel!.stream.listen(
              (message) {
                log('收到服务器响应: $message');
                receivedResponse = true;
                if (!responseCompleter.isCompleted) {
                  responseCompleter.complete(true);
                }
              },
              onError: (error) {
                log('连接错误: $error');
                if (!responseCompleter.isCompleted) {
                  responseCompleter.completeError(error);
                }
              },
              onDone: () {
                log('连接已关闭');
                if (!responseCompleter.isCompleted) {
                  responseCompleter.complete(false);
                }
              },
            );

            // 发送一个初始消息来验证连接是否真正建立
            log('发送初始消息验证连接...');
            channel!.sink.add(jsonEncode({
              'type': 'auth',
              'password': password ?? '',
            }));

            // 使用同步延迟，确保连接是真实的
            final startTime = DateTime.now();
            while (DateTime.now().difference(startTime).inMilliseconds < 1000 && !receivedResponse) {
              // 简单的延迟
            }

            // 如果没有收到响应，抛出异常
            if (!receivedResponse) {
              // 取消订阅
              subscription.cancel();

              // 关闭连接
              channel!.sink.close();

              // 抛出异常
              throw Exception('连接超时，未收到服务器响应，服务器可能未启动');
            }

            // 取消临时订阅
            subscription.cancel();

            log('成功创建 WebSocket 连接');

            // 设置消息监听
            channel!.stream.listen(
              handleWebSocketMessage,
              onDone: () {
                log('WebSocket 连接已关闭');
                updateStatus(IsolateSocketStatus.disconnected);
                mainSendPort.send({
                  'type': 'disconnected',
                  'data': {},
                });
                channel = null;
              },
              onError: (error) {
                log('WebSocket 错误: $error');

                // 更新状态为错误
                updateStatus(IsolateSocketStatus.error);

                // 发送错误到主线程（只发送一次）
                sendError('WebSocket 错误: $error');

                channel = null;
              },
            );

            // 更新状态为已连接
            updateStatus(IsolateSocketStatus.connected);

            // 发送连接成功消息到主 Isolate
            mainSendPort.send({
              'type': 'connected',
              'data': {},
            });

            // 如果有密码，发送认证请求
            if (password != null && password.isNotEmpty) {
              log('发送认证请求，密码长度: ${password.length}');
              channel!.sink.add(jsonEncode({
                'type': 'auth',
                'password': password,
              }));
            }
          } catch (e, stackTrace) {
            log('连接错误: $e');
            log('堆栈跟踪: $stackTrace');

            // 提供更详细的错误信息
            String errorMsg = '连接错误: $e';
            if (e is SocketException) {
              if (e.message.contains('Connection refused')) {
                errorMsg = '连接被拒绝: 服务器可能未启动或端口错误 (${e.port})';
              } else if (e.message.contains('Network is unreachable')) {
                errorMsg = '网络不可达: 请检查网络连接和服务器地址 (${e.address})';
              }
            }

            // 更新状态为错误
            updateStatus(IsolateSocketStatus.error);

            // 发送错误到主线程（只发送一次）
            sendError(errorMsg);
          }
          break;

        case 'disconnect':
          if (channel != null) {
            log('断开连接');
            channel!.sink.close();
            channel = null;
            updateStatus(IsolateSocketStatus.disconnected);
            mainSendPort.send({
              'type': 'disconnected',
              'data': {},
            });
          }
          break;

        case 'fetch':
          if (channel != null && status == IsolateSocketStatus.connected) {
            log('发送获取内容请求');
            channel!.sink.add(jsonEncode({
              'type': 'fetch',
            }));
          } else {
            log('无法发送获取内容请求: 未连接');
          }
          break;

        case 'push':
          if (channel != null && status == IsolateSocketStatus.connected) {
            final content = data['content'] is String ? data['content'] as String : null;
            if (content != null) {
              log('发送推送内容请求，内容长度: ${content.length}');
              channel!.sink.add(jsonEncode({
                'type': 'push',
                'content': content,
              }));
            } else {
              log('无法发送推送内容请求: 内容为空');
            }
          } else {
            log('无法发送推送内容请求: 未连接');
          }
          break;
      }
    });
  }
}
