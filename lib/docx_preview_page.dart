import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:screenwriter_editor/bridge_generated.dart/api/docx_export.dart';
import 'package:screenwriter_editor/bridge_generated.dart/frb_generated.dart';
// 外部程序打开文件
import 'package:open_file/open_file.dart';
// Microsoft文档预览库
import 'package:microsoft_viewer/microsoft_viewer.dart';

class DocxPreviewPage extends StatefulWidget {
  final String fountainText;
  final String title;

  const DocxPreviewPage({
    Key? key,
    required this.fountainText,
    required this.title,
  }) : super(key: key);

  @override
  State<DocxPreviewPage> createState() => _DocxPreviewPageState();
}

class _DocxPreviewPageState extends State<DocxPreviewPage> {
  bool _isLoading = true;
  String? _errorMessage;
  Uint8List? _docxBytes;
  SimpleConf? _config;
  ParseResult? _parseResult;
  File? _tempFile; // 临时文件，用于保存
  bool _showPreview = true; // 是否显示内置预览

  @override
  void initState() {
    super.initState();
    _initializeAndGeneratePreview();
  }

  @override
  void dispose() {
    // 页面销毁时删除临时文件
    _cleanupTempFile();
    super.dispose();
  }

  Future<void> _cleanupTempFile() async {
    if (_tempFile != null && await _tempFile!.exists()) {
      try {
        await _tempFile!.delete();
        print('临时文件已删除: ${_tempFile!.path}');
      } catch (e) {
        print('删除临时文件失败: $e');
      }
    }
  }

  Future<void> _initializeAndGeneratePreview() async {
    // 初始化Rust库（如果尚未初始化）
    try {
      await RustLib.init();
    } catch (e) {
      // 如果已经初始化过，忽略错误
      print('RustLib already initialized: $e');
    }
    _generatePreview();
  }

  Future<void> _generatePreview() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      // 创建中文配置
      _config = await createChineseConfig();

      // 解析文本获取统计信息
      _parseResult = await parseFountainTextWithStats(text: widget.fountainText);

      // 生成临时DOCX文件
      final tempDir = Directory.systemTemp;
      _tempFile = File('${tempDir.path}/preview_${DateTime.now().millisecondsSinceEpoch}.docx');

      final exportResult = await exportToDocx(
        text: widget.fountainText,
        outputPath: _tempFile!.path,
        config: _config!,
      );

