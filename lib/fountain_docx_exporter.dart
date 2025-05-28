import 'src/rust/api.dart/frb_generated.dart';
import 'src/rust/api.dart/api/docx_export.dart' as rust_api;

// 导出生成的类型供外部使用
export 'src/rust/api.dart/api/docx_export.dart';

/// Fountain DOCX 导出器
class FountainDocxExporter {
  static bool _initialized = false;

  FountainDocxExporter() {
    _initRustLib();
  }

  static Future<void> _initRustLib() async {
    if (!_initialized) {
      await RustLib.init();
      _initialized = true;
    }
  }

  /// 测试连接
  String testRustConnection() {
    try {
      // 调用Rust函数
      return rust_api.testConnection();
    } catch (e) {
      return "Connection failed: $e";
    }
  }

  /// 导出DOCX文档
  Future<rust_api.ExportResult> exportToDocx(
    String fountainText,
    String outputPath, {
    rust_api.SimpleConf? config,
  }) async {
    try {
      await _initRustLib();

      // 调用Rust的导出函数
      return await rust_api.exportToDocx(
        text: fountainText,
        outputPath: outputPath,
        config: config,
      );
    } catch (e) {
      return const rust_api.ExportResult(
        success: false,
        message: "导出失败",
        filePath: null,
      );
    }
  }

  /// 解析Fountain文本
  Future<rust_api.ParseResult> parseFountainText(
    String fountainText, {
    rust_api.SimpleConf? config,
  }) async {
    try {
      await _initRustLib();

      // 调用Rust的解析函数
      return await rust_api.parseFountainText(
        text: fountainText,
        config: config,
      );
    } catch (e) {
      return const rust_api.ParseResult(
        success: false,
        message: '解析失败',
        pageCount: 0,
        characterCount: 0,
        wordCount: 0,
      );
    }
  }

  /// 创建默认配置
  rust_api.SimpleConf createDefaultConfig() {
    return rust_api.createDefaultConfig();
  }

  /// 创建中文配置
  rust_api.SimpleConf createChineseConfig() {
    return rust_api.createChineseConfig();
  }

  /// 创建英文配置
  rust_api.SimpleConf createEnglishConfig() {
    return rust_api.createEnglishConfig();
  }
}
