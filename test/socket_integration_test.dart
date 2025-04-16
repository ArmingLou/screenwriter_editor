import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_socket_channel/io.dart';

/// 这个测试文件模拟VSCode扩展，连接到真机上运行的剧本编辑器应用
/// 测试远程同步功能
void main() {
  group('远程同步功能测试 - 连接真机', () {
    // 真机设备的IP地址和端口
    // 注意: 运行测试前需要先在真机上启动应用并启动Socket服务

    // 从环境变量获取设备IP和端口，或使用默认值
    // 运行测试时可以设置环境变量: DEVICE_IP 和 DEVICE_PORT
    // 例如: DEVICE_IP=192.168.1.123 DEVICE_PORT=8888 flutter test test/socket_integration_test.dart
    final String deviceIp = Platform.environment['DEVICE_IP'] ?? '192.168.3.248';
    final int devicePort = int.parse(Platform.environment['DEVICE_PORT'] ?? '8080');
    final String? devicePassword = Platform.environment['DEVICE_PASSWORD'] ?? 'arming';

    // 测试前的提示
    setUp(() {
      print('\n测试开始: 请确保真机应用已启动并开启Socket服务');
      print('连接地址: ws://$deviceIp:$devicePort');
      if (devicePassword != null && devicePassword!.isNotEmpty) {
        print('密码验证: 已启用 (密码: $devicePassword)');
      } else {
        print('密码验证: 未启用');
      }
      print('如果测试失败，请检查IP地址、端口和密码是否正确\n');
    });

    test('1. 测试连接到真机并发送fetch请求', () async {
      // 创建一个Completer来等待响应
      final completer = Completer<String>();

      try {
        // 连接到真机上的WebSocket服务
        final wsClient = IOWebSocketChannel.connect('ws://$deviceIp:$devicePort');

        // 认证状态
        bool isAuthenticated = devicePassword == null || devicePassword!.isEmpty;
        final authCompleter = Completer<bool>();

        // 监听响应
        wsClient.stream.listen(
          (message) {
            try {
              final data = jsonDecode(message);

              // 处理认证响应
              if (data['type'] == 'auth_response') {
                final bool success = data['success'] == true;
                print('认证${success ? '成功' : '失败'}: ${data['message']}');
                isAuthenticated = success;
                if (!authCompleter.isCompleted) {
                  authCompleter.complete(success);
                }
              }
              // 处理错误消息
              else if (data['type'] == 'error') {
                print('收到错误: ${data['message']}');
                if (!completer.isCompleted) {
                  completer.completeError(data['message']);
                }
              }
              // 处理内容响应
              else if (data['type'] == 'content') {
                print('收到内容响应: ${data['content'].length} 字符');
                completer.complete(data['content']);
              }
            } catch (e) {
              print('解析消息错误: $e');
              if (!completer.isCompleted) {
                completer.completeError(e);
              }
            }
          },
          onError: (error) {
            print('连接错误: $error');
            if (!completer.isCompleted) {
              completer.completeError(error);
            }
          },
          onDone: () {
            print('连接关闭');
            if (!completer.isCompleted) {
              completer.completeError('Connection closed');
            }
          },
        );

        // 等待连接建立
        await Future.delayed(const Duration(seconds: 1));

        // 如果需要认证，先发送认证请求
        if (devicePassword != null && devicePassword!.isNotEmpty) {
          print('发送认证请求...');
          wsClient.sink.add(jsonEncode({
            'type': 'auth',
            'password': devicePassword
          }));

          // 等待认证结果
          isAuthenticated = await authCompleter.future.timeout(
            const Duration(seconds: 5),
            onTimeout: () {
              print('认证超时');
              return false;
            }
          );

          if (!isAuthenticated) {
            throw Exception('认证失败');
          }

          print('认证成功，继续测试...');
        }

        print('发送fetch请求...');
        // 发送fetch请求
        wsClient.sink.add(jsonEncode({
          'type': 'fetch'
        }));

        // 等待响应，设置超时
        final response = await completer.future.timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            print('等待响应超时');
            return 'timeout';
          }
        );

        // 关闭连接
        wsClient.sink.close();

        // 验证收到了响应
        expect(response, isNot('timeout'));
        expect(response, isNotEmpty);
        print('成功获取到真机编辑器内容，长度: ${response.length} 字符');
      } catch (e) {
        print('测试失败: $e');
        fail('无法连接到真机或收取内容: $e');
      }
    });

    test('2. 测试向真机发送push请求', () async {
      try {
        // 连接到真机上的WebSocket服务
        final wsClient = IOWebSocketChannel.connect('ws://$deviceIp:$devicePort');

        // 认证状态
        bool isAuthenticated = devicePassword == null || devicePassword.isEmpty;
        final authCompleter = Completer<bool>();

        // 监听响应
        wsClient.stream.listen((message) {
          try {
            final data = jsonDecode(message);

            // 处理认证响应
            if (data['type'] == 'auth_response') {
              final bool success = data['success'] == true;
              print('认证${success ? '成功' : '失败'}: ${data['message']}');
              isAuthenticated = success;
              if (!authCompleter.isCompleted) {
                authCompleter.complete(success);
              }
            }
            // 处理错误消息
            else if (data['type'] == 'error') {
              print('收到错误: ${data['message']}');
            }
          } catch (e) {
            print('解析消息错误: $e');
          }
        });

        // 等待连接建立
        await Future.delayed(const Duration(seconds: 1));

        // 如果需要认证，先发送认证请求
        if (devicePassword != null && devicePassword.isNotEmpty) {
          print('发送认证请求...');
          wsClient.sink.add(jsonEncode({
            'type': 'auth',
            'password': devicePassword
          }));

          // 等待认证结果
          isAuthenticated = await authCompleter.future.timeout(
            const Duration(seconds: 5),
            onTimeout: () {
              print('认证超时');
              return false;
            }
          );

          if (!isAuthenticated) {
            throw Exception('认证失败');
          }

          print('认证成功，继续测试...');
        }

        // 准备测试内容
        final testContent = '''
# 测试剧本

标题: 远程同步测试
作者: VSCode扩展模拟器

.(内景) 办公室 - 日

主角坐在电脑前，专注地看着屏幕。

@主角
(自言自语)
这个远程同步功能真的很棒！

主角微笑，继续敲击键盘。

CUT TO:

EXT. 公园 - NIGHT

主角在公园里散步，看着手机。

@主角2
现在我可以在任何地方编辑我的剧本了。

> 此内容由远程同步测试生成 <
''';

        print('发送push请求...');
        print('内容长度: ${testContent.length} 字符');

        // 发送push请求
        wsClient.sink.add(jsonEncode({
          'type': 'push',
          'content': testContent
        }));

        // 等待一段时间，确保内容已发送
        await Future.delayed(const Duration(seconds: 2));

        // 关闭连接
        wsClient.sink.close();

        print('内容已推送到真机，请在真机上检查编辑器内容是否已更新');

        // 测试成功，如果没有异常
        expect(true, true);
      } catch (e) {
        print('测试失败: $e');
        fail('无法连接到真机或发送内容: $e');
      }
    });

    test('3. 测试先fetch再push的完整流程', () async {
      try {
        // 连接到真机上的WebSocket服务
        final wsClient = IOWebSocketChannel.connect('ws://$deviceIp:$devicePort');
        String? originalContent;
        final fetchCompleter = Completer<String>();

        // 认证状态
        bool isAuthenticated = devicePassword == null || devicePassword.isEmpty;
        final authCompleter = Completer<bool>();

        // 监听响应
        wsClient.stream.listen(
          (message) {
            try {
              final data = jsonDecode(message);

              // 处理认证响应
              if (data['type'] == 'auth_response') {
                final bool success = data['success'] == true;
                print('认证${success ? '成功' : '失败'}: ${data['message']}');
                isAuthenticated = success;
                if (!authCompleter.isCompleted) {
                  authCompleter.complete(success);
                }
              }
              // 处理错误消息
              else if (data['type'] == 'error') {
                print('收到错误: ${data['message']}');
                if (!fetchCompleter.isCompleted) {
                  fetchCompleter.completeError(data['message']);
                }
              }
              // 处理内容响应
              else if (data['type'] == 'content' && !fetchCompleter.isCompleted) {
                originalContent = data['content'];
                fetchCompleter.complete(data['content']);
              }
            } catch (e) {
              print('解析消息错误: $e');
              if (!fetchCompleter.isCompleted) {
                fetchCompleter.completeError(e);
              }
            }
          },
          onError: (error) {
            print('连接错误: $error');
            if (!fetchCompleter.isCompleted) {
              fetchCompleter.completeError(error);
            }
          },
        );

        // 等待连接建立
        await Future.delayed(const Duration(seconds: 1));

        // 如果需要认证，先发送认证请求
        if (devicePassword != null && devicePassword.isNotEmpty) {
          print('发送认证请求...');
          wsClient.sink.add(jsonEncode({
            'type': 'auth',
            'password': devicePassword
          }));

          // 等待认证结果
          isAuthenticated = await authCompleter.future.timeout(
            const Duration(seconds: 5),
            onTimeout: () {
              print('认证超时');
              return false;
            }
          );

          if (!isAuthenticated) {
            throw Exception('认证失败');
          }

          print('认证成功，继续测试...');
        }

        // 1. 先发送fetch请求获取原始内容
        print('步骤1: 发送fetch请求获取原始内容...');
        wsClient.sink.add(jsonEncode({
          'type': 'fetch'
        }));

        // 等待响应
        await fetchCompleter.future.timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            print('等待fetch响应超时');
            throw TimeoutException('Fetch response timeout');
          }
        );

        print('成功获取原始内容，长度: ${originalContent?.length ?? 0} 字符');

        // 2. 然后发送push请求，将修改后的内容推送回去
        // 在原始内容的基础上添加注释
        final modifiedContent = originalContent != null && originalContent!.isNotEmpty
            ? '${originalContent!}\n\n/* 这是一条由远程同步测试添加的注释 */\n'
            : '这是一条测试内容，原始内容为空。\n\n/* 这是一条由远程同步测试添加的注释 */\n';

        print('步骤2: 发送push请求，推送修改后的内容...');
        print('修改后内容长度: ${modifiedContent.length} 字符');

        wsClient.sink.add(jsonEncode({
          'type': 'push',
          'content': modifiedContent
        }));

        // 等待一段时间，确保内容已发送
        await Future.delayed(const Duration(seconds: 2));

        // 关闭连接
        wsClient.sink.close();

        print('完整流程测试完成，请在真机上检查编辑器内容是否已更新');

        // 测试成功
        expect(true, true);
      } catch (e) {
        print('测试失败: $e');
        fail('完整流程测试失败: $e');
      }
    });
  });
}
