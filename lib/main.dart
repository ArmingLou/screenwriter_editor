import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:path/path.dart' as path;
import 'fountain_parser.dart';
import 'package:intl/intl.dart';
import 'package:percent_indicator/percent_indicator.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(const ScreenwriterEditorApp());
}

class _FormatTask {
  final Completer<void> _completer = Completer<void>();
  final Future<void> Function() _task;

  _FormatTask(this._task);

  Future<void> execute() async {
    Future<void> future = _task().whenComplete(() => _completer.complete());
    return future;
  }

  bool get isPending => !_completer.isCompleted;
}

class ScreenwriterEditorApp extends StatelessWidget {
  const ScreenwriterEditorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Screenwriter Editor',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const EditorScreen(),
    );
  }
}

class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  final ValueNotifier<List<int>> _charsLenNotifier =
      ValueNotifier<List<int>>([0, 0]);
  final ValueNotifier<String> _stateBarMsgNotifier = ValueNotifier<String>("");
  final TextEditingController _titleEditingController = TextEditingController();
  final ScrollController _titleScrollController = ScrollController();
  late final QuillController _quillController;
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  // TextSelection? _lastSelection;
  // String _currentFilePath = '';
  bool _onlyEditRefresh = true;
  //仅在输入或删除文本时，刷新光标附近文本的语法高亮；否则，只要光标位置改变，都刷新光标附近文本的语法高亮。

  final _formatQueue = <_FormatTask>[];
  static const _maxQueueLength = 2;

  final double _sliderWidth = 180;

  int _lastSelection = -1;

  int _lastFormatingFullTime = 0;
  int _lastTapSliderTime = 0;
  int _startChars = 0; //第一个场景之前的字数，作用是预估时间需要减去。
  double _charsPerMinu = 243.22; //按每分钟多少个字预估。

  // 获取可见区域文本
  Future<void> formatText(int index, int len, Attribute? attribute,
      bool shouldNotifyListeners) async {
    _quillController.formatText(
      index,
      len,
      attribute,
      shouldNotifyListeners: shouldNotifyListeners,
    );
  }

  // 获取可见区域文本，基于光标位置的一个有限范围进行。
  Future<void> formatVisibleText() async {
    // // 获取可见区域的行范围
    // final firstVisibleLine = _getFirstVisibleLine(_scrollController);
    // final lastVisibleLine = _getLastVisibleLine(_scrollController);

    // // 获取可见区域的文本
    // final fullText = _quillController.document.toPlainText();
    // final lines = fullText.split('\n');

    // int beforTextOffset = 0;
    // if (firstVisibleLine > 0) {
    //   final beforeText = lines.sublist(0, firstVisibleLine).join('\n');
    //   beforTextOffset = beforeText.length;
    // }
    // final visibleText =
    //     lines.sublist(firstVisibleLine, lastVisibleLine + 1).join('\n');

    final fullText = _quillController.document.toPlainText();

    // final selection = _quillController.selection;
    int preChar;
    int sufChar;
    if (_onlyEditRefresh) {
      preChar = 20;
      sufChar = 20;
    } else {
      preChar = 150;
      sufChar = 300;
      //差不多一页范围
    }

    int beforTextOffset = 0;
    // find beforTextOffset
    int tempEnd = _quillController.selection.baseOffset - preChar;
    if (tempEnd > 0) {
      int tempStart = tempEnd;
      while (true) {
        tempStart -= 30;
        if (tempStart <= 0) {
          break;
        }
        var tempStr = fullText.substring(tempStart, tempEnd);
        var i = tempStr.indexOf('\n\n');
        if (i >= 0) {
          var comm = fullText.substring(tempStart + i, _quillController.selection.baseOffset);
          // 假设 [[]] 和 /* */ 不存在相互嵌套的简单情况处理
          var j1 = comm.indexOf(']]');
          if (j1 >= 0) {
            var j2 = comm.indexOf('[[');
            if (j2 < 0 || j2 > j1) {
              //截断的 注释，继续往前找
              continue;
            }
          }
          var k1 = comm.indexOf('*/');
          if (k1 >= 0) {
            var k2 = comm.indexOf('/*');
            if (k2 < 0 || k2 > k1) {
              //截断的 注释，继续往前找
              continue;
            }
          }
          beforTextOffset = tempStart + i;
          break;
        }
      }
    }

    int end = _quillController.selection.extentOffset + sufChar;
    if (end >= fullText.length) {
      end = fullText.length;
    } else {
      int tempStart = end;
      tempEnd = tempStart;
      while (true) {
        tempEnd += 30;
        if (tempEnd >= fullText.length) {
          end = fullText.length;
          break;
        }
        var tempStr = fullText.substring(tempStart, tempEnd);
        var i = tempStr.lastIndexOf('\n\n');
        if (i >= 0) {
          var comm = fullText.substring(_quillController.selection.baseOffset, tempStart + i);
          // 假设 [[]] 和 /* */ 不存在相互嵌套的简单情况处理
          var j1 = comm.lastIndexOf('[[');
          if (j1 >= 0) {
            var j2 = comm.lastIndexOf(']]');
            if (j2 < 0 || j2 < j1) {
              //截断的 注释，继续往前找
              continue;
            }
          }
          var k1 = comm.lastIndexOf('/*');
          if (k1 >= 0) {
            var k2 = comm.lastIndexOf('*/');
            if (k2 < 0 || k2 < k1) {
              //截断的 注释，继续往前找
              continue;
            }
          }
          end = tempStart + i;
          break;
        }
      }
    }
    // len = len - beforTextOffset;
    // if (len < 0) {
    //   len = 0;
    // }
    final visibleText = fullText.substring(beforTextOffset, end);

    // 解析并格式化可见文本
    final parsed = await compute(_parseText, visibleText);

    RT:
    for (final element in parsed) {
      final styles = _getStyleForElement(element);
      if (styles != null) {
        for (var style in styles) {
          if (style != null) {
            if (_formatQueue.length >= _maxQueueLength) {
              break RT;
            }
            await formatText(element.range.start + beforTextOffset,
                element.range.length, style, false);
            //await 延迟
            await Future.delayed(const Duration(milliseconds: 2));
          }
        }
      }
    }

    // 恢复光标位置
    _quillController.updateSelection(
      _quillController.selection,
      ChangeSource.local,
    );
  }

  // 全文格式一次
  Future<void> formatFullText() async {
    final int thisFormatFullTime =
        (DateTime.now().millisecondsSinceEpoch / 1000).toInt();
    if (thisFormatFullTime == _lastFormatingFullTime) {
      return;
    }
    _lastFormatingFullTime = thisFormatFullTime;
    _stateBarMsgNotifier.value = '(语法刷新中...)'; //状态栏显示状态。

    // final selection = _quillController.selection;
    final fullText = _quillController.document.toPlainText();

    // 解析并格式化可见文本
    final parsed = await compute(_parseText, fullText);

    // var count = 0;

    bool wasBreak = false;

    bool fisrtScencStarted = false;
    // int tempStartChars = 0;

    RTF:
    for (final element in parsed) {
      if (!fisrtScencStarted && thisFormatFullTime == _lastFormatingFullTime) {
        if (element.type == 'scene_heading') {
          fisrtScencStarted = true;
          _startChars = element.range.start+element.range.length;
        } else {
          if (element.type != 'comment') {
            // comment 是重复的字数。
            // tempStartChars += element.range.length + 1; // 加个换行符的数量1.
            // 简单地从metadata中找到 每分钟多少个字的配置。前提是这个json配置的字段，格式上要单独一行。
            int i = element.text.indexOf('"chars_per_minu"');
            if (i > 0) {
              String s = element.text.substring(i + 16);
              int j = s.indexOf(',');
              String v = '';
              if (j > 1) {
                v = s.substring(s.indexOf(':') + 1, j);
                _charsPerMinu = double.parse(v.trim());
              } else if (j == -1) {
                v = s.substring(s.indexOf(':') + 1);
                _charsPerMinu = double.parse(v.trim());
              }
            }
          }
        }
      }
      final styles = _getStyleForElement(element);
      if (styles != null) {
        for (var style in styles) {
          if (style != null) {
            if (thisFormatFullTime != _lastFormatingFullTime) {
              wasBreak = true;
              break RTF;
            }
            await formatText(
                element.range.start, element.range.length, style, false);
            // count++;
            // if (count >= 100) {
            //   count = 0;
            //   _quillController.updateSelection(
            //     TextSelection(baseOffset: element.range.start, extentOffset: element.range.start),
            //     ChangeSource.local,
            //   );
            // }
            //await 延迟
            await Future.delayed(const Duration(milliseconds: 2));
          }
        }
      }
    }

    if (thisFormatFullTime == _lastFormatingFullTime) {
      _stateBarMsgNotifier.value = ''; //恢复0，为状态栏显示状态。
    }

    if (!wasBreak) {
      // 恢复光标位置.只是为了触发刷新界面，否则可能样式不渲染。
      _quillController.updateSelection(
        _quillController.selection,
        ChangeSource.local,
      );
    }
  }

  // 添加任务到队列
  void whenCompl() async {
    _formatQueue.removeAt(0);
    if (_formatQueue.length == 1) {
      await _formatQueue[0].execute().whenComplete(whenCompl);
    }
  }

  // 添加任务到队列。编辑时需要更新
  void addFormatTask() async {
    if (_quillController.selection.baseOffset == _lastSelection) {
      return;
    }
    _lastSelection = _quillController.selection.baseOffset;
    // 否则不用添加新任务

    // 如果队列已满，移除上次最新进入的任务
    if (_formatQueue.length >= _maxQueueLength) {
      // 从后往前查找未开始的任务
      for (var i = _formatQueue.length - 1; i >= _maxQueueLength - 1; i--) {
        if (_formatQueue[i].isPending) {
          _formatQueue.removeAt(i);
          // break;
        }
      }
    }

    // 添加新任务
    final task = _FormatTask(formatVisibleText);
    _formatQueue.add(task);

    // 如果只有一个任务，立即执行
    if (_formatQueue.length == 1) {
      await task.execute().whenComplete(whenCompl);
    } else {
      // 等待前一个任务完成
      // await _formatQueue[_formatQueue.length - 2].future;
      // await task.execute();
    }
  }

  void _setupFormatListener() {
    // 监听文档变化
    _quillController.document.changes.listen((change) {
      if (change.source != ChangeSource.local ||
          (change.change.last.key != 'insert' &&
              change.change.last.key != 'delete')) {
        return;
      }
      if (_onlyEditRefresh) {
        addFormatTask();
      }
    });

    // 监听光标位置变化
    // _quillController.addListener(() {
    //   // if (_quillController.selection.baseOffset != _lastSelection) {
    //   //   _lastSelection = _quillController.selection.baseOffset;
    //   addFormatTask();
    //   // }
    // });
  }

  void _onTapSlider(PointerEvent event) async {
    int currentT = DateTime.now().millisecondsSinceEpoch;
    if (currentT - _lastTapSliderTime < 100) {
      return;
    }
    _lastTapSliderTime = currentT;
    // 计算 指针的偏移 百分比
    double progress = event.localPosition.dx / _sliderWidth;
    if (progress < 0) progress = 0;

    int total = _quillController.document.length - 1;
    if (total < 0) total = 0;

    int selectionTar = (total * progress).toInt();
    if (selectionTar >= _quillController.document.length) {
      selectionTar = _quillController.document.length - 1;
    }

    _quillController.updateSelection(
      TextSelection(baseOffset: selectionTar, extentOffset: selectionTar),
      ChangeSource.local,
    );
  }

  void _onTapDownSlider(PointerDownEvent event) async {
    _onTapSlider(event);
  }

  void _onTapMoveSlider(PointerMoveEvent event) async {
    _onTapSlider(event);
  }

  int _getFirstVisibleLine(ScrollController scrollController) {
    final offset = scrollController.offset;
    const lineHeight = 20.0; // 假设每行高度为20px
    final firstVisible = (offset / lineHeight).floor();
    // 获取前10行，确保不小于0
    return math.max(0, firstVisible - 10);
  }

  int _getLastVisibleLine(ScrollController scrollController) {
    final offset = scrollController.offset;
    final viewportHeight = MediaQuery.of(context).size.height;
    const lineHeight = 20.0; // 假设每行高度为20px
    final lastVisible = ((offset + viewportHeight) / lineHeight).ceil();
    final totalLines =
        _quillController.document.toPlainText().split('\n').length;
    // 获取后10行，确保不超过总行数
    return math.min(totalLines - 1, lastVisible + 10);
  }

  // 在isolate中解析文本
  static Future<List<FountainElement>> _parseText(String text) async {
    final parser = FountainParser();
    return parser.parse(text);
  }

  void whenChangeSlect(TextSelection t) {
    int total = _quillController.document.length - 1;
    if (total < 0) total = 0;
    _charsLenNotifier.value = [
      _quillController.selection.baseOffset,
      total
    ]; //更新状态光标偏移统计；
    if (!_onlyEditRefresh) {
      addFormatTask();
    }
  }

  @override
  void initState() {
    super.initState();
    final document = Document();
    _quillController = QuillController(
      document: document,
      selection: const TextSelection.collapsed(offset: 0),
      onSelectionChanged: whenChangeSlect,
    );

    _setupFormatListener();
  }

  @override
  void dispose() {
    _quillController.dispose();
    super.dispose();
  }

  bool _isFilePickerActive = false;

  Future<void> _openFile() async {
    if (_isFilePickerActive) return;
    _isFilePickerActive = true;

    final status =
        await [Permission.manageExternalStorage, Permission.storage].request();
    // if(status != PermissionStatus.granted){ //就算没有允许的情况下，也可能过成功写入新文件。 相反，就算允许了，也会可能出现权限问题无法写入。申请一次，总比不申请好。
    //   _showError('没有获取到文件读写权限');
    //   return;
    // }

    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
        withData: false,
        withReadStream: false,
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        if (file.extension?.toLowerCase() == 'fountain') {
          // 获取真实文件路径并解码
          String? filePath;
          var i = file.identifier!.indexOf("%3A%2F");
          if (i > -1) {
            filePath = file.identifier!.substring(i + 3);
          } else {
            var i = file.identifier!.indexOf("%3A");
            if (i > -1) {
              filePath = file.identifier!.substring(i + 3);
              final dir = await getExternalStorageDirectory();
              var dirPath = dir!.path;
              final j = dirPath.indexOf('/Android/data/');
              dirPath = dirPath.substring(0, j);
              filePath = dirPath + '/' + filePath;
            }
          }
          if (filePath == null) {
            throw Exception('无法获取文件路径');
          }

          // 解码URL编码的路径
          filePath = Uri.decodeFull(filePath);

          // 检查文件是否可访问
          if (!await File(filePath).exists()) {
            throw Exception('文件不存在或无法访问');
          }

          // 读取文件内容
          // String content = await File(filePath).readAsString();
          String content = await File(file.path!).readAsString();
          // final delta = Delta()..insert('$content\n');
          // _quillController.clear();
          _quillController.replaceText(0, _quillController.document.length - 1,
              '$content', const TextSelection.collapsed(offset: 0));

          int total = _quillController.document.length - 1;
          if (total < 0) total = 0;
          _charsLenNotifier.value = [
            _quillController.selection.baseOffset,
            total
          ]; //更新状态光标偏移统计；

          FilePicker.platform.clearTemporaryFiles();

          // 更新当前文件路径
          // setState(() {
          // _currentFilePath = filePath!;
          // });
          _titleEditingController.text = filePath;
          // 在下一次ui刷新后再执行
          Future.delayed(const Duration(milliseconds: 500), () {
            _titleScrollController
                .jumpTo(_titleScrollController.position.maxScrollExtent);
          });

          // 触发格式更新
          // addFormatTask();//部分格式
          formatFullText(); //全文格式
        } else {
          _showError('请选择.fountain文件');
        }
      }
    } catch (e) {
      _showError('打开文件失败: $e');
    } finally {
      _isFilePickerActive = false;
    }
  }

  Future<void> _saveFile() async {
    if (_isFilePickerActive) return;
    _isFilePickerActive = true;

    try {
      // String savePath = _currentFilePath;
      String savePath = _titleEditingController.text.trim();

      // 如果没有文件路径，则选择保存位置
      if (savePath.isEmpty) {
        if (mounted) {
          _showError('请先在标题栏输入文件名');
        }
        return;
      }

      final status = await [
        Permission.manageExternalStorage,
        Permission.storage
      ].request();
      // if(status != PermissionStatus.granted){ //就算没有允许的情况下，也可能过成功写入新文件。 相反，就算允许了，也会可能出现权限问题无法写入。申请一次，总比不申请好。
      //   _showError('没有获取到文件读写权限');
      //   return;
      // }

      if (!savePath.contains('/')) {
        // 只输入了文件名的情况
        // 获取默认保存路径
        Directory directory;
        String fileName = 'script.fountain';
        if (Platform.isAndroid) {
          //android 平台下 用 FilePicker.platform.saveFile 保存的文件，二次编辑不能二次保存，会有权限问题。需要用 file2.writeAsString 保存文件，才能二次编辑

          // directory = await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();
          // final initialPath = directory.path;

          // Android平台使用pickFiles选择文件路径
          await FilePicker.platform.clearTemporaryFiles();
          final result = await FilePicker.platform.pickFiles(
            type: FileType.any,
            allowMultiple: false,
            dialogTitle: '选择任意一个文件，将保存新文件在相同目录下',
            // initialDirectory: initialPath,
            // lockParentWindow: true,
          );

          if (result == null || result.files.isEmpty) return;
          final file = result.files.first;
          String? filePath;
          var i = file.identifier!.indexOf("%3A%2F");
          if (i > -1) {
            filePath = file.identifier!.substring(i + 3);
          } else {
            var i = file.identifier!.indexOf("%3A");
            if (i > -1) {
              filePath = file.identifier!.substring(i + 3);
              final dir = await getExternalStorageDirectory();
              var dirPath = dir!.path;
              final j = dirPath.indexOf('/Android/data/');
              dirPath = dirPath.substring(0, j);
              filePath = dirPath + '/' + filePath;
            }
          }
          if (filePath == null) {
            throw Exception('无法获取文件路径');
          }
          // 解码URL编码的路径
          filePath = Uri.decodeFull(filePath);
          final f = File(filePath);

          // savePath = f.parent.path +
          //     '/剧本' +
          //     DateFormat('yyyy-MM-dd_HH_mm').format(DateTime.now()) +
          //     '.fountain';
          fileName = savePath;
          if (!fileName.endsWith('.fountain')) {
            fileName = '$fileName.fountain';
          }
          savePath = f.parent.path + '/' + fileName;

          // 写入文件内容
          final file2 = File(savePath);
          if (file2.existsSync()) {
            _showError('新建文件失败: 文件名 [ $fileName ] 在相同目录下已存在，请换一个名称');
            return;
          }
          var plainText = _quillController.document.toPlainText();
          if (plainText.endsWith('\n')) {
            plainText = plainText.substring(
                0,
                plainText.length -
                    1); //_quillController.document.toPlainText()方法，会自动在文末加一个\n换行符
          }
          await file2.writeAsString(plainText, flush: true);

          // if (savePath.isEmpty) {
          //   directory = await getApplicationDocumentsDirectory();
          //   // 用时间戳做文件名
          //   fileName = '剧本' +
          //       DateTime.now().microsecondsSinceEpoch.toString();
          // } else {
          //   // 从 savePath 文件获取目录和 文件名
          //   final file2 = File(savePath);
          //   directory = file2.parent;
          //   fileName = path.basename(savePath);
          // }

          // final plainText = _quillController.document.toPlainText();
          // Uint8List bytes = Utf8Codec().encode(plainText);

          // // 其他平台使用FilePicker选择保存位置
          // await FilePicker.platform.clearTemporaryFiles();
          // final result = await FilePicker.platform.saveFile(
          //   dialogTitle: '保存Fountain文件',
          //   fileName: fileName,
          //   initialDirectory: directory.path,
          //   allowedExtensions: ['fountain'],
          //   lockParentWindow: true,
          //   bytes: bytes,
          // );

          // if (result == null) return; // result 有可能被重命名，当文件名与现有文件重复。
          // // savePath = result.endsWith('.fountain') ? result : '$result.fountain';
          // savePath = result + '.fountain'; //副本

          // // 重新 写入文件内容, 可编辑的副本。
          // final file2 = File(savePath);
          // await file2.writeAsString(plainText, flush: true);
        } else {
          directory = await getApplicationDocumentsDirectory();
          // 用时间戳做文件名
          if (!savePath.endsWith('.fountain')) {
            savePath = '$savePath.fountain';
          }
          fileName = savePath;

          var plainText = _quillController.document.toPlainText();
          if (plainText.endsWith('\n')) {
            plainText = plainText.substring(
                0,
                plainText.length -
                    1); //_quillController.document.toPlainText()方法，会自动在文末加一个\n换行符
          }
          Uint8List bytes = Utf8Codec().encode(plainText);

          // 其他平台使用FilePicker选择保存位置
          await FilePicker.platform.clearTemporaryFiles();
          final result = await FilePicker.platform.saveFile(
            dialogTitle: '保存Fountain文件',
            fileName: fileName,
            initialDirectory: directory.path,
            allowedExtensions: ['fountain'],
            lockParentWindow: true,
            bytes: bytes,
          );

          if (result == null) return;
          // savePath = result.endsWith('.fountain') ? result : '$result.fountain';
          savePath =
              result; // TODO Arming (2025-03-12) : android 保存文件时，切换目录保存，会有bug。保存的文件实际在切换了的目录了，但返回的result总是Download目录下的地址。
        }
      } else {
        // 写入文件内容
        var plainText = _quillController.document.toPlainText();
        if (plainText.endsWith('\n')) {
          plainText = plainText.substring(
              0,
              plainText.length -
                  1); //_quillController.document.toPlainText()方法，会自动在文末加一个\n换行符
        }
        final file2 = File(savePath);
        await file2.writeAsString(plainText, flush: true);
      }

      // 更新状态
      // setState(() {
      //   _currentFilePath = savePath;
      // });
      _titleEditingController.text = savePath;
      // 在下一次ui刷新后再执行
      Future.delayed(const Duration(milliseconds: 500), () {
        _titleScrollController
            .jumpTo(_titleScrollController.position.maxScrollExtent);
      });

      // 显示成功提示
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('文件保存成功: $savePath'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        _showError('保存文件失败: $e');
        // _titleEditingController.text = '/errror/';
      }
    } finally {
      _isFilePickerActive = false;
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  List<Attribute<dynamic>?>? _getStyleForElement(FountainElement element) {
    switch (element.type) {
      case 'scene_heading':
        return [
          // Attribute.fromKeyValue(Attribute.font.key, "Courier"),
          Attribute.fromKeyValue(Attribute.size.key, "18"),
          Attribute.fromKeyValue(Attribute.bold.key, true),
          Attribute.fromKeyValue(Attribute.italic.key, null), // 使用null清除斜体样式
          Attribute.fromKeyValue(Attribute.color.key, '#FF0000')
        ];
      case 'character':
        return [
          // Attribute.fromKeyValue(Attribute.font.key, "Courier"),
          Attribute.fromKeyValue(Attribute.size.key, "16"),
          Attribute.fromKeyValue(Attribute.bold.key, true),
          Attribute.fromKeyValue(Attribute.italic.key, null),
          Attribute.fromKeyValue(Attribute.color.key, '#0000FF')
        ];
      case 'parenthetical':
        return [
          // Attribute.fromKeyValue(Attribute.font.key, "Courier"),
          Attribute.fromKeyValue(Attribute.size.key, "14"),
          Attribute.fromKeyValue(Attribute.bold.key, null),
          Attribute.fromKeyValue(Attribute.italic.key, true),
          Attribute.fromKeyValue(Attribute.color.key, '#6B8E23')
        ];
      case 'dialogue':
        return [
          // Attribute.fromKeyValue(Attribute.font.key, "Courier"),
          Attribute.fromKeyValue(Attribute.size.key, "14"),
          Attribute.fromKeyValue(Attribute.bold.key, null),
          Attribute.fromKeyValue(Attribute.italic.key, true),
          Attribute.fromKeyValue(Attribute.color.key, '#3CB371')
        ];
      case 'transition':
        return [
          // Attribute.fromKeyValue(Attribute.font.key, "Courier"),
          Attribute.fromKeyValue(Attribute.size.key, "14"),
          Attribute.fromKeyValue(Attribute.bold.key, null),
          Attribute.fromKeyValue(Attribute.italic.key, null),
          Attribute.fromKeyValue(Attribute.color.key, '#d853ce')
        ];
      case 'sections':
        return [
          // Attribute.fromKeyValue(Attribute.font.key, "Courier"),
          Attribute.fromKeyValue(Attribute.size.key, "18"),
          Attribute.fromKeyValue(Attribute.bold.key, null),
          Attribute.fromKeyValue(Attribute.italic.key, null),
          Attribute.fromKeyValue(Attribute.color.key, '#a7089b')
        ];
      case 'page_breaks':
        return [
          // Attribute.fromKeyValue(Attribute.font.key, "Courier"),
          Attribute.fromKeyValue(Attribute.size.key, "14"),
          Attribute.fromKeyValue(Attribute.bold.key, null),
          Attribute.fromKeyValue(Attribute.italic.key, null),
          Attribute.fromKeyValue(Attribute.color.key, '#d5072d')
        ];
      case 'synopses':
        return [
          // Attribute.fromKeyValue(Attribute.font.key, "Courier"),
          Attribute.fromKeyValue(Attribute.size.key, "14"),
          Attribute.fromKeyValue(Attribute.bold.key, null),
          Attribute.fromKeyValue(Attribute.italic.key, null),
          Attribute.fromKeyValue(Attribute.color.key, '#add8e6')
        ];
      case 'center':
        return [
          // Attribute.fromKeyValue(Attribute.font.key, "Courier"),
          Attribute.fromKeyValue(Attribute.size.key, "14"),
          Attribute.fromKeyValue(Attribute.bold.key, null),
          Attribute.fromKeyValue(Attribute.italic.key, null),
          Attribute.fromKeyValue(Attribute.color.key, '#87ceeb')
        ];
      case 'lyrics':
        return [
          // Attribute.fromKeyValue(Attribute.font.key, "Courier"),
          Attribute.fromKeyValue(Attribute.size.key, "14"),
          Attribute.fromKeyValue(Attribute.bold.key, null),
          Attribute.fromKeyValue(Attribute.italic.key, true),
          Attribute.fromKeyValue(Attribute.color.key, '#00FF00')
        ];
      case 'note':
        return [
          // Attribute.fromKeyValue(Attribute.font.key, "Courier"),
          Attribute.fromKeyValue(Attribute.size.key, "12"),
          Attribute.fromKeyValue(Attribute.bold.key, null),
          Attribute.fromKeyValue(Attribute.italic.key, null),
          Attribute.fromKeyValue(Attribute.color.key, '#CDBE70')
        ];
      case 'comment':
        return [
          // Attribute.fromKeyValue(Attribute.font.key, "Courier"),
          Attribute.fromKeyValue(Attribute.size.key, "12"),
          Attribute.fromKeyValue(Attribute.bold.key, null),
          Attribute.fromKeyValue(Attribute.italic.key, null),
          Attribute.fromKeyValue(Attribute.color.key, '#aeaeae')
        ];
      default:
        return [
          // Attribute.fromKeyValue(Attribute.font.key, "Courier"),
          Attribute.fromKeyValue(Attribute.size.key, "14"),
          Attribute.fromKeyValue(Attribute.bold.key, null),
          Attribute.fromKeyValue(Attribute.italic.key, null),
          Attribute.fromKeyValue(Attribute.color.key, '#000000')
        ];
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: null,
        actions: [
          // Switch(
          //   value: !_onlyEditRefresh,
          //   onChanged: (value) {
          //     setState(() {
          //       _onlyEditRefresh = !value;
          //     });
          //   },
          // ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: formatFullText,
          ),
          Expanded(
            child: TextField(
              controller: _titleEditingController,
              scrollController: _titleScrollController,
              textAlign: TextAlign.right,
              decoration: const InputDecoration(
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(horizontal: 8),
              ),
              // onChanged: (value) {
              //   setState(() {
              //     _currentFilePath = value;
              //   });
              // },
            ),
          ),
          IconButton(
            icon: const Icon(Icons.folder_open),
            onPressed: _openFile,
          ),
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _saveFile,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: QuillEditor(
                focusNode: _focusNode,
                scrollController: _scrollController,
                controller: _quillController,
                config: QuillEditorConfig(
                  scrollable: true,
                  autoFocus: false,
                  expands: true,
                  padding: const EdgeInsets.all(8),
                ),
              ),
            ),
            Container(
              height: 24,
              color: Color.fromARGB(255, 210, 210, 210),
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  ValueListenableBuilder<String>(
                    valueListenable: _stateBarMsgNotifier,
                    builder: (context, msg, _) {
                      return Text(
                        msg,
                        style: const TextStyle(
                            fontSize: 12,
                            color: Color.fromARGB(255, 201, 79, 60)),
                      );
                    },
                  ),
                  Padding(
                    //左边添加8像素补白
                    padding: EdgeInsets.only(left: 10),
                    child: Text(
                      '字数:',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  Listener(
                    onPointerDown: _onTapDownSlider,
                    onPointerMove: _onTapMoveSlider,
                    child: ValueListenableBuilder<List<int>>(
                      valueListenable: _charsLenNotifier,
                      builder: (context, arr, _) {
                        // 预估时间处理：
                        int total = arr[1] - _startChars;
                        int curr = arr[0] - _startChars;
                        if (curr < 0) curr = 0;
                        double totalMinu = total / _charsPerMinu;
                        double currMinu = curr / _charsPerMinu;
                        String totalLabel = '';
                        String currLabel = '';
                        if (totalMinu > 1) {
                          int totalM = totalMinu.toInt();
                          totalLabel = "$totalM'";
                        } else {
                          int totalSeconds = (totalMinu * 60).toInt();
                          int totalS = totalSeconds % 60;
                          totalLabel = "$totalS”";
                        }
                        if (currMinu > 1) {
                          int currM = currMinu.toInt();
                          currLabel = "$currM'";
                        } else {
                          int currSeconds = (currMinu * 60).toInt();
                          int currS = currSeconds % 60;
                          currLabel = "$currS”";
                        }
                        return LinearPercentIndicator(
                          width: _sliderWidth,
                          lineHeight: 14.0,
                          percent: arr[0] / arr[1],
                          center: Text(
                            '${arr[0]} / ${arr[1]}  [$currLabel/$totalLabel]',
                            style: TextStyle(fontSize: 12.0),
                          ),
                          backgroundColor:
                              const Color.fromARGB(255, 164, 191, 214),
                          progressColor:
                              const Color.fromARGB(255, 233, 231, 175),
                        );
                      },
                    ),
                  )
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