      if (exportResult.success) {
        // 读取文件内容
        _docxBytes = await _tempFile!.readAsBytes();

        // 不删除临时文件，保留用于预览
        // 临时文件将在页面销毁时删除

        setState(() {
          _isLoading = false;
        });
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = '生成预览失败: ${exportResult.message}';
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = '生成预览时发生错误: $e';
      });
    }
  }

  Future<void> _saveToFile() async {
    if (_docxBytes == null) {
      _showError('没有可保存的文档数据');
      return;
    }

    try {
      // 生成默认文件名
      String defaultFileName = 'screenplay';
      if (widget.title.isNotEmpty) {
        String fileName = widget.title;
        if (fileName.contains('/')) {
          fileName = fileName.split('/').last;
        }
        if (fileName.contains('\\')) {
          fileName = fileName.split('\\').last;
        }
        if (fileName.contains('.')) {
          fileName = fileName.split('.').first;
        }
        if (fileName.isNotEmpty) {
          defaultFileName = fileName;
        }
      }

      // 使用FilePicker选择保存位置
      await FilePicker.platform.clearTemporaryFiles();
      final result = await FilePicker.platform.saveFile(
        dialogTitle: '保存DOCX文档',
        fileName: '$defaultFileName.docx',
        allowedExtensions: ['docx'],
        type: FileType.custom,
        lockParentWindow: true,
        bytes: _docxBytes,
      );

      if (result == null) {
        // 用户取消了保存
        return;
      }

      // 确保文件扩展名为.docx
      String outputPath = result;
      if (!outputPath.toLowerCase().endsWith('.docx')) {
        outputPath = '$outputPath.docx';
      }

      _showInfo('正在保存DOCX文档...');

      // 写入文件
      final file = File(outputPath);
      await file.writeAsBytes(_docxBytes!);

      _showSuccess('DOCX文档保存成功！\n保存位置: $outputPath');
    } catch (e) {
      _showError('保存DOCX文档时发生错误: $e');
    }
  }



  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  void _showInfo(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.blue,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _showSuccess(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  // 使用外部程序打开DOCX文件
  Future<void> _openWithExternalApp() async {
    if (_tempFile == null || !await _tempFile!.exists()) {
      _showError('临时文件不存在，请重新生成预览');
      return;
    }

    try {
      // 使用open_file包打开DOCX文件
      final result = await OpenFile.open(
        _tempFile!.path,
        type: "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
      );

      // 根据返回结果显示相应提示
      if (result.type.toString() == 'ResultType.done') {
        _showSuccess('文档已成功打开！');
      } else if (result.type.toString() == 'ResultType.noAppToOpen') {
        _showError('没有找到可以打开DOCX文件的应用\n请安装Word、WPS或其他文档编辑器');
      } else if (result.type.toString() == 'ResultType.fileNotFound') {
        _showError('文件未找到，请重新生成文档');
      } else if (result.type.toString() == 'ResultType.permissionDenied') {
        _showError('没有权限打开文件');
      } else {
        _showError('打开文件失败: ${result.message}');
      }
    } catch (e) {
      // 如果失败，提供备选方案
      _showError('无法自动打开文件: $e');
      _showInfo('请点击"保存到本地"按钮保存文档，然后手动使用Word、WPS等应用打开查看');
    }
  }

  // 切换预览模式
  void _togglePreview() {
    setState(() {
      _showPreview = !_showPreview;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('DOCX文档预览'),
        actions: [
          if (!_isLoading && _docxBytes != null) ...[
            // 预览模式切换按钮
            IconButton(
              icon: Icon(_showPreview ? Icons.info : Icons.preview),
              tooltip: _showPreview ? '显示文档信息' : '内置预览',
              onPressed: _togglePreview,
            ),
            // 外部程序打开按钮
            IconButton(
              icon: const Icon(Icons.open_in_new),
              tooltip: '用外部应用打开',
              onPressed: _openWithExternalApp,
            ),
          ],
          if (!_isLoading && _docxBytes != null)
            IconButton(
              icon: const Icon(Icons.save),
              tooltip: '保存到本地',
              onPressed: _saveToFile,
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('正在生成DOCX文档...'),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Colors.red[300],
            ),
            const SizedBox(height: 16),
            Text(
              _errorMessage!,
              style: const TextStyle(color: Colors.red),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => _initializeAndGeneratePreview(),
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }

    // 根据预览模式显示不同内容
    if (_showPreview && _docxBytes != null) {
      // 内置预览模式
      return Column(
        children: [
          // 预览提示
          // Container(
          //   width: double.infinity,
          //   padding: const EdgeInsets.all(12),
          //   margin: const EdgeInsets.all(16),
          //   decoration: BoxDecoration(
          //     color: Colors.blue[50],
          //     borderRadius: BorderRadius.circular(8),
          //     border: Border.all(color: Colors.blue[200]!),
          //   ),
          //   child: Row(
          //     children: [
          //       Icon(Icons.preview, color: Colors.blue[600]),
          //       const SizedBox(width: 8),
          //       Expanded(
          //         child: Text(
          //           'DOCX文档内置预览',
          //           style: TextStyle(color: Colors.blue[800]),
          //         ),
          //       ),
          //     ],
          //   ),
          // ),
          // microsoft_viewer预览器
          Expanded(
            child: MicrosoftViewer(
                  _docxBytes!,
                  key: UniqueKey(), // 使用UniqueKey确保每次都重新渲染
                ),
          ),
          // 底部操作按钮
          Container(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // 外部打开按钮
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _openWithExternalApp,
                    icon: const Icon(Icons.open_in_new, size: 20),
                    label: const Text('外部打开'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: Colors.orange[600],
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // 保存按钮
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: _saveToFile,
                    icon: const Icon(Icons.download, size: 20),
                    label: const Text('保存到本地'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: Colors.blue[600],
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    // 文档信息模式
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 成功提示卡片
          Card(
            color: Colors.green[50],
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green[600], size: 32),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'DOCX文档生成成功！',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.green[800],
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '您可以点击"外部打开"按钮直接预览，或点击"保存到本地"按钮保存文档',
                          style: TextStyle(color: Colors.green[700]),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // 文档信息卡片
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '文档信息',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  _buildInfoRow('标题', widget.title.isNotEmpty ? widget.title : '未命名剧本'),
                  if (_parseResult != null && _parseResult!.success) ...[
                    _buildInfoRow('页数', '${_parseResult!.pageCount} 页'),
                    _buildInfoRow('字符数', '${_parseResult!.characterCount} 个'),
                    _buildInfoRow('单词数', '${_parseResult!.wordCount} 个'),
                  ],
                  if (_config != null)
                    _buildInfoRow('打印配置', _config!.printProfile),
                  if (_docxBytes != null)
                    _buildInfoRow('文件大小', '${(_docxBytes!.length / 1024).toStringAsFixed(2)} KB'),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // 操作按钮
          Row(
            children: [
              // 外部打开按钮
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _openWithExternalApp,
                  icon: const Icon(Icons.open_in_new, size: 20),
                  label: const Text('外部打开'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: Colors.orange[600],
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // 保存按钮
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: _saveToFile,
                  icon: const Icon(Icons.download, size: 20),
                  label: const Text('保存到本地'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: Colors.blue[600],
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: Text(value),
          ),
        ],
      ),
    );
  }
}
