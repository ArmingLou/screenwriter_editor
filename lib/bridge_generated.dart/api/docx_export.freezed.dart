// dart format width=80
// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'docx_export.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$ExportResult {
  bool get success;
  String get message;
  String? get filePath;

  /// Create a copy of ExportResult
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $ExportResultCopyWith<ExportResult> get copyWith =>
      _$ExportResultCopyWithImpl<ExportResult>(
          this as ExportResult, _$identity);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is ExportResult &&
            (identical(other.success, success) || other.success == success) &&
            (identical(other.message, message) || other.message == message) &&
            (identical(other.filePath, filePath) ||
                other.filePath == filePath));
  }

  @override
  int get hashCode => Object.hash(runtimeType, success, message, filePath);

  @override
  String toString() {
    return 'ExportResult(success: $success, message: $message, filePath: $filePath)';
  }
}

/// @nodoc
abstract mixin class $ExportResultCopyWith<$Res> {
  factory $ExportResultCopyWith(
          ExportResult value, $Res Function(ExportResult) _then) =
      _$ExportResultCopyWithImpl;
  @useResult
  $Res call({bool success, String message, String? filePath});
}

/// @nodoc
class _$ExportResultCopyWithImpl<$Res> implements $ExportResultCopyWith<$Res> {
  _$ExportResultCopyWithImpl(this._self, this._then);

  final ExportResult _self;
  final $Res Function(ExportResult) _then;

  /// Create a copy of ExportResult
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? success = null,
    Object? message = null,
    Object? filePath = freezed,
  }) {
    return _then(_self.copyWith(
      success: null == success
          ? _self.success
          : success // ignore: cast_nullable_to_non_nullable
              as bool,
      message: null == message
          ? _self.message
          : message // ignore: cast_nullable_to_non_nullable
              as String,
      filePath: freezed == filePath
          ? _self.filePath
          : filePath // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// @nodoc

class _ExportResult implements ExportResult {
  const _ExportResult(
      {required this.success, required this.message, this.filePath});

  @override
  final bool success;
  @override
  final String message;
  @override
  final String? filePath;

  /// Create a copy of ExportResult
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  _$ExportResultCopyWith<_ExportResult> get copyWith =>
      __$ExportResultCopyWithImpl<_ExportResult>(this, _$identity);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _ExportResult &&
            (identical(other.success, success) || other.success == success) &&
            (identical(other.message, message) || other.message == message) &&
            (identical(other.filePath, filePath) ||
                other.filePath == filePath));
  }

  @override
  int get hashCode => Object.hash(runtimeType, success, message, filePath);

  @override
  String toString() {
    return 'ExportResult(success: $success, message: $message, filePath: $filePath)';
  }
}

/// @nodoc
abstract mixin class _$ExportResultCopyWith<$Res>
    implements $ExportResultCopyWith<$Res> {
  factory _$ExportResultCopyWith(
          _ExportResult value, $Res Function(_ExportResult) _then) =
      __$ExportResultCopyWithImpl;
  @override
  @useResult
  $Res call({bool success, String message, String? filePath});
}

/// @nodoc
class __$ExportResultCopyWithImpl<$Res>
    implements _$ExportResultCopyWith<$Res> {
  __$ExportResultCopyWithImpl(this._self, this._then);

  final _ExportResult _self;
  final $Res Function(_ExportResult) _then;

  /// Create a copy of ExportResult
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? success = null,
    Object? message = null,
    Object? filePath = freezed,
  }) {
    return _then(_ExportResult(
      success: null == success
          ? _self.success
          : success // ignore: cast_nullable_to_non_nullable
              as bool,
      message: null == message
          ? _self.message
          : message // ignore: cast_nullable_to_non_nullable
              as String,
      filePath: freezed == filePath
          ? _self.filePath
          : filePath // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// @nodoc
mixin _$ParseResult {
  bool get success;
  String get message;
  int get pageCount;
  int get characterCount;
  int get wordCount;

  /// Create a copy of ParseResult
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $ParseResultCopyWith<ParseResult> get copyWith =>
      _$ParseResultCopyWithImpl<ParseResult>(this as ParseResult, _$identity);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is ParseResult &&
            (identical(other.success, success) || other.success == success) &&
            (identical(other.message, message) || other.message == message) &&
            (identical(other.pageCount, pageCount) ||
                other.pageCount == pageCount) &&
            (identical(other.characterCount, characterCount) ||
                other.characterCount == characterCount) &&
            (identical(other.wordCount, wordCount) ||
                other.wordCount == wordCount));
  }

  @override
  int get hashCode => Object.hash(
      runtimeType, success, message, pageCount, characterCount, wordCount);

  @override
  String toString() {
    return 'ParseResult(success: $success, message: $message, pageCount: $pageCount, characterCount: $characterCount, wordCount: $wordCount)';
  }
}

/// @nodoc
abstract mixin class $ParseResultCopyWith<$Res> {
  factory $ParseResultCopyWith(
          ParseResult value, $Res Function(ParseResult) _then) =
      _$ParseResultCopyWithImpl;
  @useResult
  $Res call(
      {bool success,
      String message,
      int pageCount,
      int characterCount,
      int wordCount});
}

/// @nodoc
class _$ParseResultCopyWithImpl<$Res> implements $ParseResultCopyWith<$Res> {
  _$ParseResultCopyWithImpl(this._self, this._then);

  final ParseResult _self;
  final $Res Function(ParseResult) _then;

  /// Create a copy of ParseResult
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? success = null,
    Object? message = null,
    Object? pageCount = null,
    Object? characterCount = null,
    Object? wordCount = null,
  }) {
    return _then(_self.copyWith(
      success: null == success
          ? _self.success
          : success // ignore: cast_nullable_to_non_nullable
              as bool,
      message: null == message
          ? _self.message
          : message // ignore: cast_nullable_to_non_nullable
              as String,
      pageCount: null == pageCount
          ? _self.pageCount
          : pageCount // ignore: cast_nullable_to_non_nullable
              as int,
      characterCount: null == characterCount
          ? _self.characterCount
          : characterCount // ignore: cast_nullable_to_non_nullable
              as int,
      wordCount: null == wordCount
          ? _self.wordCount
          : wordCount // ignore: cast_nullable_to_non_nullable
              as int,
    ));
  }
}

