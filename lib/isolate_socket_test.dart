import 'package:flutter/material.dart';
import 'isolate_socket_client.dart';
import 'isolate_socket_service.dart';

class IsolateSocketTestPage extends StatefulWidget {
  const IsolateSocketTestPage({super.key});

  @override
  State<IsolateSocketTestPage> createState() => _IsolateSocketTestPageState();
}

class _IsolateSocketTestPageState extends State<IsolateSocketTestPage> {
  // 服务端实例
  final _server = IsolateSocketServer();

  // 客户端实例
  final _client = IsolateSocketClient();

  // 日志
  final List<String> _logs = [];

  // 控制器
  final TextEditingController _portController = TextEditingController(text: '8080');
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _contentController = TextEditingController();

  @override
  void initState() {
    super.initState();

    // 监听服务端事件
    _server.events.listen((event) {
      _addLog('服务端事件: ${event.type}, 客户端: ${event.clientIP ?? "无"}, 内容长度: ${event.content?.length ?? 0}');

      // 如果收到获取内容请求，发送内容
      if (event.type == IsolateSocketServerEventType.fetch) {
        _server.sendContentToClient(
          event.clientIP!,
          'Hello from server! Time: ${DateTime.now()}',
        );
      }
    });

    // 监听客户端事件
    _client.events.listen((event) {
      _addLog('客户端事件: ${event.type}, 内容长度: ${event.content?.length ?? 0}');
    });
  }

  @override
  void dispose() {
    // 释放资源
    _server.dispose();
    _client.dispose();

    // 释放控制器
    _portController.dispose();
    _passwordController.dispose();
    _contentController.dispose();

    super.dispose();
  }

  // 添加日志
  void _addLog(String log) {
    setState(() {
      _logs.add('${DateTime.now().toString().substring(11, 19)} $log');
      if (_logs.length > 100) {
        _logs.removeAt(0);
      }
    });
  }

  // 启动服务器
  Future<void> _startServer() async {
    final port = int.tryParse(_portController.text) ?? 8080;
    final password = _passwordController.text.isEmpty ? null : _passwordController.text;

    _addLog('正在启动服务器，端口: $port, 密码: ${password ?? "无"}');

    final success = await _server.startServer(
      port: port,
      password: password,
      requirePassword: password != null,
    );

    _addLog('服务器启动${success ? "成功" : "失败"}');
  }

  // 停止服务器
  Future<void> _stopServer() async {
    _addLog('正在停止服务器');
    await _server.stopServer();
    _addLog('服务器已停止');
  }

  // 连接到服务器
  Future<void> _connectToServer() async {
    final port = int.tryParse(_portController.text) ?? 8080;
    final password = _passwordController.text.isEmpty ? null : _passwordController.text;

    _addLog('正在连接到服务器，端口: $port, 密码: ${password ?? "无"}');

    final success = await _client.connect(
      'localhost',
      port,
      password: password,
    );

    _addLog('连接${success ? "成功" : "失败"}');
  }

  // 断开连接
  Future<void> _disconnect() async {
    _addLog('正在断开连接');
    await _client.disconnect();
    _addLog('已断开连接');
  }

  // 获取内容
  void _fetchContent() {
    _addLog('正在获取内容');
    _client.fetchContent();
  }

  // 推送内容
  void _pushContent() {
    final content = _contentController.text;
    if (content.isEmpty) {
      _addLog('内容不能为空');
      return;
    }

    _addLog('正在推送内容，长度: ${content.length}');
    _client.pushContent(content);
    _contentController.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Isolate Socket Test'),
      ),
      body: Column(
        children: [
          // 配置区域
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _portController,
                        decoration: const InputDecoration(
                          labelText: '端口',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextField(
                        controller: _passwordController,
                        decoration: const InputDecoration(
                          labelText: '密码（可选）',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _server.status.value == IsolateSocketServerStatus.running
                            ? _stopServer
                            : _startServer,
                        child: Text(_server.status.value == IsolateSocketServerStatus.running
                            ? '停止服务器'
                            : '启动服务器'),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _client.status.value == IsolateSocketStatus.connected
                            ? _disconnect
                            : _connectToServer,
                        child: Text(_client.status.value == IsolateSocketStatus.connected
                            ? '断开连接'
                            : '连接到服务器'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _client.status.value == IsolateSocketStatus.connected
                            ? _fetchContent
                            : null,
                        child: const Text('获取内容'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _contentController,
                        decoration: const InputDecoration(
                          labelText: '内容',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    ElevatedButton(
                      onPressed: _client.status.value == IsolateSocketStatus.connected
                          ? _pushContent
                          : null,
                      child: const Text('推送内容'),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // 状态区域
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              children: [
                Expanded(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Column(
                        children: [
                          const Text('服务端状态'),
                          ValueListenableBuilder<IsolateSocketServerStatus>(
                            valueListenable: _server.status,
                            builder: (context, status, child) {
                              return Text(
                                status.toString().split('.').last,
                                style: TextStyle(
                                  color: status == IsolateSocketServerStatus.running
                                      ? Colors.green
                                      : status == IsolateSocketServerStatus.error
                                          ? Colors.red
                                          : Colors.black,
                                  fontWeight: FontWeight.bold,
                                ),
                              );
                            },
                          ),
                          ValueListenableBuilder<int>(
                            valueListenable: _server.clientCountNotifier,
                            builder: (context, count, child) {
                              return Text('客户端数量: $count');
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Column(
                        children: [
                          const Text('客户端状态'),
                          ValueListenableBuilder<IsolateSocketStatus>(
                            valueListenable: _client.status,
                            builder: (context, status, child) {
                              return Text(
                                status.toString().split('.').last,
                                style: TextStyle(
                                  color: status == IsolateSocketStatus.connected
                                      ? Colors.green
                                      : status == IsolateSocketStatus.error
                                          ? Colors.red
                                          : Colors.black,
                                  fontWeight: FontWeight.bold,
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 日志区域
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('日志'),
                          IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              setState(() {
                                _logs.clear();
                              });
                            },
                          ),
                        ],
                      ),
                      Expanded(
                        child: ListView.builder(
                          itemCount: _logs.length,
                          itemBuilder: (context, index) {
                            return Text(_logs[_logs.length - 1 - index]);
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
