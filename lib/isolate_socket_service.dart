import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/foundation.dart';

/// 定义Socket服务端的状态
enum IsolateSocketServerStatus {
  stopped,
  starting,
  running,
  error,
}

/// 定义Socket服务端的事件类型
enum IsolateSocketServerEventType {
  started,           // 服务器启动
  stopped,           // 服务器停止
  clientConnected,   // 客户端连接
  clientDisconnected,// 客户端断开
  fetch,             // 收到获取内容请求
  push,              // 收到推送内容请求
  error,             // 发生错误
}

/// Socket服务端事件数据结构
class IsolateSocketServerEvent {
  final IsolateSocketServerEventType type;
  final String? content;
  final String? clientIP;
  final String? errorMessage;

  IsolateSocketServerEvent({
    required this.type,
    this.content,
    this.clientIP,
    this.errorMessage,
  });
}

/// 在 Isolate 中运行的 WebSocket 服务端
class IsolateSocketServer {
  // 单例模式
  static final IsolateSocketServer _instance = IsolateSocketServer._internal();
  factory IsolateSocketServer() => _instance;
  IsolateSocketServer._internal();

  // 状态
  final ValueNotifier<IsolateSocketServerStatus> status =
      ValueNotifier<IsolateSocketServerStatus>(IsolateSocketServerStatus.stopped);

  // 错误信息
  String? errorMessage;

  // 服务器配置
  int? _currentPort;
  String? _currentPassword;
  bool _requirePassword = false;

  // 事件流控制器
  final StreamController<IsolateSocketServerEvent> _eventController =
      StreamController<IsolateSocketServerEvent>.broadcast();

  // 事件流
  Stream<IsolateSocketServerEvent> get events => _eventController.stream;

  // WebSocket 服务端 Isolate
  Isolate? _serverIsolate;
  ReceivePort? _receivePort;
  SendPort? _sendPort;
  Completer<bool>? _startCompleter;

  // 客户端计数
  final ValueNotifier<int> clientCountNotifier = ValueNotifier<int>(0);