/// @nodoc

class _ParseResult implements ParseResult {
  const _ParseResult(
      {required this.success,
      required this.message,
      required this.pageCount,
      required this.characterCount,
      required this.wordCount});

  @override
  final bool success;
  @override
  final String message;
  @override
  final int pageCount;
  @override
  final int characterCount;
  @override
  final int wordCount;

  /// Create a copy of ParseResult
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  _$ParseResultCopyWith<_ParseResult> get copyWith =>
      __$ParseResultCopyWithImpl<_ParseResult>(this, _$identity);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _ParseResult &&
            (identical(other.success, success) || other.success == success) &&
            (identical(other.message, message) || other.message == message) &&
            (identical(other.pageCount, pageCount) ||
                other.pageCount == pageCount) &&
            (identical(other.characterCount, characterCount) ||
                other.characterCount == characterCount) &&
            (identical(other.wordCount, wordCount) ||
                other.wordCount == wordCount));
  }

  @override
  int get hashCode => Object.hash(
      runtimeType, success, message, pageCount, characterCount, wordCount);

  @override
  String toString() {
    return 'ParseResult(success: $success, message: $message, pageCount: $pageCount, characterCount: $characterCount, wordCount: $wordCount)';
  }
}

/// @nodoc
abstract mixin class _$ParseResultCopyWith<$Res>
    implements $ParseResultCopyWith<$Res> {
  factory _$ParseResultCopyWith(
          _ParseResult value, $Res Function(_ParseResult) _then) =
      __$ParseResultCopyWithImpl;
  @override
  @useResult
  $Res call(
      {bool success,
      String message,
      int pageCount,
      int characterCount,
      int wordCount});
}

/// @nodoc
class __$ParseResultCopyWithImpl<$Res> implements _$ParseResultCopyWith<$Res> {
  __$ParseResultCopyWithImpl(this._self, this._then);

  final _ParseResult _self;
  final $Res Function(_ParseResult) _then;

