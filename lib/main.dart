import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:path/path.dart' as path;
import 'package:screenwriter_editor/socket_service.dart';
import 'package:screenwriter_editor/socket_settings_page.dart';
import 'package:screenwriter_editor/socket_client.dart';
import 'package:screenwriter_editor/socket_client_page.dart';
import 'package:screenwriter_editor/statis.dart';
import 'package:screenwriter_editor/stats_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'fountain_parser.dart';
import 'package:intl/intl.dart';
import 'package:percent_indicator/percent_indicator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:toastification/toastification.dart';

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
      debugShowCheckedModeBanner: false,
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
  final ValueNotifier<Statis?> _stateStatisNotifier =
      ValueNotifier<Statis?>(null);
  final TextEditingController _titleEditingController = TextEditingController();
  final ScrollController _titleScrollController = ScrollController();
  late final QuillController _quillController;
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  // TextSelection? _lastSelection;
  // String _currentFilePath = '';
  bool _onlyEditRefresh = true;
  //仅在输入或删除文本时，刷新光标附近文本的语法高亮；否则，只要光标位置改变，都刷新光标附近文本的语法高亮。

  final List<Delta> _lastRedo = [];

  final _formatQueue = <_FormatTask>[];
  static const _maxQueueLength = 2;

  final double _sliderWidth = 180;

  // 控制工具栏显示/隐藏的状态变量
  bool _editable = false;
  bool _historyRollback = false;
  bool _docChanged = false;
  bool _openNewDocWaitDeleteNotify = false;
  bool _openNewDocWaitInsertNotify = false;

  // 光标移动定时器
  Timer? _backwardTimer;
  Timer? _forwardTimer;

  // 光标移动加速相关变量
  final int _cursorMoveInterval = 50; // 初始移动间隔（毫秒）
  final int _minCursorMoveInterval = 5; // 最小移动间隔（毫秒）
  final int _cursorAccelerationStep = 5; // 每次加速减少的毫秒数
  int _longPressStartTime = 0; // 长按开始时间

  // 只读模式下用户输入检测相关变量
  int _readOnlyInputCount = 0; // 只读模式下用户输入次数
  int _lastReadOnlyInputTime = 0; // 最近一次只读模式下用户输入的时间
  Timer? _editIconBlinkTimer; // 编辑图标闪烁定时器
  Color _editIconColor = Colors.black; // 编辑图标颜色

  // Socket服务相关变量
  final SocketService _socketService = SocketService();
  StreamSubscription<SocketEvent>? _socketEventSubscription;

  // Statis? statisGlobal;

  int _lastSelection = -1;

  List<FountainElement> _elements = [];

  int _lastFormatingFullTime = 0;
  Map<String, int> _lastParserFullTime = {};
  Map<String, FountainParser> _parser = {};
  int _lastTapSliderTime = 0;
  int _startChars = 0; //第一个场景之前的字数，作用是预估时间需要减去。
  double _charsPerMinu = 243.22; //按每分钟多少个字预估， （全文，不区分对白）。
  double _dialCharsPerMinu = 171; //按每分钟多少个字预估, （只针对 对白）。
  bool fisrtScencStarted = false;

  static final List<List<String>> defaultAutoCompleteScene = [
    [".(内景) "],
    [".(外景) "],
    [".(内外景) "],
    ["INT. "],
    ["EXT. "],
    ["INT/EXT. "],
    ["EST. "]
  ];
  List<List<String>> autoCompleteScene = [];
  List<List<String>> autoCompleteLocation = [];
  List<List<String>> autoCompleteTime = [
    [" - 日"],
    [" - 夜"],
    [" - 黎明"],
    [" - 清晨"],
    [" - 傍晚"],
    [" - DAY"],
    [" - NIGHT"],
    [" - DAWN"],
    [" - MORNING"],
    [" - DUSK"]
  ];
  List<List<String>> autoCompleteCharacter = [
    ["@"]
  ];
  List<List<String>> autoCompleteVoice = [
    ["  (画外音)"],
    ["  (旁白)"],
    ["  (O. S.)"],
    ["  (V. O.)"]
  ];
  List<List<String>> autoCompleteTransition = [
    [">"],
    [">叠化"],
    [">淡出淡入"],
    [">切到"],
    [">闪回"],
    [">淡出"],
    [">淡入"],
    [">闪回结束"],
    [">{=镜头交切=}", ">{=镜头交切=} (只含 以后 新场景)"],
    [">{#镜头交切#}", ">{#镜头交切#} (含 前一.当前.以后 场景)"],
    [">{+镜头交切+}", ">{+镜头交切+} (含 当前.以后 场景)"],
    [">{-结束交切-}"],
  ];

  List<String> autoCompleteSnippet = [
    "Title Page",
    "日期",
    "影片类型",
    "一句话梗概",
    "故事简介",
    "人设",
    "人设填空",
    "重复场景号 #\${}#",
    "标注 [[]]",
    "注释 /*  */",
    "括号 ()",
    "斜体     * *",
    "粗体    ** **",
    "粗斜体 *** ***",
    "下划线 _ _",
    "居中 > <",
    "分页 ===",
    "##",
    "=",
    "~",
  ];

  void addCompleteAfterParser(Statis statis, {Set<String>? dupSceneHeadings}) {
    // 处理 autoCompleteLocation - 按首字拼音或首字母升序排序
    autoCompleteLocation.clear();
    final locationsList = statis.locations.keys.toList();

    // 自定义排序函数，按首字的拼音或首字母排序
    locationsList.sort((a, b) {
      // 获取首字
      String firstCharA = a.isNotEmpty ? a[0] : '';
      String firstCharB = b.isNotEmpty ? b[0] : '';

      // 判断是否为英文字符
      bool isEnglishA = firstCharA.codeUnitAt(0) < 128;
      bool isEnglishB = firstCharB.codeUnitAt(0) < 128;

      // 如果两个都是英文或都是中文，直接比较
      if (isEnglishA == isEnglishB) {
        return a.compareTo(b);
      }

      // 如果一个是英文一个是中文，英文在前
      return isEnglishA ? -1 : 1;
    });

    for (var location in locationsList) {
      autoCompleteLocation.add([location]);
    }

    // 重置 autoCompleteScene 为默认内容，然后添加重复场景号的场景头

    // 清除旧的内容，重新基于默认内容添加
    autoCompleteScene.clear();
    autoCompleteScene.addAll(defaultAutoCompleteScene);

    // 如果有重复场景号的场景头，添加到 autoCompleteScene
    if (dupSceneHeadings != null && dupSceneHeadings.isNotEmpty) {
      for (var heading in dupSceneHeadings) {
        autoCompleteScene.add([heading]);
      }
    }

    // 处理 autoCompleteCharacter - 按字数降序排序
    autoCompleteCharacter.clear();
    final characterEntries = statis.characters.entries.toList();
    characterEntries.sort((a, b) => b.value.compareTo(a.value)); // 按字数降序排序
    final sortedCharacters =
        characterEntries.map((entry) => entry.key).toList();
    autoCompleteCharacter.add([""]); //加一个空的
    for (var character in sortedCharacters) {
      autoCompleteCharacter.add([character]);
    }
    //autoCompleteCharacter 全部加上前缀“@”
    List<List<String>> newAutoCompleteCharacter = [];
    for (var item in autoCompleteCharacter) {
      newAutoCompleteCharacter.add(["@${item[0]}"]);
    }
    autoCompleteCharacter = newAutoCompleteCharacter;
    // 处理 autoCompleteTime - 保持基础时间列表顺序，添加新时间
    final baseTimeList = [
      [" - 日"],
      [" - 夜"],
      [" - 黎明"],
      [" - 清晨"],
      [" - 傍晚"],
      [" - DAY"],
      [" - NIGHT"],
      [" - DAWN"],
      [" - MORNING"],
      [" - DUSK"]
    ];
    autoCompleteTime = List.from(baseTimeList);

    // 添加其他时间标记
    for (var time in statis.times.keys) {
      if (time == "不确定") {
        continue;
      }
      final formattedTimeStr = " - ${time.toUpperCase()}";
      final formattedTime = [formattedTimeStr];

      // 检查是否已存在相同的时间标记
      bool exists = false;
      for (var timeItem in autoCompleteTime) {
        if (timeItem.isNotEmpty && timeItem[0] == formattedTimeStr) {
          exists = true;
          break;
        }
      }

      if (!exists) {
        autoCompleteTime.add(formattedTime);
      }
    }
  }

  // 获取可见区域文本
  Future<void> formatText(int index, int len, Attribute? attribute,
      bool shouldNotifyListeners) async {
    // 清理 撤销/重做历史中，修改样式的 变化 历史记录，只保留插入或者删除的记录
    // 创建一个新列表，存储需要保留的元素
    final undoToKeep = _quillController.document.history.stack.undo
        .where((element) => element.last.isDelete || element.last.isInsert)
        .toList();

    // 同样处理 redo 列表
    final redoToKeep = _quillController.document.history.stack.redo
        .where((element) => element.last.isDelete || element.last.isInsert)
        .toList();

    _quillController.formatText(
      index,
      len,
      attribute,
      shouldNotifyListeners: shouldNotifyListeners,
    );

    // 清空原列表
    _quillController.document.history.stack.undo.clear();

    // 添加需要保留的元素
    _quillController.document.history.stack.undo.addAll(undoToKeep);

    // 清空原列表
    _quillController.document.history.stack.redo.clear();

    // 添加需要保留的元素
    _quillController.document.history.stack.redo.addAll(redoToKeep);

    // _fixDocHistory();
  }

  // 获取可见区域文本，基于光标位置的一个有限范围进行。
  Future<void> formatVisibleText() async {
    var minOffset = _quillController.selection.baseOffset - 300;
    var maxOffset = _quillController.selection.extentOffset + 300;

    final tot = _elements.length;
    RT:
    for (var i = 0; i < tot; i++) {
      final element = _elements[i];

      if (element.range.start + element.range.length < minOffset) {
        continue;
      }
      if (element.range.start > maxOffset) {
        break;
      }

      if (element.formated) {
        continue;
      }

      final styles = _getStyleForElement(element);
      if (styles != null) {
        for (var style in styles) {
          if (style != null) {
            if (_formatQueue.length >= _maxQueueLength) {
              break RT;
            }
            await formatText(
                element.range.start, element.range.length, style, false);
            _elements[i].formated = true;
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

  // 全文解析一次，并重置统计信息。
  Future<bool> parseFullTextAndStatis(String scene, Function? callback) async {
    final int thisParserTime =
        (DateTime.now().millisecondsSinceEpoch / 1000).toInt();
    if (thisParserTime == _lastParserFullTime[scene]) {
      return false;
    }
    _lastParserFullTime[scene] = thisParserTime;

    final fullText = _quillController.document.toPlainText();
    // _stateStatisNotifier.value = null;

    // 解析并格式化可见文本
    if (_parser.containsKey(scene)) {
      _parser[scene]!.cancel = true;
    }
    final parser = FountainParser();
    _parser[scene] = parser;
    // final parsed = await compute(_parseText, fullText);
    final parsed = await compute<Map<String, dynamic>, ParserOutput>(
      (Map<String, dynamic> params) {
        final text = params['text'] as String;
        return parser.parse(true, text);
      },
      {'text': fullText},
    );

    if ((_lastParserFullTime.containsKey(scene) &&
            _lastParserFullTime[scene]! > thisParserTime) ||
        parsed.canceled) {
      return false;
    }

    _stateStatisNotifier.value = parsed.statis;
    fisrtScencStarted = parsed.fisrtScencStarted;
    _charsPerMinu = parsed.charsPerMinu;
    _dialCharsPerMinu = parsed.dialCharsPerMinu;
    _startChars = parsed.startChars;
    _elements = parsed.elements;

    addCompleteAfterParser(parsed.statis!,
        dupSceneHeadings: parsed.dupSceneHeadings);

    if (callback != null) {
      callback();
    }

    return true;
  }

  // 全文格式一次
  Future<void> formatFullText() async {
    final int thisFormatFullTime =
        (DateTime.now().millisecondsSinceEpoch / 1000).toInt();
    if (thisFormatFullTime == _lastFormatingFullTime) {
      return;
    }
    _lastFormatingFullTime = thisFormatFullTime;
    _stateBarMsgNotifier.value = '全文语法样式刷新中...'; //状态栏显示状态。

    var succ = await parseFullTextAndStatis("refresh", null);
    if (!succ) {
      return;
    }

    bool wasBreak = false;
    // var i = 0;
    final tot = _elements.length;
    RTF:
    for (var i = 0; i < tot; i++) {
      final element = _elements[i];
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
            _elements[i].formated = true;
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

      var progress = '';
      var j = i + 1;
      if (j >= tot) {
        progress = '100%';
      } else {
        progress = '${(j / tot * 100).toStringAsFixed(0)}%';
      }
      if (!_stateBarMsgNotifier.value.startsWith('打开文件')) {
        _stateBarMsgNotifier.value = '全文语法样式刷新中... ($progress)';
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

      if (_openNewDocWaitInsertNotify || _openNewDocWaitDeleteNotify) {
        // 加载新文档
        if (change.change.last.key == 'insert') {
          _openNewDocWaitInsertNotify = false;
        } else if (change.change.last.key == 'delete') {
          _openNewDocWaitDeleteNotify = false;
        }
        return;
      }

      setState(() {
        _docChanged = _quillController.document.hasRedo ||
            _quillController.document.hasUndo;
      });

      if (!_editable) {
        // 实现编辑内容回滚，间接实现只读。
        if (_historyRollback) {
          // undo 之后的回调。
          _historyRollback = false;

          // 在只读模式下，用户操作了键盘输入
          // 检测并计数用户输入
          int currentTime = DateTime.now().millisecondsSinceEpoch;

          // 如果距离上次输入超过3秒，重置计数器
          if (currentTime - _lastReadOnlyInputTime > 3000) {
            _readOnlyInputCount = 1;
          } else {
            _readOnlyInputCount++;
          }

          // 更新最近一次输入时间
          _lastReadOnlyInputTime = currentTime;

          // 如果5秒内触发了3次或以上，启动图标闪烁
          if (_readOnlyInputCount >= 3) {
            _readOnlyInputCount = 0; // 重置计数器
            _startEditIconBlinking(); // 启动图标闪烁
          }

          return;
        } else {
          _historyRollback = true;
          _quillController.undo(); // 不能使用 _quillController.document.undo();
          _quillController.document.history.stack.redo.clear();
          _quillController.document.history.stack.redo.addAll(_lastRedo);
          return;
        }
      } else {
        _lastRedo.clear();
        _lastRedo.addAll(_quillController.document.history.stack.redo);
      }
      parseFullTextAndStatis("edit", () {
        if (_onlyEditRefresh) {
          addFormatTask();
        }
      });
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

  // 在isolate中解析文本
  // static Future<List<FountainElement>> _parseText(
  //     Statis? statis, String text) async {
  //   final parser = FountainParser();
  //   return parser.parse(statis, text);
  // }

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

  // 初始化Socket服务
  void _initSocketService() async {
    // 监听Socket事件
    _socketEventSubscription = _socketService.events.listen((event) {
      switch (event.type) {
        case SocketEventType.auth:
          // 处理认证事件
          final success = event.content == 'success';
          if (success) {
            _showSuccess('远程客户端认证成功');
          } else {
            _showError('远程客户端认证失败');
          }
          break;
        case SocketEventType.fetch:
          // 发送当前编辑器内容给客户端
          final content = _docText();
          _socketService.sendContent(content, event.socket);
          _showInfo('已将内容发送给远程客户端');
          break;
        case SocketEventType.push:
          // 将客户端发送的内容替换到编辑器
          if (event.content != null && event.content!.isNotEmpty) {
            _replaceTextFromRemote(event.content!);
          }
          break;
      }
    });

    // 监听Socket客户端事件
    SocketClient().events.listen((event) {
      if (event.type == SocketClientEventType.content) {
        if (event.content != null) {
          // 收到远程内容，替换到当前编辑器
          _replaceTextFromRemote(event.content!);
        }
      }
    });

    // 从共享首选项中加载端口设置并自动启动服务器
    final prefs = await SharedPreferences.getInstance();
    final autoStart = prefs.getBool('socket_auto_start') ?? false;
    if (autoStart) {
      final port = prefs.getInt('socket_port') ?? 8080;
      final password = prefs.getString('socket_password');
      final success =
          await _socketService.startServer(port, password: password);
      if (success) {
        final securityStatus =
            password != null && password.isNotEmpty ? '，已启用密码验证' : '';
        _showSuccess('远程同步服务已自动启动，端口: $port$securityStatus');
      }
    }
  }

  // 显示Socket客户端操作菜单
  void _showSocketClientMenu(BuildContext context) {
    final socketClient = SocketClient();
    final server = socketClient.currentServer;

    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text('已连接到 ${server?.name ?? "未知服务器"}'),
              subtitle: Text('${server?.host}:${server?.port}'),
              leading: const Icon(Icons.computer, color: Colors.green),
            ),
            const Divider(),
            ListTile(
              title: const Text('断开连接'),
              leading: const Icon(Icons.link_off),
              onTap: () {
                socketClient.disconnect();
                Navigator.pop(context);
              },
            ),
            ListTile(
              title: const Text('推送内容'),
              subtitle: const Text('将当前编辑器内容推送到远程服务器'),
              leading: const Icon(Icons.upload),
              onTap: () {
                final content = _docText();
                socketClient.pushContent(content);
                Navigator.pop(context);
                _showInfo('内容已推送到远程服务器');
              },
            ),
            ListTile(
              title: const Text('拉取内容'),
              subtitle: const Text('从远程服务器获取内容并替换当前编辑器'),
              leading: const Icon(Icons.download),
              onTap: () {
                socketClient.fetchContent();
                Navigator.pop(context);
                _showInfo('正在从远程服务器获取内容...');
              },
            ),
          ],
        ),
      ),
    );
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

    // 初始化 autoCompleteScene
    autoCompleteScene = List.from(defaultAutoCompleteScene);

    // 设置初始的只读状态，与工具栏状态一致
    // _quillController.readOnly = !_editable;

    _setupFormatListener();
    _initSocketService();
  }

  // 处理编辑图标闪烁效果
  void _startEditIconBlinking() {
    // 如果已经有定时器在运行，先取消
    _editIconBlinkTimer?.cancel();

    // 闪烁计数器
    int blinkCount = 0;
    const int totalBlinks = 25; // 闪烁次数

    // 创建定时器，每0.5秒切换一次颜色
    _editIconBlinkTimer =
        Timer.periodic(const Duration(milliseconds: 100), (timer) {
      setState(() {
        // 在灰色和红色之间切换
        _editIconColor =
            _editIconColor == Colors.black ? Colors.red : Colors.black;
      });

      blinkCount++;
      if (blinkCount >= totalBlinks) {
        // 闪烁结束后恢复原来的颜色
        setState(() {
          _editIconColor = Colors.black;
        });
        timer.cancel();
        _editIconBlinkTimer = null;
      }
    });
  }

  @override
  void dispose() {
    _editIconBlinkTimer?.cancel();
    _socketEventSubscription?.cancel();
    _socketService.dispose();
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
          if (Platform.isAndroid) {
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
                filePath = '$dirPath/$filePath';
              }
            }
            if (filePath == null) {
              throw Exception('无法获取文件路径');
            }

            // 解码URL编码的路径
            filePath = Uri.decodeFull(filePath);
          } else {
            filePath = file.path;
            if (filePath == null) {
              throw Exception('无法获取文件路径');
            }
          }

          // 检查文件是否可访问
          if (!await File(filePath).exists()) {
            throw Exception('文件不存在或无法访问');
          }

          _stateBarMsgNotifier.value = '打开文件中...($filePath)'; //状态栏显示状态。

          Future.delayed(const Duration(milliseconds: 5), () async {
            try {
              // 读取文件内容
              // String content = await File(filePath).readAsString();
              String content = await File(file.path!).readAsString();
              // final delta = Delta()..insert('$content\n');
              // _quillController.clear();

              _openNewDocWaitInsertNotify = true; // 等待回调， 一个 insert
              if (!_quillController.document.isEmpty()) {
                _openNewDocWaitDeleteNotify = true;
              }
              _quillController.replaceText(
                  0,
                  _quillController.document.length - 1,
                  content,
                  const TextSelection.collapsed(offset: 0));

              int total = _quillController.document.length - 1;
              if (total < 0) total = 0;
              _charsLenNotifier.value = [
                _quillController.selection.baseOffset,
                total
              ]; //更新状态光标偏移统计；
              _quillController.document.history.clear();

              FilePicker.platform.clearTemporaryFiles();

              // 更新当前文件路径
              // setState(() {
              // _currentFilePath = filePath!;
              // });
              _titleEditingController.text = filePath!;
              // 在下一次ui刷新后再执行
              Future.delayed(const Duration(milliseconds: 500), () {
                _titleScrollController
                    .jumpTo(_titleScrollController.position.maxScrollExtent);
              });
              Future.delayed(const Duration(milliseconds: 2), () {
                // 触发格式更新
                // addFormatTask();//部分格式
                formatFullText(); //全文格式
              });
              setState(() {
                // 更新编辑器的只读状态
                _editable = false;
                _docChanged = false;
                _historyRollback = false;
                // _quillController.readOnly = true;
              });
            } catch (e) {
              _showError('打开文件失败: $e');
              _stateBarMsgNotifier.value = ''; //恢复0，为状态栏显示状态。
            }
          });
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

      if (Platform.isIOS || (!savePath.contains('/') && !Platform.isAndroid)) {
        // ios 每次保存都要选择保存路径，是另存为，只能支持这样了。控件 open file 拿到的是临时文件路径，没办法拿到实际。
        // 其他平台，只有新文件才需要选择保存路径。
        Directory directory;
        String fileName = 'script.fountain';
        directory = await getApplicationDocumentsDirectory();
        // 用时间戳做文件名
        if (!savePath.endsWith('.fountain')) {
          savePath = '$savePath.fountain';
        }
        fileName = savePath.substring(savePath.lastIndexOf('/') + 1);

        var plainText = _docText();
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
      } else if (!savePath.contains('/')) {
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
              filePath = '$dirPath/$filePath';
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
          savePath = '${f.parent.path}/$fileName';

          // 写入文件内容
          final file2 = File(savePath);
          if (file2.existsSync()) {
            _showError('新建文件失败: 文件名 [ $fileName ] 在相同目录下已存在，请换一个名称');
            return;
          }
          var plainText = _docText();
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
        }
        //  else {
        //   directory = await getApplicationDocumentsDirectory();
        //   // 用时间戳做文件名
        //   if (!savePath.endsWith('.fountain')) {
        //     savePath = '$savePath.fountain';
        //   }
        //   fileName = savePath;

        //   var plainText = _quillController.document.toPlainText();
        //   if (plainText.endsWith('\n')) {
        //     plainText = plainText.substring(
        //         0,
        //         plainText.length -
        //             1); //_quillController.document.toPlainText()方法，会自动在文末加一个\n换行符
        //   }
        //   Uint8List bytes = Utf8Codec().encode(plainText);

        //   // 其他平台使用FilePicker选择保存位置
        //   await FilePicker.platform.clearTemporaryFiles();
        //   final result = await FilePicker.platform.saveFile(
        //     dialogTitle: '保存Fountain文件',
        //     fileName: fileName,
        //     initialDirectory: directory.path,
        //     allowedExtensions: ['fountain'],
        //     lockParentWindow: true,
        //     bytes: bytes,
        //   );

        //   if (result == null) return;
        //   // savePath = result.endsWith('.fountain') ? result : '$result.fountain';
        //   savePath =
        //       result; // TODO Arming (2025-03-12) : android 保存文件时，切换目录保存，会有bug。保存的文件实际在切换了的目录了，但返回的result总是Download目录下的地址。
        // }
      } else {
        // 写入文件内容
        var plainText = _docText();
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
        _showSuccess('文件保存成功: $savePath');
      }
      _quillController.document.history.clear();
      setState(() {
        _docChanged = false;
      });
    } catch (e) {
      if (mounted) {
        _showError('保存文件失败: $e');
        // _titleEditingController.text = '/errror/';
      }
    } finally {
      _isFilePickerActive = false;
    }
  }

  void _showError(String message, {int milliseconds = 2000}) {
    _showToast(message, Colors.red, milliseconds);
  }

  void _showSuccess(String message, {int milliseconds = 2000}) {
    // _showToast(message, Colors.green[300]!, milliseconds);
    toastification.show(
        context: context,
        title: Text(message),
        autoCloseDuration: Duration(milliseconds: milliseconds),
        type: ToastificationType.success,
        style: ToastificationStyle.flat,
        alignment: Alignment.center,
        primaryColor: Colors.green[700],
        backgroundColor: Colors.green[300],
        foregroundColor: Colors.white,
        closeButton: ToastCloseButton(showType: CloseButtonShowType.none));
  }

  void _showInfo(String message, {int milliseconds = 2000}) {
    // _showToast(message, Colors.green[300]!, milliseconds);
    toastification.show(
        context: context,
        title: Text(message),
        autoCloseDuration: Duration(milliseconds: milliseconds),
        style: ToastificationStyle.simple,
        alignment: Alignment.center,
        primaryColor: Colors.green[700],
        backgroundColor: Colors.blue[300],
        foregroundColor: Colors.white,
        closeButton: ToastCloseButton(showType: CloseButtonShowType.none));
  }

  void _showToast(String message, Color color, int milliseconds) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: Duration(milliseconds: milliseconds),
      ),
    );
  }

  // 从文本内容打开新文档
  void _replaceTextFromRemote(String content) {
    if (!_editable) {
      _editable = true; // 强制切换到编辑模式
      // needPopEditbar = true;
    }

    _quillController.replaceText(0, _quillController.document.length - 1,
        content, const TextSelection.collapsed(offset: 0));

    int total = _quillController.document.length - 1;
    if (total < 0) total = 0;
    _charsLenNotifier.value = [_quillController.selection.baseOffset, total];
    _showInfo('已从远程 接收并更新内容');

    // 触发格式更新
    Future.delayed(const Duration(milliseconds: 2), () {
      setState(() {});
      formatFullText(); // 全文格式
    });
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
        if ((element.featureText.trim().startsWith('{=') &&
                element.featureText.trim().endsWith('=}')) ||
            (element.featureText.trim().startsWith('{#') &&
                element.featureText.trim().endsWith('#}')) ||
            (element.featureText.trim().startsWith('{+') &&
                element.featureText.trim().endsWith('+}')) ||
            (element.featureText.trim().startsWith('{-') &&
                element.featureText.trim().endsWith('-}'))) {
          // 交切
          return [
            // Attribute.fromKeyValue(Attribute.font.key, "Courier"),
            Attribute.fromKeyValue(Attribute.size.key, "18"),
            Attribute.fromKeyValue(Attribute.bold.key, true),
            Attribute.fromKeyValue(Attribute.italic.key, null),
            Attribute.fromKeyValue(Attribute.color.key, '#d853ce')
          ];
        }
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

  // 在当前光标位置插入文本
  void _insertTextAtCursor(String text) {
    final index = _quillController.selection.baseOffset;
    _quillController.replaceText(index, 0, text, null);

    // 将光标移动到插入文本的末尾
    final newPosition = index + text.length;
    _quillController.updateSelection(
        TextSelection.collapsed(offset: newPosition), ChangeSource.local);
  }

  // 在当前光标位置插入括号, 如果选择_quillController.selection选择的长度大于零，在 quillController.selection.baseOffset 插入括号的前半部，再插入原来内容，再插入括号后半部，最后光标在括号内
  void _insertBracketsAtCursor(String brackets, {int offset = 1}) {
    final backetsHalfLen =
        offset > 0 ? (brackets.length ~/ 2) : brackets.length + offset;
    final index = _quillController.selection.baseOffset;
    final length = _quillController.selection.extentOffset -
        _quillController.selection.baseOffset;
    if (length > 0) {
      final text = _quillController.document
          .toPlainText()
          .substring(index, index + length);
      _quillController.replaceText(
          index,
          length,
          brackets.substring(0, backetsHalfLen) +
              text +
              brackets.substring(backetsHalfLen),
          null);
    } else {
      _quillController.replaceText(index, 0, brackets, null);
    }
    final newPosition = index + backetsHalfLen + length;
    _quillController.updateSelection(
        TextSelection.collapsed(offset: newPosition), ChangeSource.local);
  }

  String _docText() {
    var plainText = _quillController.document.toPlainText();
    if (plainText.endsWith('\n')) {
      plainText = plainText.substring(
          0,
          plainText.length -
              1); //_quillController.document.toPlainText()方法，会自动在文末加一个\n换行符
    }
    return plainText;
  }

  // 找出光标当前位置，前后有换行符的内容，判断为行， 删除当前行
  void _deleteLine() {
    try {
      // 处理特殊情况：文本为空
      if (_quillController.document.isEmpty()) {
        return; // 文本为空，无需删除
      }

      // 获取当前文本内容
      final text = _docText();

      // 确保光标位置在文本范围内
      int index = _quillController.selection.baseOffset;
      if (index < 0) {
        index = 0;
      } else if (index > text.length) {
        index = text.length;
      }

      // 找出光标前最近的换行符（包含该换行符）
      int start;
      if (index <= 0) {
        // 如果光标在文档开头，则从文档开头开始删除
        start = 0;
      } else {
        // 找出光标前最近的换行符
        int lastNewLineIndex = text.lastIndexOf('\n', index - 1);
        if (lastNewLineIndex >= 0) {
          // 如果找到换行符，则从该换行符开始删除（包含该换行符）
          start = lastNewLineIndex;
        } else {
          // 如果没有找到换行符，则从文档开头开始删除
          start = 0;
        }
      }

      // 找出光标后最近的换行符（不包含该换行符）
      int end;
      int nextNewLineIndex = text.indexOf('\n', index);
      if (nextNewLineIndex >= 0) {
        // 如果找到换行符，则删除到该换行符（不包含该换行符）
        end = nextNewLineIndex;
        if (start == 0) {
          end++; // 如果从文档第一行，没有前面的换行符，需要包含后一个换行符
        }
      } else {
        // 如果没有找到换行符，则删除到文档结尾
        end = text.length;
      }

      if (end <= start) return; // 如果范围无效，直接返回

      // 使用安全的方式执行删除操作
      try {
        // 执行删除操作
        _quillController.replaceText(
            start, end - start, '', TextSelection.collapsed(offset: start));
      } catch (e) {
        // 如果删除操作失败，尝试使用更安全的方式
      }
    } catch (e) {
      // 捕获所有异常，确保不会崩溃
    }
  }

  // 光标向前移动
  void _moveCursorForward() {
    final currentPosition = _quillController.selection.baseOffset;
    final documentLength = _quillController.document.length;

    // 确保不超出文档范围
    if (currentPosition < documentLength - 1) {
      final newPosition = currentPosition + 1;
      _quillController.updateSelection(
          TextSelection.collapsed(offset: newPosition), ChangeSource.local);
    }
  }

  // 光标向前移动多步
  void _moveCursorForwardMultiple(int steps) {
    final currentPosition = _quillController.selection.baseOffset;
    final documentLength = _quillController.document.length;

    // 确保不超出文档范围
    if (currentPosition < documentLength - 1) {
      int newPosition = currentPosition + steps;
      if (newPosition >= documentLength) {
        newPosition = documentLength - 1;
      }
      _quillController.updateSelection(
          TextSelection.collapsed(offset: newPosition), ChangeSource.local);
    }
  }

  // 光标向后移动
  void _moveCursorBackward() {
    final currentPosition = _quillController.selection.baseOffset;

    // 确保不超出文档范围
    if (currentPosition > 0) {
      final newPosition = currentPosition - 1;
      _quillController.updateSelection(
          TextSelection.collapsed(offset: newPosition), ChangeSource.local);
    }
  }

  // 光标向后移动多步
  void _moveCursorBackwardMultiple(int steps) {
    final currentPosition = _quillController.selection.baseOffset;

    // 确保不超出文档范围
    if (currentPosition > 0) {
      int newPosition = currentPosition - steps;
      if (newPosition < 0) {
        newPosition = 0;
      }
      _quillController.updateSelection(
          TextSelection.collapsed(offset: newPosition), ChangeSource.local);
    }
  }

  // 显示下拉列表
  void _showDropdownMenu(
      BuildContext context, List<List<String>> items, String title) {
    final RenderBox button = context.findRenderObject() as RenderBox;
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final RelativeRect position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(Offset.zero, ancestor: overlay),
        button.localToGlobal(button.size.bottomRight(Offset.zero),
            ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );

    // 自定义紧凑的菜单项样式
    final customMenuItemHeight = 30.0; // 默认是48.0
    final customMenuItemPadding =
        const EdgeInsets.symmetric(horizontal: 16.0, vertical: 1.0); // 默认是16.0

    showMenu<String>(
      context: context,
      position: position,
      // 设置菜单项之间的间距
      elevation: 1.0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(1.0)),
      items: [
        PopupMenuItem<String>(
          enabled: false,
          height: customMenuItemHeight,
          padding: customMenuItemPadding,
          child: Text(title,
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.0)),
        ),
        ...items.map((List<String> item) => PopupMenuItem<String>(
              value: item[0],
              height: customMenuItemHeight,
              padding: customMenuItemPadding,
              child: Text(item.length > 1 ? item[1] : item[0],
                  style: TextStyle(fontSize: 13.0)),
            )),
      ],
    ).then((String? selectedValue) {
      if (selectedValue != null) {
        _insertTextAtCursor(selectedValue);
      }
    });
  }

  // 显示代码片段下拉列表
  void _showDropdownMenuOfSnippet(
      BuildContext context, List<String> items, String title) {
    final RenderBox button = context.findRenderObject() as RenderBox;
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final RelativeRect position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(Offset.zero, ancestor: overlay),
        button.localToGlobal(button.size.bottomRight(Offset.zero),
            ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );

    // 自定义紧凑的菜单项样式
    final customMenuItemHeight = 30.0; // 默认是48.0
    final customMenuItemPadding =
        const EdgeInsets.symmetric(horizontal: 16.0, vertical: 1.0); // 默认是16.0

    showMenu<String>(
      context: context,
      position: position,
      // 设置菜单项之间的间距
      elevation: 1.0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(1.0)),
      items: [
        PopupMenuItem<String>(
          enabled: false,
          height: customMenuItemHeight,
          padding: customMenuItemPadding,
          child: Text(title,
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.0)),
        ),
        ...items.map((String item) => PopupMenuItem<String>(
              value: item,
              height: customMenuItemHeight,
              padding: customMenuItemPadding,
              child: Text(item, style: TextStyle(fontSize: 13.0)),
            )),
      ],
    ).then((String? selectedValue) {
      if (selectedValue != null) {
        _insertSnippetByName(selectedValue);
      }
    });
  }

  void _insertSnippetByName(String name) {
    switch (name) {
      case "Title Page":
        // 获取当前日期
        final currentDate = DateFormat('yyyy/MM/dd').format(DateTime.now());
        _insertTextAtCursor('''Title: **《》**
Credit: 作者
Author: Arming
Draft Date: $currentDate
Contact: arming.lou@foxmail.com
Font: Source Han Sans
Font Italic: FZKai-Z03

Metadata: {
    "userPassword":"",
    "ownerPassword":"Arm_ing",
    "permissions":{
        "printing":false,
        "modifying":false,
        "copying":false,
        "annotating":false,
        "fillingForms":false,
        "contentAccessibility":false,
        "documentAssembly":false
    },
    "chars_per_minu": 243.22,
    "dial_chars_per_minu": 171,
    "chinaFormat": 1,
    "embedFonts": false,
    "print": {
        "paper_size": "a4",
        "font_size": 12,
        "character_spacing": 1,
        "note_font_size": 9,
        "lines_per_page": 30,
        "top_margin": 1.19,
        "bottom_margin": 1,
        "page_width": 8.27,
        "page_height": 11.69,
        "left_margin": 1.5,
        "right_margin": 1.5,
        "font_width": 0.1,
        "note_line_height": 0.17,
        "page_number_top_margin": 0.4
    }
}''');
        return;

      case "日期":
        final currentDate = DateFormat('yyyy/MM/dd').format(DateTime.now());
        _insertTextAtCursor(currentDate);
        return;

      case "影片类型":
        _insertTextAtCursor('''#影片类型
/* 情感类型 / 情节类型 / 情绪类型 */
**类型：** ''');
        return;

      case "一句话梗概":
        _insertTextAtCursor('''#一句话梗概
**一句话梗概：**
''');
        return;

      case "故事简介":
        _insertTextAtCursor('''#故事简介
**故事简介：**
''');
        return;

      case "人设":
        _insertTextAtCursor('''#人设
**人物设定：**

''');
        return;

      case "人设填空":
        _insertTextAtCursor('''(基本信息)
(+可怜之处，最大困境)
(-羡慕之处)
(+过人之处)
(-缺陷之处)
(+光辉之处)
(-不足之处)
(=结局特质)
''');
        return;

      case "重复场景号 #\${}#":
        _insertBracketsAtCursor(" #\${}#", offset: -2);
        return;

      case "标注 [[]]":
        _insertBracketsAtCursor("[[]]");
        return;

      case "注释 /*  */":
        _insertBracketsAtCursor("/*  */");
        return;

      case "括号 ()":
        _insertBracketsAtCursor("()");
        return;

      case "斜体     * *":
        _insertBracketsAtCursor("**");
        return;

      case "粗体    ** **":
        _insertBracketsAtCursor("****");
        return;

      case "粗斜体 *** ***":
        _insertBracketsAtCursor("******");
        return;

      case "下划线 _ _":
        _insertBracketsAtCursor("__");
        return;

      case "居中 > <":
        _insertBracketsAtCursor("><");
        return;

      case "分页 ===":
        _insertTextAtCursor("===");
        return;

      default:
        _insertTextAtCursor(name);
        return;
    }
  }

  // 创建工具栏组件
  final Color disbaleColor = Color.fromARGB(20, 0, 0, 0);
  Widget _buildToolbar() {
    // 定义图标大小和按钮大小，使其更紧凑
    const double iconSize = 18.0; // 进一步缩小图标大小
    const VisualDensity visualDensity =
        VisualDensity(horizontal: -1.0, vertical: -4.0); // 最小化按钮内边距

    return Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        height: 30, // 进一步减小工具栏高度
        color: const Color.fromARGB(255, 240, 240, 240),
        padding: const EdgeInsets.symmetric(horizontal: 0), // 移除水平内边距
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween, // 两端对齐
          children: [
            // 左侧下拉菜单按钮组
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal, // 水平滚动
                physics: const BouncingScrollPhysics(), // 滚动物理效果
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.start, // 左对齐，便于滚动
                  crossAxisAlignment: CrossAxisAlignment.center, // 垂直居中
                  mainAxisSize: MainAxisSize.min, // 根据子组件确定大小
                  children: [
                    // 添加小间距，作为左侧的空白
                    const SizedBox(width: 4),
                    // 场景标记按钮
                    Builder(
                      builder: (context) => IconButton(
                        icon: Icon(Icons.movie, size: iconSize),
                        tooltip: '场景标记',
                        onPressed: () {
                          _showDropdownMenu(context, autoCompleteScene, '场景标记');
                        },
                        visualDensity: visualDensity,
                      ),
                    ),
                    // 场景位置按钮
                    Builder(
                      builder: (context) => IconButton(
                        disabledColor: disbaleColor,
                        icon: Icon(Icons.place, size: iconSize),
                        tooltip: '场景位置',
                        onPressed: autoCompleteLocation.isEmpty
                            ? null
                            : () {
                                _showDropdownMenu(
                                    context, autoCompleteLocation, '场景位置');
                              },
                        visualDensity: visualDensity,
                      ),
                    ),
                    // 时间标记按钮
                    Builder(
                      builder: (context) => IconButton(
                        icon: Icon(Icons.wb_sunny_rounded, size: iconSize),
                        tooltip: '时间标记',
                        onPressed: () {
                          _showDropdownMenu(context, autoCompleteTime, '时间标记');
                        },
                        visualDensity: visualDensity,
                      ),
                    ),
                    // 角色名称按钮
                    Builder(
                      builder: (context) => IconButton(
                        icon: Icon(Icons.person, size: iconSize),
                        tooltip: '角色名称',
                        onPressed: () {
                          _showDropdownMenu(
                              context, autoCompleteCharacter, '角色名称');
                        },
                        visualDensity: visualDensity,
                      ),
                    ),

                    // 画外音/旁白按钮
                    Builder(
                      builder: (context) => IconButton(
                        icon: Icon(Icons.record_voice_over, size: iconSize),
                        tooltip: '画外音/旁白',
                        onPressed: () {
                          _showDropdownMenu(
                              context, autoCompleteVoice, '画外音/旁白');
                        },
                        visualDensity: visualDensity,
                      ),
                    ),

                    // 转场标记按钮
                    Builder(
                      builder: (context) => IconButton(
                        icon: Icon(Icons.compare_sharp, size: iconSize),
                        tooltip: '转场标记',
                        onPressed: () {
                          _showDropdownMenu(
                              context, autoCompleteTransition, '转场标记');
                        },
                        visualDensity: visualDensity,
                      ),
                    ),

                    // 代码片段
                    Builder(
                      builder: (context) => IconButton(
                        icon: Icon(Icons.integration_instructions_outlined,
                            size: iconSize),
                        tooltip: '代码片段',
                        onPressed: () {
                          _showDropdownMenuOfSnippet(
                              context, autoCompleteSnippet, '代码片段');
                        },
                        visualDensity: visualDensity,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      // 第二层工具栏
      Container(
        height: 30, // 进一步减小工具栏高度
        color: const Color.fromARGB(255, 240, 240, 240),
        padding: const EdgeInsets.symmetric(horizontal: 0), // 移除水平内边距
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween, // 两端对齐
          children: [
            // 左侧下拉菜单按钮组
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal, // 水平滚动
                physics: const BouncingScrollPhysics(), // 滚动物理效果
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.start, // 左对齐，便于滚动
                  crossAxisAlignment: CrossAxisAlignment.center, // 垂直居中
                  mainAxisSize: MainAxisSize.min, // 根据子组件确定大小
                  children: [
                    // 添加小间距，作为左侧的空白
                    const SizedBox(width: 4),
                    // 刷新语法样式
                    Builder(
                      builder: (context) => IconButton(
                        disabledColor: disbaleColor,
                        icon: Icon(Icons.refresh, size: iconSize),
                        tooltip: '刷新语法样式',
                        onPressed: _docChanged ? formatFullText : null,
                        padding: EdgeInsets.only(right: 0, left: 0),
                        visualDensity: visualDensity,
                      ),
                    ),

                    // 分隔线
                    Container(
                      height: 20,
                      width: 1,
                      color: Colors.grey[300],
                      margin: const EdgeInsets.symmetric(horizontal: 1),
                    ),

                    // 撤销
                    Builder(
                      builder: (context) => IconButton(
                        disabledColor: disbaleColor,
                        icon: Icon(Icons.undo, size: iconSize),
                        tooltip: '撤销',
                        onPressed: _quillController.document.hasUndo
                            ? _quillController.undo
                            : null,
                        visualDensity: visualDensity,
                      ),
                    ),

                    // 重做
                    Builder(
                      builder: (context) => IconButton(
                        disabledColor: disbaleColor,
                        icon: Icon(Icons.redo, size: iconSize),
                        tooltip: '重做',
                        onPressed: _quillController.document.hasRedo
                            ? _quillController.redo
                            : null,
                        visualDensity: visualDensity,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // 删除行
            Builder(
              builder: (context) => IconButton(
                icon: Icon(Icons.disabled_by_default_outlined, size: iconSize),
                tooltip: '删除行',
                onPressed: _deleteLine,
                padding: EdgeInsets.only(right: 0, left: 0),
                visualDensity: visualDensity,
              ),
            ),

            // 分隔线
            Container(
              height: 20,
              width: 1,
              color: Colors.grey[300],
              margin: const EdgeInsets.symmetric(horizontal: 1),
            ),

            // 右侧光标控制按钮组
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // 光标向后移动按钮
                Container(
                  width: 30.0,
                  height: 30.0,
                  margin: const EdgeInsets.symmetric(horizontal: 2.0),
                  child: GestureDetector(
                    onLongPress: () {
                      // 记录长按开始时间
                      _longPressStartTime =
                          DateTime.now().millisecondsSinceEpoch;

                      // 初始化移动速度变量
                      int moveInterval = _cursorMoveInterval;
                      int moveSteps = 1;

                      // 创建定时器变量
                      Timer? cursorTimer;

                      // 长按时启动定时器，连续移动光标
                      cursorTimer = Timer.periodic(
                          Duration(milliseconds: moveInterval), (timer) {
                        // 计算长按时间
                        int pressDuration =
                            DateTime.now().millisecondsSinceEpoch -
                                _longPressStartTime;

                        // 根据长按时间调整移动速度和步长
                        if (pressDuration > 1000) {
                          // 1秒后开始加速
                          moveSteps = 5; // 每次移动更多字符

                          // 减少定时器间隔，加快移动速度
                          int newInterval = _cursorMoveInterval -
                              ((pressDuration - 1000) ~/ 500) *
                                  _cursorAccelerationStep;
                          if (newInterval < _minCursorMoveInterval) {
                            newInterval = _minCursorMoveInterval;
                          }

                          // 如果间隔发生变化，重新创建定时器
                          if (newInterval != moveInterval) {
                            moveInterval = newInterval;
                            timer.cancel();
                            _backwardTimer = Timer.periodic(
                                Duration(milliseconds: moveInterval),
                                (newTimer) {
                              _moveCursorBackwardMultiple(moveSteps);
                            });
                          }
                        }

                        // 移动光标
                        _moveCursorBackwardMultiple(moveSteps);
                      });

                      // 存储定时器引用，以便在松开时取消
                      _backwardTimer = cursorTimer;
                    },
                    onLongPressEnd: (_) {
                      // 松开时停止定时器
                      _backwardTimer?.cancel();
                      _backwardTimer = null;
                      _longPressStartTime = 0;
                    },
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: _moveCursorBackward,
                        child: Icon(Icons.arrow_back, size: iconSize),
                      ),
                    ),
                  ),
                ),
                // 光标向前移动按钮
                Container(
                  width: 30.0,
                  height: 30.0,
                  margin: const EdgeInsets.symmetric(horizontal: 2.0),
                  child: GestureDetector(
                    onLongPress: () {
                      // 记录长按开始时间
                      _longPressStartTime =
                          DateTime.now().millisecondsSinceEpoch;

                      // 初始化移动速度变量
                      int moveInterval = _cursorMoveInterval;
                      int moveSteps = 1;

                      // 创建定时器变量
                      Timer? cursorTimer;

                      // 长按时启动定时器，连续移动光标
                      cursorTimer = Timer.periodic(
                          Duration(milliseconds: moveInterval), (timer) {
                        // 计算长按时间
                        int pressDuration =
                            DateTime.now().millisecondsSinceEpoch -
                                _longPressStartTime;

                        // 根据长按时间调整移动速度和步长
                        if (pressDuration > 1000) {
                          // 1秒后开始加速
                          moveSteps = 5; // 每次移动更多字符

                          // 减少定时器间隔，加快移动速度
                          int newInterval = _cursorMoveInterval -
                              ((pressDuration - 1000) ~/ 500) *
                                  _cursorAccelerationStep;
                          if (newInterval < _minCursorMoveInterval) {
                            newInterval = _minCursorMoveInterval;
                          }

                          // 如果间隔发生变化，重新创建定时器
                          if (newInterval != moveInterval) {
                            moveInterval = newInterval;
                            timer.cancel();
                            _forwardTimer = Timer.periodic(
                                Duration(milliseconds: moveInterval),
                                (newTimer) {
                              _moveCursorForwardMultiple(moveSteps);
                            });
                          }
                        }

                        // 移动光标
                        _moveCursorForwardMultiple(moveSteps);
                      });

                      // 存储定时器引用，以便在松开时取消
                      _forwardTimer = cursorTimer;
                    },
                    onLongPressEnd: (_) {
                      // 松开时停止定时器
                      _forwardTimer?.cancel();
                      _forwardTimer = null;
                      _longPressStartTime = 0;
                    },
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: _moveCursorForward,
                        child: Icon(Icons.arrow_forward, size: iconSize),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      )
    ]);
  }

  // 切换工具栏显示/隐藏的方法已经在状态栏按钮中实现

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
          // IconButton(
          //   icon: const Icon(Icons.refresh),
          //   onPressed: formatFullText,
          // ),
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
            disabledColor: const Color.fromARGB(20, 0, 0, 0),
            onPressed: _docChanged ? _saveFile : null,
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
            ValueListenableBuilder<String>(
              valueListenable: _stateBarMsgNotifier,
              builder: (context, msg, _) {
                if (msg.isEmpty) {
                  // 返回空白：
                  return SizedBox.shrink();
                } else {
                  return Container(
                    height: 20,
                    color: Color.fromARGB(255, 245, 119, 65),
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            softWrap: false,
                            overflow: TextOverflow.ellipsis,
                            msg,
                            style: const TextStyle(
                                fontSize: 12,
                                color: Color.fromARGB(255, 255, 255, 255)),
                          ),
                        ),
                      ],
                    ),
                  );
                }
              },
            ),
            // 根据状态显示或隐藏工具栏
            if (_editable) _buildToolbar(),
            Container(
              height: 24,
              color: Color.fromARGB(255, 210, 210, 210),
              // padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  ValueListenableBuilder<SocketServiceStatus>(
                    valueListenable: _socketService.status,
                    builder: (context, status, _) {
                      final isRunning = status == SocketServiceStatus.running;
                      return Material(
                        color: Colors.transparent,
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          child: SizedBox(
                            width: 24,
                            height: 24,
                            child: Icon(
                              isRunning ? Icons.cloud_circle: Icons.cloud_off,
                              color: isRunning ? Colors.green : null,
                              size: 16,
                            ),
                          ),
                          // tooltip: isRunning ? '远程同步服务已启动' : '远程同步设置',
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    const SocketSettingsPage(),
                              ),
                            );
                          },
                          // padding: EdgeInsets.zero,
                          // constraints: BoxConstraints(),
                        ),
                      );
                    },
                  ),
                  // 远程同步客户端按钮
                  ValueListenableBuilder<SocketClientStatus>(
                    valueListenable: SocketClient().status,
                    builder: (context, status, _) {
                      final isConnected =
                          status == SocketClientStatus.connected;
                      return Material(
                        color: Colors.transparent,
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          child: SizedBox(
                            width: 30,
                            height: 24,
                            child: Icon(
                              isConnected ? Icons.file_download_sharp : Icons.file_download_off_sharp,
                              color: isConnected ? Colors.green : Colors.black,
                              size: 18,
                            ),
                          ),
                          onTap: () {
                            if (isConnected) {
                              // 已连接，显示操作菜单
                              _showSocketClientMenu(context);
                            } else {
                              // 未连接，打开连接页面
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      const SocketClientPage(),
                                ),
                              );
                            }
                          },
                        ),
                      );
                    },
                  ),
                  const SizedBox(width: 10),
                  // 工具栏切换按钮
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      child: SizedBox(
                        width: 30,
                        height: 24,
                        child: Icon(
                          _editable ? Icons.edit_sharp : Icons.edit_off_sharp,
                          size: 16,
                          color: _editable
                              ? Colors.green
                              : _editIconColor, // 使用可变颜色变量
                        ),
                      ),
                      // tooltip: '切换只读/编辑模式',
                      onTap: () {
                        _showInfo("进入${_editable ? '只读' : '编辑'}模式");
                        setState(() {
                          _editable = !_editable;
                          if (!_editable) {
                            _historyRollback = false;
                            _editIconColor = Colors.black; // 重置图标颜色
                            _editIconBlinkTimer?.cancel(); // 取消正在进行的闪烁
                            _editIconBlinkTimer = null;
                          }
                          // 更新编辑器的只读状态
                          // _quillController.readOnly = !_editable;
                        });
                      },
                      // padding: EdgeInsets.only(),
                      // constraints: BoxConstraints(),
                    ),
                  ),
                  // 空白间距
                  // const SizedBox(width: 15),
                  ValueListenableBuilder<Statis?>(
                    valueListenable: _stateStatisNotifier,
                    builder: (context, statis, _) {
                      final emp = statis == null || statis.isEmpty();
                      return Material(
                        color: Colors.transparent,
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          child: SizedBox(
                            width: 30,
                            height: 24,
                            child: Icon(Icons.bar_chart,
                                size: 18,
                                color: emp ? disbaleColor : Colors.black),
                          ),
                          onTap: () {
                            if (!emp) {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => StatsPage(
                                    statis: statis,
                                    dialCharsPerMinu: _dialCharsPerMinu,
                                  ),
                                ),
                              );
                            }
                          },
                          // padding: EdgeInsets.zero,
                          // constraints: BoxConstraints(),
                        ),
                      );
                    },
                  ),
                  SizedBox(width: 5),
                  Text(
                    '字数:',
                    style: const TextStyle(fontSize: 12),
                  ),
                  Listener(
                    onPointerDown: _onTapDownSlider,
                    onPointerMove: _onTapMoveSlider,
                    child: ValueListenableBuilder<List<int>>(
                      valueListenable: _charsLenNotifier,
                      builder: (context, arr, _) {
                        // 预估时间处理：
                        String totalLabel = '';
                        String currLabel = '';
                        if (fisrtScencStarted) {
                          int total = arr[1] - _startChars;
                          int curr = arr[0] - _startChars;
                          if (curr < 0) curr = 0;
                          double totalMinu = total / _charsPerMinu;
                          double currMinu = curr / _charsPerMinu;

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
                        } else {
                          currLabel = '0”';
                          totalLabel = '0”';
                        }
                        // 计算百分比，确保它是一个有效的数字并且在 0.0 到 1.0 之间
                        double percent = 0.0;
                        if (arr[1] > 0) {
                          percent = arr[0] / arr[1];
                          // 限制在 0.0 到 1.0 之间
                          percent = percent.clamp(0.0, 1.0);
                        }

                        return LinearPercentIndicator(
                          width: _sliderWidth,
                          lineHeight: 14.0,
                          percent: percent,
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
                  ),
                  SizedBox(width: 10),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
