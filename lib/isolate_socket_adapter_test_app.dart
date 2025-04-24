import 'package:flutter/material.dart';
import 'isolate_socket_service_adapter.dart';
import 'isolate_socket_client_adapter.dart';

void main() {
  runApp(const IsolateSocketAdapterTestApp());
}

class IsolateSocketAdapterTestApp extends StatelessWidget {
  const IsolateSocketAdapterTestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Isolate Socket Adapter Test',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const IsolateSocketAdapterTestPage(),
    );
  }
}

class IsolateSocketAdapterTestPage extends StatefulWidget {
  const IsolateSocketAdapterTestPage({super.key});

  @override
  State<IsolateSocketAdapterTestPage> createState() => _IsolateSocketAdapterTestPageState();
}

class _IsolateSocketAdapterTestPageState extends State<IsolateSocketAdapterTestPage> {
  // Socket 服务和客户端
  final SocketService _server = SocketService();
  final SocketClient _client = SocketClient();

  // 服务器配置
  final int _serverPort = 8080;
  final String _serverPassword = 'test123';

  // 客户端配置
  final RemoteServerConfig _clientConfig = RemoteServerConfig(
    name: 'Test Server',
    host: '127.0.0.1', // 使用IP地址而不是hostname
    port: 8080,
    password: 'test123',
  );

  // 编辑器内容
  String _editorContent = 'Hello, World!';

  // 服务器事件日志
  final List<String> _serverLogs = [];

  // 客户端事件日志
  final List<String> _clientLogs = [];

  @override
  void initState() {
    super.initState();

    // 监听服务器事件
    _server.events.listen((event) {
      setState(() {
        _serverLogs.add('服务器事件: ${event.type}, 内容: ${event.content}');
      });

      // 处理获取内容请求
      if (event.type == SocketEventType.fetch && event.socket != null) {
        _server.sendContent(_editorContent, event.socket);
      }

      // 处理推送内容请求
      if (event.type == SocketEventType.push && event.content != null) {
        setState(() {
          _editorContent = event.content!;
          _serverLogs.add('编辑器内容已更新: $_editorContent');
        });
      }
    });

    // 监听客户端事件
    _client.events.listen((event) {
      setState(() {
        _clientLogs.add('客户端事件: ${event.type}, 内容: ${event.content}, 错误: ${event.errorMessage}');
      });

      // 处理接收到内容
      if (event.type == SocketClientEventType.content && event.content != null) {
        setState(() {
          _editorContent = event.content!;
          _clientLogs.add('编辑器内容已更新: $_editorContent');
        });
      }
    });

    // 监听服务器状态变化
    _server.status.addListener(() {
      setState(() {
        _serverLogs.add('服务器状态变化: ${_server.status.value}');
      });
    });

    // 监听客户端状态变化
    _client.status.addListener(() {
      setState(() {
        _clientLogs.add('客户端状态变化: ${_client.status.value}');
      });
    });
  }

  @override
  void dispose() {
    // 停止服务器
    _server.stopServer();

    // 断开客户端连接
    _client.disconnect();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Isolate Socket Adapter Test'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 服务器控制
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('服务器控制', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        ValueListenableBuilder<SocketServiceStatus>(
                          valueListenable: _server.status,
                          builder: (context, status, child) {
                            return Text('状态: $status');
                          },
                        ),
                        const SizedBox(width: 16),
                        Text('客户端数量: ${_server.clientCount}'),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        ElevatedButton(
                          onPressed: _server.status.value == SocketServiceStatus.running
                              ? null
                              : () async {
                                  final success = await _server.startServer(
                                    _serverPort,
                                    password: _serverPassword,
                                  );
                                  if (!success) {
                                    setState(() {
                                      _serverLogs.add('启动服务器失败: ${_server.errorMessage}');
                                    });
                                  }
                                },
                          child: const Text('启动服务器'),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: _server.status.value != SocketServiceStatus.running
                              ? null
                              : () async {
                                  await _server.stopServer();
                                },
                          child: const Text('停止服务器'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // 客户端控制
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('客户端控制', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    ValueListenableBuilder<SocketClientStatus>(
                      valueListenable: _client.status,
                      builder: (context, status, child) {
                        return Text('状态: $status');
                      },
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        ElevatedButton(
                          onPressed: _client.status.value == SocketClientStatus.connected
                              ? null
                              : () async {
                                  final success = await _client.connect(_clientConfig);
                                  if (!success) {
                                    setState(() {
                                      _clientLogs.add('连接服务器失败: ${_client.errorMessage}');
                                    });
                                  }
                                },
                          child: const Text('连接服务器'),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: _client.status.value != SocketClientStatus.connected
                              ? null
                              : () async {
                                  await _client.disconnect();
                                },
                          child: const Text('断开连接'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        ElevatedButton(
                          onPressed: _client.status.value != SocketClientStatus.connected
                              ? null
                              : () {
                                  _client.fetchContent();
                                },
                          child: const Text('获取内容'),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: _client.status.value != SocketClientStatus.connected
                              ? null
                              : () {
                                  final newContent = '$_editorContent (已修改)';
                                  _client.pushContent(newContent);
                                },
                          child: const Text('推送内容'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // 编辑器内容
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('编辑器内容', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8.0),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey),
                        borderRadius: BorderRadius.circular(4.0),
                      ),
                      child: Text(_editorContent),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // 服务器日志
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('服务器日志', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            setState(() {
                              _serverLogs.clear();
                            });
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      height: 200,
                      padding: const EdgeInsets.all(8.0),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey),
                        borderRadius: BorderRadius.circular(4.0),
                      ),
                      child: ListView.builder(
                        itemCount: _serverLogs.length,
                        itemBuilder: (context, index) {
                          return Text(_serverLogs[index]);
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // 客户端日志
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('客户端日志', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            setState(() {
                              _clientLogs.clear();
                            });
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      height: 200,
                      padding: const EdgeInsets.all(8.0),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey),
                        borderRadius: BorderRadius.circular(4.0),
                      ),
                      child: ListView.builder(
                        itemCount: _clientLogs.length,
                        itemBuilder: (context, index) {
                          return Text(_clientLogs[index]);
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