  /// Create a copy of ParseResult
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? success = null,
    Object? message = null,
    Object? pageCount = null,
    Object? characterCount = null,
    Object? wordCount = null,
  }) {
    return _then(_ParseResult(
      success: null == success
          ? _self.success
          : success // ignore: cast_nullable_to_non_nullable
              as bool,
      message: null == message
          ? _self.message
          : message // ignore: cast_nullable_to_non_nullable
              as String,
      pageCount: null == pageCount
          ? _self.pageCount
          : pageCount // ignore: cast_nullable_to_non_nullable
              as int,
      characterCount: null == characterCount
          ? _self.characterCount
          : characterCount // ignore: cast_nullable_to_non_nullable
              as int,
      wordCount: null == wordCount
          ? _self.wordCount
          : wordCount // ignore: cast_nullable_to_non_nullable
              as int,
    ));
  }
}

/// @nodoc
mixin _$SimpleConf {
  bool get printTitlePage;
  String get printProfile;
  bool get doubleSpaceBetweenScenes;
  bool get printSections;
  bool get printSynopsis;
  bool get printActions;
  bool get printHeaders;
  bool get printDialogues;
  bool get numberSections;
  bool get useDualDialogue;
  bool get printNotes;
  String get printHeader;
  String get printFooter;
  String get printWatermark;
  String get scenesNumbers;
  bool get eachSceneOnNewPage;

  /// Create a copy of SimpleConf
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $SimpleConfCopyWith<SimpleConf> get copyWith =>
      _$SimpleConfCopyWithImpl<SimpleConf>(this as SimpleConf, _$identity);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is SimpleConf &&
            (identical(other.printTitlePage, printTitlePage) ||
                other.printTitlePage == printTitlePage) &&
            (identical(other.printProfile, printProfile) ||
                other.printProfile == printProfile) &&
            (identical(
                    other.doubleSpaceBetweenScenes, doubleSpaceBetweenScenes) ||
                other.doubleSpaceBetweenScenes == doubleSpaceBetweenScenes) &&
            (identical(other.printSections, printSections) ||
                other.printSections == printSections) &&
            (identical(other.printSynopsis, printSynopsis) ||
                other.printSynopsis == printSynopsis) &&
            (identical(other.printActions, printActions) ||
                other.printActions == printActions) &&
            (identical(other.printHeaders, printHeaders) ||
                other.printHeaders == printHeaders) &&
            (identical(other.printDialogues, printDialogues) ||
                other.printDialogues == printDialogues) &&
            (identical(other.numberSections, numberSections) ||
                other.numberSections == numberSections) &&
            (identical(other.useDualDialogue, useDualDialogue) ||
                other.useDualDialogue == useDualDialogue) &&
            (identical(other.printNotes, printNotes) ||
                other.printNotes == printNotes) &&
            (identical(other.printHeader, printHeader) ||
                other.printHeader == printHeader) &&
            (identical(other.printFooter, printFooter) ||
                other.printFooter == printFooter) &&
            (identical(other.printWatermark, printWatermark) ||
                other.printWatermark == printWatermark) &&
            (identical(other.scenesNumbers, scenesNumbers) ||
                other.scenesNumbers == scenesNumbers) &&
            (identical(other.eachSceneOnNewPage, eachSceneOnNewPage) ||
                other.eachSceneOnNewPage == eachSceneOnNewPage));
  }

  @override
  int get hashCode => Object.hash(
      runtimeType,
      printTitlePage,
      printProfile,
      doubleSpaceBetweenScenes,
      printSections,
      printSynopsis,
      printActions,
      printHeaders,
      printDialogues,
      numberSections,
      useDualDialogue,
      printNotes,
      printHeader,
      printFooter,
      printWatermark,
      scenesNumbers,
      eachSceneOnNewPage);

  @override
  String toString() {
    return 'SimpleConf(printTitlePage: $printTitlePage, printProfile: $printProfile, doubleSpaceBetweenScenes: $doubleSpaceBetweenScenes, printSections: $printSections, printSynopsis: $printSynopsis, printActions: $printActions, printHeaders: $printHeaders, printDialogues: $printDialogues, numberSections: $numberSections, useDualDialogue: $useDualDialogue, printNotes: $printNotes, printHeader: $printHeader, printFooter: $printFooter, printWatermark: $printWatermark, scenesNumbers: $scenesNumbers, eachSceneOnNewPage: $eachSceneOnNewPage)';
  }
}