  /// 初始化服务端 Isolate
  Future<void> _initializeIsolate() async {
    // 清理旧的资源
    if (_serverIsolate != null) {
      _serverIsolate!.kill(priority: Isolate.immediate);
      _serverIsolate = null;
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

    // 监听来自服务端 Isolate 的消息
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

    // 创建服务端 Isolate
    _serverIsolate = await Isolate.spawn(
      _serverIsolateEntry,
      receivePort.sendPort,
    );

    // 等待 SendPort
    await completer.future;

    debugPrint('WebSocket 服务端 Isolate 初始化完成');
  }

  /// 处理来自服务端 Isolate 的消息
  void _handleIsolateMessage(dynamic message) {
    if (message is! Map) return;

    final type = message['type'];
    if (type is! String) return;

    final data = message['data'];
    if (data is! Map) return;

    switch (type) {
      case 'status':
        final statusValue = data['status'] as int?;
        if (statusValue != null) {
          status.value = IsolateSocketServerStatus.values[statusValue];
          debugPrint('服务端状态更新: ${status.value}');
        }
        break;

      case 'error':
        final error = data['message'] as String?;
        if (error != null) {
          errorMessage = error;
          status.value = IsolateSocketServerStatus.error;
          _eventController.add(IsolateSocketServerEvent(
            type: IsolateSocketServerEventType.error,
            errorMessage: error,
          ));
          debugPrint('服务端错误: $error');
        }
        break;

      case 'started':
        final port = data['port'] as int?;
        if (port != null) {
          _currentPort = port;
          _eventController.add(IsolateSocketServerEvent(
            type: IsolateSocketServerEventType.started,
            content: port.toString(),
          ));

          // 如果有等待启动的 Completer，完成它
          _startCompleter?.complete(true);
          _startCompleter = null;
        }
        break;

      case 'stopped':
        _currentPort = null;
        _eventController.add(IsolateSocketServerEvent(
          type: IsolateSocketServerEventType.stopped,
        ));
        break;

      case 'client_connected':
        final clientIP = data['clientIP'] as String?;
        if (clientIP != null) {
          clientCountNotifier.value++;
          _eventController.add(IsolateSocketServerEvent(
            type: IsolateSocketServerEventType.clientConnected,
            clientIP: clientIP,
          ));
        }
        break;

      case 'client_disconnected':
        final clientIP = data['clientIP'] as String?;
        if (clientIP != null) {
          clientCountNotifier.value = (clientCountNotifier.value - 1).clamp(0, double.infinity).toInt();
          _eventController.add(IsolateSocketServerEvent(
            type: IsolateSocketServerEventType.clientDisconnected,
            clientIP: clientIP,
          ));
        }
        break;

      case 'fetch':
        final clientIP = data['clientIP'] as String?;
        _eventController.add(IsolateSocketServerEvent(
          type: IsolateSocketServerEventType.fetch,
          clientIP: clientIP,
        ));
        break;

      case 'push':
        final clientIP = data['clientIP'] as String?;
        final content = data['content'] as String?;
        _eventController.add(IsolateSocketServerEvent(
          type: IsolateSocketServerEventType.push,
          clientIP: clientIP,
          content: content,
        ));
        break;

      case 'log':
        final logMessage = data['message'] as String?;
        if (logMessage != null) {
          debugPrint('[WebSocket Server Isolate] $logMessage');
        }
        break;
    }
  }

  /// 启动服务器
  Future<bool> startServer({
    int port = 8080,
    String? password,
    bool requirePassword = false,
  }) async {
    // 如果服务器已经在运行，先停止
    if (status.value == IsolateSocketServerStatus.running) {
      await stopServer();
    }

    // 保存当前配置
    _currentPort = port;
    _currentPassword = password;
    _requirePassword = requirePassword;

    // 更新状态为启动中
    status.value = IsolateSocketServerStatus.starting;
    errorMessage = null;

    // 初始化服务端 Isolate
    await _initializeIsolate();

    // 创建启动完成器
    _startCompleter = Completer<bool>();

    // 发送启动命令到服务端 Isolate
    _sendPort?.send({
      'type': 'start',
      'data': {
        'port': port,
        'password': password,
        'requirePassword': requirePassword,
      },
    });

    // 等待启动结果，设置超时
    try {
      return await _startCompleter!.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          errorMessage = '启动服务器超时';
          status.value = IsolateSocketServerStatus.error;
          _eventController.add(IsolateSocketServerEvent(
            type: IsolateSocketServerEventType.error,
            errorMessage: '启动服务器超时',
          ));
          return false;
        },
      );
    } catch (e) {
      errorMessage = e.toString();
      status.value = IsolateSocketServerStatus.error;
      _eventController.add(IsolateSocketServerEvent(
        type: IsolateSocketServerEventType.error,
        errorMessage: e.toString(),
      ));
      return false;
    }
  }

  /// 停止服务器
  Future<void> stopServer() async {
    if (status.value == IsolateSocketServerStatus.stopped) return;

    // 发送停止命令到服务端 Isolate
    _sendPort?.send({
      'type': 'stop',
      'data': {},
    });

    // 清除当前配置
    _currentPort = null;
    _currentPassword = null;
    clientCountNotifier.value = 0;
  }

  /// 发送内容到所有客户端
  void sendContentToAll(String content) {
    if (status.value != IsolateSocketServerStatus.running) return;

    // 发送内容命令到服务端 Isolate
    _sendPort?.send({
      'type': 'send_to_all',
      'data': {
        'content': content,
      },
    });
  }

  /// 发送内容到特定客户端
  void sendContentToClient(String clientIP, String content) {
    if (status.value != IsolateSocketServerStatus.running) return;

    // 发送内容命令到服务端 Isolate
    _sendPort?.send({
      'type': 'send_to_client',
      'data': {
        'clientIP': clientIP,
        'content': content,
      },
    });
  }

  /// 断开特定客户端
  void disconnectClient(String clientIP) {
    if (status.value != IsolateSocketServerStatus.running) return;

    // 发送断开客户端命令到服务端 Isolate
    _sendPort?.send({
      'type': 'disconnect_client',
      'data': {
        'clientIP': clientIP,
      },
    });
  }

  /// 获取当前连接的客户端数量
  int get clientCount => clientCountNotifier.value;

  /// 获取当前端口
  int? get currentPort => _currentPort;

  /// 获取当前密码
  String? get currentPassword => _currentPassword;

  /// 是否需要密码
  bool get requirePassword => _requirePassword;

  /// 释放资源
  void dispose() {
    stopServer();

    // 关闭服务端 Isolate
    if (_serverIsolate != null) {
      _serverIsolate!.kill(priority: Isolate.immediate);
      _serverIsolate = null;
    }

    // 关闭接收端口
    if (_receivePort != null) {
      _receivePort!.close();
      _receivePort = null;
    }

    // 关闭事件控制器
    _eventController.close();
  }

  /// 服务端 Isolate 入口函数
  static void _serverIsolateEntry(SendPort mainSendPort) {
    // 创建接收端口
    final receivePort = ReceivePort();

    // 发送 SendPort 到主 Isolate
    mainSendPort.send(receivePort.sendPort);

    // 服务器实例
    HttpServer? server;

    // 客户端列表
    final clients = <WebSocket>[];
    final clientIPs = <WebSocket, String>{};
    final authenticatedClients = <WebSocket>{};
    final ipToClient = <String, WebSocket>{};

    // ping-pong 状态跟踪
    final lastPingSentTime = <WebSocket, DateTime>{};
    final lastPongReceivedTime = <WebSocket, DateTime>{};

    // 密码配置
    String? password;
    bool requirePassword = false;

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
    void updateStatus(IsolateSocketServerStatus newStatus) {
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

    // 处理客户端断开连接
    void handleClientDisconnect(WebSocket socket) {
      final clientIP = clientIPs[socket];

      // 从列表中移除
      clients.remove(socket);
      authenticatedClients.remove(socket);

      // 清理 ping-pong 状态
      lastPingSentTime.remove(socket);
      lastPongReceivedTime.remove(socket);

      if (clientIP != null) {
        ipToClient.remove(clientIP);
        clientIPs.remove(socket);

        // 通知主 Isolate 客户端已断开连接
        mainSendPort.send({
          'type': 'client_disconnected',
          'data': {
            'clientIP': clientIP,
          },
        });

        log('客户端已断开连接: $clientIP');
      }
    }

    // 处理 WebSocket 消息
    void handleWebSocketMessage(WebSocket socket, dynamic message) {
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
              try {
                socket.add(jsonEncode({
                  'type': 'pong',
                  'timestamp': timestamp,
                }));

                log('收到 ping 消息，已回复 pong 响应，时间戳: $timestamp');
              } catch (e) {
                log('发送 pong 响应失败: $e');
              }
              return;
            }
          }

          final data = jsonDecode(message);
          final type = data['type'];
          final clientIP = clientIPs[socket];

          switch (type) {
            case 'auth':
              final clientPassword = data['password'] ?? '';

              // 如果不需要密码，或者密码正确
              if (!requirePassword || clientPassword == password) {
                authenticatedClients.add(socket);

                // 发送认证成功响应
                socket.add(jsonEncode({
                  'type': 'auth_response',
                  'success': true,
                }));

                log('客户端认证成功: ${clientIP ?? "未知IP"}');
              } else {
                // 发送认证失败响应
                socket.add(jsonEncode({
                  'type': 'auth_response',
                  'success': false,
                  'message': '密码错误',
                }));

                log('客户端认证失败: ${clientIP ?? "未知IP"}');

                // 断开连接
                socket.close();
              }
              break;

            case 'fetch':
              // 检查是否已认证
              if (requirePassword && !authenticatedClients.contains(socket)) {
                socket.add(jsonEncode({
                  'type': 'error',
                  'message': '未认证',
                }));
                return;
              }

              // 通知主 Isolate 收到获取内容请求
              mainSendPort.send({
                'type': 'fetch',
                'data': {
                  'clientIP': clientIP,
                },
              });

              log('收到获取内容请求: ${clientIP ?? "未知IP"}');
              break;

            case 'push':
              // 检查是否已认证
              if (requirePassword && !authenticatedClients.contains(socket)) {
                socket.add(jsonEncode({
                  'type': 'error',
                  'message': '未认证',
                }));
                return;
              }

              final content = data['content'] ?? '';

              // 通知主 Isolate 收到推送内容请求
              mainSendPort.send({
                'type': 'push',
                'data': {
                  'clientIP': clientIP,
                  'content': content,
                },
              });

              log('收到推送内容请求: ${clientIP ?? "未知IP"}, 内容长度: ${content.length}');
              break;

            case 'pong':
              // 处理 pong 响应
              final timestamp = data['timestamp'] ?? 0;
              final now = DateTime.now();
              final roundTripTime = now.millisecondsSinceEpoch - timestamp;

              // 记录接收 pong 的时间
              lastPongReceivedTime[socket] = now;

              log('收到 pong 响应: ${clientIP ?? "未知IP"}, 往返时间: $roundTripTime ms');
              break;

            default:
              log('收到未知类型的消息: $type, 来自: ${clientIP ?? "未知IP"}');
          }
        } catch (e) {
          log('解析消息错误: $e');
        }
      }
    }

    // 处理 WebSocket 请求
    Future<void> handleWebSocketRequest(HttpRequest request) async {
      // 获取客户端 IP
      final clientIP = request.connectionInfo?.remoteAddress.address;

      try {
        // 升级到 WebSocket 连接
        final socket = await WebSocketTransformer.upgrade(request);
        clients.add(socket);

        // 存储客户端 IP
        if (clientIP != null) {
          clientIPs[socket] = clientIP;
          ipToClient[clientIP] = socket;
        }

        // 通知主 Isolate 客户端已连接
        mainSendPort.send({
          'type': 'client_connected',
          'data': {
            'clientIP': clientIP,
          },
        });

        log('客户端已连接: ${clientIP ?? "未知IP"}');

        // 监听 WebSocket 消息
        socket.listen(
          (dynamic message) {
            handleWebSocketMessage(socket, message);
          },
          onDone: () {
            handleClientDisconnect(socket);
          },
          onError: (error) {
            log('WebSocket 错误: $error');
            handleClientDisconnect(socket);
          },
        );
      } catch (e) {
        log('处理 WebSocket 请求错误: $e');
      }
    }

    // 定期发送 ping 消息和检查未响应的客户端
    Timer? pingTimer;
    Timer? connectionCheckTimer;

    void startPingTimer() {
      // 取消现有的定时器
      pingTimer?.cancel();
      connectionCheckTimer?.cancel();

      // 启动 ping 定时器
      pingTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
        if (clients.isEmpty) return;

        final now = DateTime.now();
        final timestamp = now.millisecondsSinceEpoch;
        final pingMessage = jsonEncode({
          'type': 'ping',
          'timestamp': timestamp,
        });

        // 记录需要清理的客户端
        final clientsToRemove = <WebSocket>[];

        for (var client in clients) {
          try {
            // 记录发送 ping 的时间
            lastPingSentTime[client] = now;
            client.add(pingMessage);
          } catch (e) {
            log('发送 ping 消息失败: $e，将断开客户端连接');
            clientsToRemove.add(client);
          }
        }

        // 清理发送失败的客户端
        for (var client in clientsToRemove) {
          handleClientDisconnect(client);
        }

        log('已向 ${clients.length} 个客户端发送 ping 消息');
      });

      // 启动连接检查定时器（每15秒检查一次）
      connectionCheckTimer = Timer.periodic(const Duration(seconds: 15), (timer) {
        if (clients.isEmpty) return;

        final now = DateTime.now();
        final clientsToRemove = <WebSocket>[];

        for (var client in clients) {
          // 获取上次发送 ping 的时间
          final lastPingTime = lastPingSentTime[client];
          if (lastPingTime == null) continue;

          // 获取上次接收 pong 的时间
          final lastPongTime = lastPongReceivedTime[client];

          // 如果从未收到过 pong，且 ping 发送超过 45 秒，则认为客户端已断开
          if (lastPongTime == null) {
            final pingAge = now.difference(lastPingTime).inSeconds;
            if (pingAge > 45) {
              log('客户端 ${clientIPs[client] ?? "未知IP"} 从未响应 ping，已发送 ping $pingAge 秒，认为已断开连接');
              clientsToRemove.add(client);
            }
            continue;
          }

          // 如果最后一次 pong 接收时间早于最后一次 ping 发送时间，且间隔超过 45 秒，则认为客户端已断开
          if (lastPongTime.isBefore(lastPingTime)) {
            final pingAge = now.difference(lastPingTime).inSeconds;
            if (pingAge > 45) {
              log('客户端 ${clientIPs[client] ?? "未知IP"} 未响应最近的 ping，已发送 ping $pingAge 秒，认为已断开连接');
              clientsToRemove.add(client);
            }
          }
        }

        // 清理未响应的客户端
        for (var client in clientsToRemove) {
          try {
            client.close();
          } catch (e) {
            log('关闭未响应客户端连接失败: $e');
          }
          handleClientDisconnect(client);
        }

        if (clientsToRemove.isNotEmpty) {
          log('已清理 ${clientsToRemove.length} 个未响应的客户端');
        }
      });
    }

    // 监听来自主 Isolate 的命令
    receivePort.listen((message) async {
      if (message is! Map) return;

      final type = message['type'];
      if (type is! String) return;

      final data = message['data'];
      if (data is! Map) return;

      switch (type) {
        case 'start':
          final port = data['port'] is int ? data['port'] as int : null;
          password = data['password'] is String ? data['password'] as String : null;
          requirePassword = data['requirePassword'] is bool ? data['requirePassword'] as bool : false;

          if (port == null) {
            sendError('启动参数无效');
            return;
          }

          // 如果服务器已经在运行，先停止
          if (server != null) {
            await server!.close(force: true);
            server = null;

            // 清理客户端列表
            for (var client in clients) {
              await client.close();
            }
            clients.clear();
            clientIPs.clear();
            authenticatedClients.clear();
            ipToClient.clear();

            // 取消定时器
            pingTimer?.cancel();
            pingTimer = null;
            connectionCheckTimer?.cancel();
            connectionCheckTimer = null;
          }

          // 更新状态为启动中
          updateStatus(IsolateSocketServerStatus.starting);

          try {
            // 创建 HTTP 服务器
            server = await HttpServer.bind(InternetAddress.anyIPv4, port);

            // 监听 HTTP 请求
            server!.listen((request) {
              if (WebSocketTransformer.isUpgradeRequest(request)) {
                handleWebSocketRequest(request);
              } else {
                request.response.statusCode = HttpStatus.forbidden;
                request.response.close();
              }
            });

            // 启动 ping 定时器
            startPingTimer();

            // 更新状态为运行中
            updateStatus(IsolateSocketServerStatus.running);

            // 通知主 Isolate 服务器已启动
            mainSendPort.send({
              'type': 'started',
              'data': {
                'port': port,
              },
            });

            log('服务器已启动，监听端口: $port');
          } catch (e) {
            log('启动服务器错误: $e');
            sendError('启动服务器错误: $e');
            updateStatus(IsolateSocketServerStatus.error);
          }
          break;

        case 'stop':
          if (server != null) {
            // 停止服务器
            await server!.close(force: true);
            server = null;

            // 清理客户端列表
            for (var client in clients) {
              await client.close();
            }
            clients.clear();
            clientIPs.clear();
            authenticatedClients.clear();
            ipToClient.clear();

            // 取消定时器
            pingTimer?.cancel();
            pingTimer = null;
            connectionCheckTimer?.cancel();
            connectionCheckTimer = null;

            // 更新状态为已停止
            updateStatus(IsolateSocketServerStatus.stopped);

            // 通知主 Isolate 服务器已停止
            mainSendPort.send({
              'type': 'stopped',
              'data': {},
            });

            log('服务器已停止');
          }
          break;

        case 'send_to_all':
          final content = data['content'] is String ? data['content'] as String : null;

          if (content != null && clients.isNotEmpty) {
            final contentMessage = jsonEncode({
              'type': 'content',
              'content': content,
            });

            for (var client in clients) {
              // 检查是否已认证
              if (!requirePassword || authenticatedClients.contains(client)) {
                try {
                  client.add(contentMessage);
                } catch (e) {
                  log('发送内容到客户端失败: $e');
                }
              }
            }

            log('已向 ${clients.length} 个客户端发送内容，内容长度: ${content.length}');
          }
          break;

        case 'send_to_client':
          final clientIP = data['clientIP'] is String ? data['clientIP'] as String : null;
          final content = data['content'] is String ? data['content'] as String : null;

          if (clientIP != null && content != null) {
            final client = ipToClient[clientIP];

            if (client != null) {
              // 检查是否已认证
              if (!requirePassword || authenticatedClients.contains(client)) {
                try {
                  client.add(jsonEncode({
                    'type': 'content',
                    'content': content,
                  }));

                  log('已向客户端 $clientIP 发送内容，内容长度: ${content.length}');
                } catch (e) {
                  log('发送内容到客户端 $clientIP 失败: $e');
                }
              } else {
                log('客户端 $clientIP 未认证，无法发送内容');
              }
            } else {
              log('客户端 $clientIP 不存在或已断开连接');
            }
          }
          break;

        case 'disconnect_client':
          final clientIP = data['clientIP'] is String ? data['clientIP'] as String : null;

          if (clientIP != null) {
            final client = ipToClient[clientIP];

            if (client != null) {
              try {
                await client.close();

                // 从列表中移除（handleClientDisconnect 会处理剩余的清理工作）
                handleClientDisconnect(client);

                log('已断开客户端 $clientIP 的连接');
              } catch (e) {
                log('断开客户端 $clientIP 连接失败: $e');
              }
            } else {
              log('客户端 $clientIP 不存在或已断开连接');
            }
          }
          break;
      }
    });
  }
}
