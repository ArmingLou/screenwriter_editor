class FountainConstants {
  
  // Fountain格式正则表达式
  static final Map<String, RegExp> regex = {
    'title_page': RegExp(
      r'^[ \t]*(title|credit|author[s]?|source|notes|draft date|date|watermark|contact( info)?|revision|copyright|font|font italic|font bold|font bold italic|metadata|tl|tc|tr|cc|br|bl|header|footer)\:.*',
      caseSensitive: false,
    ),
    'section': RegExp(r'^[ \t]*(#+)(?:\s*)(.*)'),
    'synopsis': RegExp(r'^[ \t]*(?:\=)(.*)'),
    'scene_heading': RegExp(
      r'^[ \t]*([.](?=[\w\(（\p{L}])|(?:int|ext|est|int[.]?\/ext|i[.]?\/e)[. ])([^#]*)(#\s*[^\s].*#)?\s*$',
      caseSensitive: false,
      unicode: true,
    ),
    'scene_number': RegExp(r'#(.+)#'),
    'transition': RegExp(r'^\s*(?:(>)[^\n\r]*(?!<[ \t]*)|[A-Z ]+TO:)$'),
    'character': FountainConstants.blockRegex['block_dialogue_begin']!,
    'parenthetical': RegExp(r'^[ \t]*(\(.+\)|（.+）)\s*$'),
    'parenthetical_start': RegExp(r'^[ \t]*(?:\(|（)[^\)）]*$'),
    'parenthetical_end': RegExp(r'^.*(?:\)|）)\s*$'),
    'action': RegExp(r'^(.+)'),
    'centered': RegExp(r'(?<=^[ \t]*>\s*)(.+)(?=\s*<\s*$)'),
    'page_break': RegExp(r'^\s*\={3,}\s*$'),
    'line_break': RegExp(r'^ {2,}$'),
    'note_inline': RegExp(r'(?:\[{2}(?!\[+))([\s\S]+?)(?:\]{2})'),
    'emphasis': RegExp(
      r'(_|\*{1,3}|_\*{1,3}|\*{1,3}_)(.+)(_|\*{1,3}|_\*{1,3}|\*{1,3}_)',
    ),
    'bold_italic_underline': RegExp(
      r'(_{1}\*{3}(?=.+\*{3}_{1})|\*{3}_{1}(?=.+_{1}\*{3}))(.+?)(\*{3}_{1}|_{1}\*{3})',
    ),
    'bold_underline': RegExp(
      r'(_{1}\*{2}(?=.+\*{2}_{1})|\*{2}_{1}(?=.+_{1}\*{2}))(.+?)(\*{2}_{1}|_{1}\*{2})',
    ),
    'italic_underline': RegExp(
      r'(?:_{1}\*{1}(?=.+\*{1}_{1})|\*{1}_{1}(?=.+_{1}\*{1}))(.+?)(\*{1}_{1}|_{1}\*{1})',
    ),
    'bold_italic': RegExp(r'(\*{3}(?=.+\*{3}))(.+?)(\*{3})'),
    'bold': RegExp(r'(\*{2}(?=.+\*{2}))(.+?)(\*{2})'),
    'italic': RegExp(r'(\*{1}(?=.+\*{1}))(.+?)(\*{1})'),
    'underline': RegExp(r'(_{1}(?=.+_{1}))(.+?)(_{1})'),
    'lyric': FountainConstants.blockRegex['lyric']!,
  };
  
  // 样式标记字符映射
  static const Map<String, String> styleChars = {
    'note_begin_ext': 'இ',
    'note_begin': '↺', 
    'note_end': '↻',
    'italic': '☈',
    'bold': '↭',
    'bold_italic': '↯',
    'underline': '☄',
    'italic_underline': '⇀',
    'bold_underline': '☍',
    'bold_italic_underline': '☋',
    'link': '𓆡',
    'style_left_stash': '↷',
    'style_left_pop': '↶',
    'style_right_stash': '↝',
    'style_right_pop': '↜',
    'style_global_stash': '↬',
    'style_global_pop': '↫',
    'style_global_clean': '⇜',
    'italic_global_begin': '↾',
    'italic_global_end': '↿',
    'all': '☄☈↭↯↺↻↬↫☍☋↷↶↾↿↝↜⇀𓆡⇜இ',
  };

  // 块级元素正则
  static final Map<String, RegExp> blockRegex = {
    'block_dialogue_begin': RegExp(r'^[ \t]*(((?!@)\p{Lu}[^\p{Ll}\r\n]*)|(@[^\r\n\(（\^]*))(\(.*\)|（.*）)?(\s*\^)?\s*$', unicode: true),
    'block_except_dialogue_begin': RegExp(r'^(?=\s*[^\s]+.*$)'),
    'block_end': RegExp(r'^\s*$'),
    'line_break': RegExp(r'^\s{2,}$'),
    'action_force': RegExp(r'^(\s*)(\!)(.*)'),
    'lyric': RegExp(r'^(\s*)(\~)(\s*)(.*)'),
  };

  // Token解析正则
  static final Map<String, RegExp> tokenRegex = {
    'note_inline': RegExp(r'(?:↺|இ)([\s\S]+?)(?:↻)'),
    'underline': RegExp(r'(☄(?=.+☄))(.+?)(☄)'),
    'italic': RegExp(r'(☈(?=.+☈))(.+?)(☈)'),
    'italic_global': RegExp(r'(↾)([^↿]*)(↿)'),
    'bold': RegExp(r'(↭(?=.+↭))(.+?)(↭)'),
    'bold_italic': RegExp(r'(↯(?=.+↯))(.+?)(↯)'),
    'italic_underline': RegExp(r'(?:☄☈(?=.+☈☄)|☈☄(?=.+☄☈))(.+?)(☈☄|☄☈)'),
    'bold_italic_underline': RegExp(r'(☄↯(?=.+↯☄)|↯☄(?=.+☄↯))(.+?)(↯☄|☄↯)'),
    'bold_underline': RegExp(r'(☄↭(?=.+↭☄)|↭☄(?=.+☄↭))(.+?)(↭☄|☄↭)'),
  };

  // 不能使用注解和样式的特殊位置：
  // - 场景头行
  // - 角色头行 
  // - session行
  // - transition行
  // - title page标签属性名之前位置
  // - 分页符号行(===)
}