/// @nodoc
abstract mixin class $SimpleConfCopyWith<$Res> {
  factory $SimpleConfCopyWith(
          SimpleConf value, $Res Function(SimpleConf) _then) =
      _$SimpleConfCopyWithImpl;
  @useResult
  $Res call(
      {bool printTitlePage,
      String printProfile,
      bool doubleSpaceBetweenScenes,
      bool printSections,
      bool printSynopsis,
      bool printActions,
      bool printHeaders,
      bool printDialogues,
      bool numberSections,
      bool useDualDialogue,
      bool printNotes,
      String printHeader,
      String printFooter,
      String printWatermark,
      String scenesNumbers,
      bool eachSceneOnNewPage});
}

/// @nodoc
class _$SimpleConfCopyWithImpl<$Res> implements $SimpleConfCopyWith<$Res> {
  _$SimpleConfCopyWithImpl(this._self, this._then);

  final SimpleConf _self;
  final $Res Function(SimpleConf) _then;

  /// Create a copy of SimpleConf
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? printTitlePage = null,
    Object? printProfile = null,
    Object? doubleSpaceBetweenScenes = null,
    Object? printSections = null,
    Object? printSynopsis = null,
    Object? printActions = null,
    Object? printHeaders = null,
    Object? printDialogues = null,
    Object? numberSections = null,
    Object? useDualDialogue = null,
    Object? printNotes = null,
    Object? printHeader = null,
    Object? printFooter = null,
    Object? printWatermark = null,
    Object? scenesNumbers = null,
    Object? eachSceneOnNewPage = null,
  }) {
    return _then(_self.copyWith(
      printTitlePage: null == printTitlePage
          ? _self.printTitlePage
          : printTitlePage // ignore: cast_nullable_to_non_nullable
              as bool,
      printProfile: null == printProfile
          ? _self.printProfile
          : printProfile // ignore: cast_nullable_to_non_nullable
              as String,
      doubleSpaceBetweenScenes: null == doubleSpaceBetweenScenes
          ? _self.doubleSpaceBetweenScenes
          : doubleSpaceBetweenScenes // ignore: cast_nullable_to_non_nullable
              as bool,
      printSections: null == printSections
          ? _self.printSections
          : printSections // ignore: cast_nullable_to_non_nullable
              as bool,
      printSynopsis: null == printSynopsis
          ? _self.printSynopsis
          : printSynopsis // ignore: cast_nullable_to_non_nullable
              as bool,
      printActions: null == printActions
          ? _self.printActions
          : printActions // ignore: cast_nullable_to_non_nullable
              as bool,
      printHeaders: null == printHeaders
          ? _self.printHeaders
          : printHeaders // ignore: cast_nullable_to_non_nullable
              as bool,
      printDialogues: null == printDialogues
          ? _self.printDialogues
          : printDialogues // ignore: cast_nullable_to_non_nullable
              as bool,
      numberSections: null == numberSections
          ? _self.numberSections
          : numberSections // ignore: cast_nullable_to_non_nullable
              as bool,
      useDualDialogue: null == useDualDialogue
          ? _self.useDualDialogue
          : useDualDialogue // ignore: cast_nullable_to_non_nullable
              as bool,
      printNotes: null == printNotes
          ? _self.printNotes
          : printNotes // ignore: cast_nullable_to_non_nullable
              as bool,
      printHeader: null == printHeader
          ? _self.printHeader
          : printHeader // ignore: cast_nullable_to_non_nullable
              as String,
      printFooter: null == printFooter
          ? _self.printFooter
          : printFooter // ignore: cast_nullable_to_non_nullable
              as String,
      printWatermark: null == printWatermark
          ? _self.printWatermark
          : printWatermark // ignore: cast_nullable_to_non_nullable
              as String,
      scenesNumbers: null == scenesNumbers
          ? _self.scenesNumbers
          : scenesNumbers // ignore: cast_nullable_to_non_nullable
              as String,
      eachSceneOnNewPage: null == eachSceneOnNewPage
          ? _self.eachSceneOnNewPage
          : eachSceneOnNewPage // ignore: cast_nullable_to_non_nullable
              as bool,
    ));
  }
}

/// @nodoc

