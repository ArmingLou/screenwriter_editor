import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// 认证工具类，用于处理密码哈希和 token 生成
class AuthUtils {
  /// 固定的盐值，客户端和服务端共享
  /// 注意：在实际生产环境中，应该使用更安全的方式来管理盐值
  static const String fixedSalt = 'screenwriter_fixed_salt_value_2024';

  /// 从 SharedPreferences 获取自定义盐值
  /// 如果没有启用自定义盐值，则返回 fixedSalt
  static Future<String> getSalt() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool('custom_salt_enabled') ?? false;
    if (enabled) {
      final customSalt = prefs.getString('custom_salt');
      if (customSalt != null && customSalt.isNotEmpty) {
        return customSalt;
      }
    }
    return fixedSalt;
  }

  // 缓存的盐值，用于同步方法
  static String? _cachedSalt;

  /// 预加载盐值，应在应用启动时调用
  /// [forceReload] 是否强制重新加载盐值，忽略缓存
  static Future<void> preloadSalt({bool forceReload = false}) async {
    if (forceReload || _cachedSalt == null) {
      _cachedSalt = await getSalt();
    }
  }

  /// 清除缓存的盐值，在修改自定义盐值后调用
  static void clearCachedSalt() {
    _cachedSalt = null;
  }

  /// 同步方式获取盐值，用于不方便使用异步方法的场景
  /// 注意：这个方法返回缓存的盐值，如果缓存不存在则返回固定盐值
  /// 应该在应用启动时调用 preloadSalt() 来初始化缓存
  static String getSaltSync() {
    return _cachedSalt ?? fixedSalt;
  }
  /// 生成随机盐值
  static String generateSalt() {
    final random = Random.secure();
    final values = List<int>.generate(16, (i) => random.nextInt(256));
    return base64Url.encode(values);
  }

  /// 使用 SHA-256 哈希密码
  static String hashPassword(String password, String salt) {
    final bytes = utf8.encode(password + salt);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// 生成认证 token
  ///
  /// [password] 密码
  /// [salt] 盐值
  /// [timestamp] 时间戳，用于增加 token 的唯一性
  static String generateToken(String password, String salt, int timestamp) {
    final hash = hashPassword(password, salt);
    final tokenData = '$hash:$timestamp';
    final tokenBytes = utf8.encode(tokenData);
    final tokenDigest = sha256.convert(tokenBytes);
    return tokenDigest.toString();
  }

  /// 验证 token
  ///
  /// [token] 客户端提供的 token
  /// [password] 服务器存储的密码
  /// [salt] 盐值
  /// [timestamp] 时间戳，应该与生成 token 时使用的相同
  static bool verifyToken(String token, String password, String salt, int timestamp) {
    final expectedToken = generateToken(password, salt, timestamp);
    return token == expectedToken;
  }
}
