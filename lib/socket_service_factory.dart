import 'isolate_socket_service_adapter.dart';
import 'isolate_socket_client_adapter.dart';

/// Socket 服务工厂类
class SocketServiceFactory {
  // 单例模式
  static final SocketServiceFactory _instance = SocketServiceFactory._internal();
  factory SocketServiceFactory() => _instance;
  SocketServiceFactory._internal();
  
  // 使用 Isolate 版本的 Socket 服务
  static bool _useIsolateVersion = true;
  
  /// 设置是否使用 Isolate 版本的 Socket 服务
  static void setUseIsolateVersion(bool useIsolate) {
    _useIsolateVersion = useIsolate;
  }
  
  /// 获取 Socket 服务实例
  static SocketService getSocketService() {
    // 始终返回 Isolate 版本的 Socket 服务
    return SocketService();
  }
  
  /// 获取 Socket 客户端实例
  static SocketClient getSocketClient() {
    // 始终返回 Isolate 版本的 Socket 客户端
    return SocketClient();
  }
}
