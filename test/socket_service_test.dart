import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_socket_channel/io.dart';
import 'package:screenwriter_editor/socket_service.dart';

void main() {
  group('SocketService 测试', () {
    late SocketService socketService;
    final int testPort = 8088; // 使用不同于默认端口的测试端口

    setUp(() {
      socketService = SocketService();
    });

    tearDown(() async {
      await socketService.stopServer();
    });

    test('服务器启动和停止', () async {
      // 启动服务器
      final startResult = await socketService.startServer(testPort);
      expect(startResult, true);
      expect(socketService.status.value, SocketServiceStatus.running);
      expect(socketService.currentPort, testPort);

      // 停止服务器
      await socketService.stopServer();
      expect(socketService.status.value, SocketServiceStatus.stopped);
      expect(socketService.currentPort, null);
    });

    test('模拟PC端发送fetch请求', () async {
      // 启动服务器
      await socketService.startServer(testPort);

      // 监听事件
      bool fetchReceived = false;
      socketService.events.listen((event) {
        if (event.type == SocketEventType.fetch) {
          fetchReceived = true;

          // 发送响应
          socketService.sendContent('测试内容', event.socket);
        }
      });

      // 模拟PC端连接
      final wsClient = IOWebSocketChannel.connect('ws://localhost:$testPort');

      // 发送fetch请求
      wsClient.sink.add(jsonEncode({'type': 'fetch'}));

      // 等待响应
      String? response;
      wsClient.stream.listen((message) {
        final data = jsonDecode(message);
        if (data['type'] == 'content') {
          response = data['content'];
        }
      });

      // 等待处理
      await Future.delayed(Duration(seconds: 1));

      // 验证
      expect(fetchReceived, true);
      expect(response, '测试内容');

      // 关闭连接
      wsClient.sink.close();
    });

    test('模拟PC端发送push请求', () async {
      // 启动服务器
      await socketService.startServer(testPort);

      // 监听事件
      String? pushedContent;
      socketService.events.listen((event) {
        if (event.type == SocketEventType.push) {
          pushedContent = event.content;
        }
      });

      // 模拟PC端连接
      final wsClient = IOWebSocketChannel.connect('ws://localhost:$testPort');

      // 发送push请求
      final testContent = '从PC端推送的测试内容';
      wsClient.sink.add(jsonEncode({'type': 'push', 'content': testContent}));

      // 等待处理
      await Future.delayed(Duration(seconds: 1));

      // 验证
      expect(pushedContent, testContent);

      // 关闭连接
      wsClient.sink.close();
    });
  });
}