class _SimpleConf extends SimpleConf {
  const _SimpleConf(
      {required this.printTitlePage,
      required this.printProfile,
      required this.doubleSpaceBetweenScenes,
      required this.printSections,
      required this.printSynopsis,
      required this.printActions,
      required this.printHeaders,
      required this.printDialogues,
      required this.numberSections,
      required this.useDualDialogue,
      required this.printNotes,
      required this.printHeader,
      required this.printFooter,
      required this.printWatermark,
      required this.scenesNumbers,
      required this.eachSceneOnNewPage})
      : super._();

  @override
  final bool printTitlePage;
  @override
  final String printProfile;
  @override
  final bool doubleSpaceBetweenScenes;
  @override
  final bool printSections;
  @override
  final bool printSynopsis;
  @override
  final bool printActions;
  @override
  final bool printHeaders;
  @override
  final bool printDialogues;
  @override
  final bool numberSections;
  @override
  final bool useDualDialogue;
  @override
  final bool printNotes;
  @override
  final String printHeader;
  @override
  final String printFooter;
  @override
  final String printWatermark;
  @override
  final String scenesNumbers;
  @override
  final bool eachSceneOnNewPage;

  /// Create a copy of SimpleConf
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  _$SimpleConfCopyWith<_SimpleConf> get copyWith =>
      __$SimpleConfCopyWithImpl<_SimpleConf>(this, _$identity);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _SimpleConf &&
            (identical(other.printTitlePage, printTitlePage) ||
                other.printTitlePage == printTitlePage) &&
            (identical(other.printProfile, printProfile) ||
                other.printProfile == printProfile) &&
            (identical(
                    other.doubleSpaceBetweenScenes, doubleSpaceBetweenScenes) ||
                other.doubleSpaceBetweenScenes == doubleSpaceBetweenScenes) &&
            (identical(other.printSections, printSections) ||
                other.printSections == printSections) &&
            (identical(other.printSynopsis, printSynopsis) ||
                other.printSynopsis == printSynopsis) &&
            (identical(other.printActions, printActions) ||
                other.printActions == printActions) &&
            (identical(other.printHeaders, printHeaders) ||
                other.printHeaders == printHeaders) &&
            (identical(other.printDialogues, printDialogues) ||
                other.printDialogues == printDialogues) &&
            (identical(other.numberSections, numberSections) ||
                other.numberSections == numberSections) &&
            (identical(other.useDualDialogue, useDualDialogue) ||
                other.useDualDialogue == useDualDialogue) &&
            (identical(other.printNotes, printNotes) ||
                other.printNotes == printNotes) &&
            (identical(other.printHeader, printHeader) ||
                other.printHeader == printHeader) &&
            (identical(other.printFooter, printFooter) ||
                other.printFooter == printFooter) &&
            (identical(other.printWatermark, printWatermark) ||
                other.printWatermark == printWatermark) &&
            (identical(other.scenesNumbers, scenesNumbers) ||
                other.scenesNumbers == scenesNumbers) &&
            (identical(other.eachSceneOnNewPage, eachSceneOnNewPage) ||
                other.eachSceneOnNewPage == eachSceneOnNewPage));
  }

  @override
  int get hashCode => Object.hash(
      runtimeType,
      printTitlePage,
      printProfile,
      doubleSpaceBetweenScenes,
      printSections,
      printSynopsis,
      printActions,
      printHeaders,
      printDialogues,
      numberSections,
      useDualDialogue,
      printNotes,
      printHeader,
      printFooter,
      printWatermark,
      scenesNumbers,
      eachSceneOnNewPage);

  @override
  String toString() {
    return 'SimpleConf(printTitlePage: $printTitlePage, printProfile: $printProfile, doubleSpaceBetweenScenes: $doubleSpaceBetweenScenes, printSections: $printSections, printSynopsis: $printSynopsis, printActions: $printActions, printHeaders: $printHeaders, printDialogues: $printDialogues, numberSections: $numberSections, useDualDialogue: $useDualDialogue, printNotes: $printNotes, printHeader: $printHeader, printFooter: $printFooter, printWatermark: $printWatermark, scenesNumbers: $scenesNumbers, eachSceneOnNewPage: $eachSceneOnNewPage)';
  }
}

