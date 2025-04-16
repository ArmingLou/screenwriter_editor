import 'dart:convert';
import 'dart:io';
import 'package:web_socket_channel/io.dart';

/// 简单的PC客户端模拟器，用于测试与移动端的WebSocket通信
class PcClientSimulator {
  IOWebSocketChannel? _channel;
  bool _isConnected = false;
  
  /// 连接到移动端WebSocket服务器
  Future<bool> connect(String host, int port) async {
    try {
      _channel = IOWebSocketChannel.connect('ws://$host:$port');
      
      // 设置消息监听
      _channel!.stream.listen(
        (message) {
          _handleMessage(message);
        },
        onDone: () {
          print('连接已关闭');
          _isConnected = false;
        },
        onError: (error) {
          print('连接错误: $error');
          _isConnected = false;
        }
      );
      
      _isConnected = true;
      print('已连接到 ws://$host:$port');
      return true;
    } catch (e) {
      print('连接失败: $e');
      return false;
    }
  }
  
  /// 处理接收到的消息
  void _handleMessage(dynamic message) {
    try {
      final data = jsonDecode(message);
      if (data['type'] == 'content') {
        print('\n接收到内容:');
        print('----------------------------------------');
        print(data['content']);
        print('----------------------------------------');
      } else {
        print('接收到消息: $message');
      }
    } catch (e) {
      print('处理消息错误: $e');
    }
  }
  
  /// 发送fetch请求，获取移动端编辑器内容
  void fetchContent() {
    if (!_isConnected || _channel == null) {
      print('未连接，请先连接到服务器');
      return;
    }
    
    _channel!.sink.add(jsonEncode({
      'type': 'fetch'
    }));
    print('已发送fetch请求');
  }
  
  /// 发送push请求，将内容推送到移动端编辑器
  void pushContent(String content) {
    if (!_isConnected || _channel == null) {
      print('未连接，请先连接到服务器');
      return;
    }
    
    _channel!.sink.add(jsonEncode({
      'type': 'push',
      'content': content
    }));
    print('已发送push请求，内容长度: ${content.length}字符');
  }
  
  /// 关闭连接
  void disconnect() {
    if (_channel != null) {
      _channel!.sink.close();
      _channel = null;
      _isConnected = false;
      print('已断开连接');
    }
  }
  
  /// 检查是否已连接
  bool get isConnected => _isConnected;
}

/// 交互式命令行界面
void main() async {
  final simulator = PcClientSimulator();
  
  print('=== 剧本编辑器 PC客户端模拟器 ===');
  print('用于测试与移动端的WebSocket通信');
  
  String? host;
  int? port;
  
  // 获取连接信息
  stdout.write('请输入服务器IP地址 (默认: localhost): ');
  host = stdin.readLineSync()?.trim();
  if (host == null || host.isEmpty) {
    host = 'localhost';
  }
  
  stdout.write('请输入端口号 (默认: 8080): ');
  final portInput = stdin.readLineSync()?.trim();
  if (portInput != null && portInput.isNotEmpty) {
    port = int.tryParse(portInput);
  }
  port ??= 8080;
  
  // 尝试连接
  print('正在连接到 ws://$host:$port...');
  final connected = await simulator.connect(host, port);
  
  if (!connected) {
    print('连接失败，请检查服务器是否已启动');
    exit(1);
  }
  
  // 命令循环
  while (simulator.isConnected) {
    print('\n可用命令:');
    print('1. fetch - 获取移动端编辑器内容');
    print('2. push - 推送内容到移动端编辑器');
    print('3. exit - 退出程序');
    
    stdout.write('请输入命令: ');
    final command = stdin.readLineSync()?.trim().toLowerCase();
    
    switch (command) {
      case 'fetch':
      case '1':
        simulator.fetchContent();
        break;
        
      case 'push':
      case '2':
        print('请输入要推送的内容 (输入END单独一行结束):');
        final buffer = StringBuffer();
        String? line;
        while ((line = stdin.readLineSync()) != 'END') {
          buffer.writeln(line);
        }
        simulator.pushContent(buffer.toString());
        break;
        
      case 'exit':
      case '3':
        simulator.disconnect();
        print('程序已退出');
        exit(0);
        
      default:
        print('未知命令: $command');
    }
  }
  
  print('连接已断开，程序退出');
}