/// @nodoc
abstract mixin class _$SimpleConfCopyWith<$Res>
    implements $SimpleConfCopyWith<$Res> {
  factory _$SimpleConfCopyWith(
          _SimpleConf value, $Res Function(_SimpleConf) _then) =
      __$SimpleConfCopyWithImpl;
  @override
  @useResult
  $Res call(
      {bool printTitlePage,
      String printProfile,
      bool doubleSpaceBetweenScenes,
      bool printSections,
      bool printSynopsis,
      bool printActions,
      bool printHeaders,
      bool printDialogues,
      bool numberSections,
      bool useDualDialogue,
      bool printNotes,
      String printHeader,
      String printFooter,
      String printWatermark,
      String scenesNumbers,
      bool eachSceneOnNewPage});
}

/// @nodoc
class __$SimpleConfCopyWithImpl<$Res> implements _$SimpleConfCopyWith<$Res> {
  __$SimpleConfCopyWithImpl(this._self, this._then);

  final _SimpleConf _self;
  final $Res Function(_SimpleConf) _then;

  /// Create a copy of SimpleConf
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? printTitlePage = null,
    Object? printProfile = null,
    Object? doubleSpaceBetweenScenes = null,
    Object? printSections = null,
    Object? printSynopsis = null,
    Object? printActions = null,
    Object? printHeaders = null,
    Object? printDialogues = null,
    Object? numberSections = null,
    Object? useDualDialogue = null,
    Object? printNotes = null,
    Object? printHeader = null,
    Object? printFooter = null,
    Object? printWatermark = null,
    Object? scenesNumbers = null,
    Object? eachSceneOnNewPage = null,
  }) {
    return _then(_SimpleConf(
      printTitlePage: null == printTitlePage
          ? _self.printTitlePage
          : printTitlePage // ignore: cast_nullable_to_non_nullable
              as bool,
      printProfile: null == printProfile
          ? _self.printProfile
          : printProfile // ignore: cast_nullable_to_non_nullable
              as String,
      doubleSpaceBetweenScenes: null == doubleSpaceBetweenScenes
          ? _self.doubleSpaceBetweenScenes
          : doubleSpaceBetweenScenes // ignore: cast_nullable_to_non_nullable
              as bool,
      printSections: null == printSections
          ? _self.printSections
          : printSections // ignore: cast_nullable_to_non_nullable
              as bool,
      printSynopsis: null == printSynopsis
          ? _self.printSynopsis
          : printSynopsis // ignore: cast_nullable_to_non_nullable
              as bool,
      printActions: null == printActions
          ? _self.printActions
          : printActions // ignore: cast_nullable_to_non_nullable
              as bool,
      printHeaders: null == printHeaders
          ? _self.printHeaders
          : printHeaders // ignore: cast_nullable_to_non_nullable
              as bool,
      printDialogues: null == printDialogues
          ? _self.printDialogues
          : printDialogues // ignore: cast_nullable_to_non_nullable
              as bool,
      numberSections: null == numberSections
          ? _self.numberSections
          : numberSections // ignore: cast_nullable_to_non_nullable
              as bool,
      useDualDialogue: null == useDualDialogue
          ? _self.useDualDialogue
          : useDualDialogue // ignore: cast_nullable_to_non_nullable
              as bool,
      printNotes: null == printNotes
          ? _self.printNotes
          : printNotes // ignore: cast_nullable_to_non_nullable
              as bool,
      printHeader: null == printHeader
          ? _self.printHeader
          : printHeader // ignore: cast_nullable_to_non_nullable
              as String,
      printFooter: null == printFooter
          ? _self.printFooter
          : printFooter // ignore: cast_nullable_to_non_nullable
              as String,
      printWatermark: null == printWatermark
          ? _self.printWatermark
          : printWatermark // ignore: cast_nullable_to_non_nullable
              as String,
      scenesNumbers: null == scenesNumbers
          ? _self.scenesNumbers
          : scenesNumbers // ignore: cast_nullable_to_non_nullable
              as String,
      eachSceneOnNewPage: null == eachSceneOnNewPage
          ? _self.eachSceneOnNewPage
          : eachSceneOnNewPage // ignore: cast_nullable_to_non_nullable
              as bool,
    ));
  }
}

// dart format on
