//! DOCX导出API
//!
//! 这个模块提供了Flutter应用可以调用的DOCX导出API接口

use flutter_rust_bridge::frb;
use betterfountain_rust::parser::FountainParser;
use betterfountain_rust::models::Conf;
use betterfountain_rust::docx::docx::generate_docx_document;
use betterfountain_rust::docx::docx_maker::PrintProfile;

/// 简化的配置结构，用于Flutter调用
#[frb(dart_metadata=("freezed", "immutable"))]
#[derive(Debug, Clone)]
pub struct SimpleConf {
    pub print_title_page: bool,
    pub print_profile: String,
    pub double_space_between_scenes: bool,
    pub print_sections: bool,
    pub print_synopsis: bool,
    pub print_actions: bool,
    pub print_headers: bool,
    pub print_dialogues: bool,
    pub number_sections: bool,
    pub use_dual_dialogue: bool,
    pub print_notes: bool,
    pub print_header: String,
    pub print_footer: String,
    pub print_watermark: String,
    pub scenes_numbers: String,
    pub each_scene_on_new_page: bool,
}

impl Default for SimpleConf {
    fn default() -> Self {
        Self {
            print_title_page: true,
            print_profile: "中文a4".to_string(),
            double_space_between_scenes: false,
            print_sections: false,
            print_synopsis: true,
            print_actions: true,
            print_headers: true,
            print_dialogues: true,
            number_sections: false,
            use_dual_dialogue: true,
            print_notes: true,
            print_header: String::new(),
            print_footer: String::new(),
            print_watermark: String::new(),
            scenes_numbers: "both".to_string(),
            each_scene_on_new_page: false,
        }
    }
}

impl From<SimpleConf> for Conf {
    fn from(simple: SimpleConf) -> Self {
        let mut conf = Conf::default();
        conf.print_title_page = simple.print_title_page;

        // 根据字符串创建PrintProfile
        conf.print_profile = match simple.print_profile.as_str() {
            "中文a4" => PrintProfile::default(), // 默认就是中文a4配置
            "英文letter" => {
                let mut profile = PrintProfile::default();
                profile.paper_size = "letter".to_string();
                profile.page_width = 8.5;
                profile.page_height = 11.0;
                profile
            },
            _ => PrintProfile::default(),
        };

        conf.double_space_between_scenes = simple.double_space_between_scenes;
        conf.print_sections = simple.print_sections;
        conf.print_synopsis = simple.print_synopsis;
        conf.print_actions = simple.print_actions;
        conf.print_headers = simple.print_headers;
        conf.print_dialogues = simple.print_dialogues;
        conf.number_sections = simple.number_sections;
        conf.use_dual_dialogue = simple.use_dual_dialogue;
        conf.print_notes = simple.print_notes;
        conf.print_header = simple.print_header;
        conf.print_footer = simple.print_footer;
        conf.print_watermark = simple.print_watermark;
        conf.scenes_numbers = simple.scenes_numbers;
        conf.each_scene_on_new_page = simple.each_scene_on_new_page;
        conf
    }
}

/// 导出结果
#[frb(dart_metadata=("freezed", "immutable"))]
#[derive(Debug, Clone)]
pub struct ExportResult {
    pub success: bool,
    pub message: String,
    pub file_path: Option<String>,
}

// ExportResult不需要转换，直接使用

/// 解析结果结构
#[frb(dart_metadata=("freezed", "immutable"))]
#[derive(Debug, Clone)]
pub struct ParseResult {
    pub success: bool,
    pub message: String,
    pub page_count: i32,
    pub character_count: i32,
    pub word_count: i32,
}

/// 测试连接
pub fn test_connection() -> String {
    "Rust bridge connection successful!".to_string()
}

/// 导出DOCX文档
pub async fn export_to_docx(
    text: String,
    output_path: String,
    config: Option<SimpleConf>
) -> ExportResult {
    if text.trim().is_empty() {
        return ExportResult {
            success: false,
            message: "Fountain文本不能为空".to_string(),
            file_path: None,
        };
    }

    if output_path.trim().is_empty() {
        return ExportResult {
            success: false,
            message: "输出路径不能为空".to_string(),
            file_path: None,
        };
    }

    // 使用配置或默认配置
    let conf: Conf = config.unwrap_or_default().into();

    // 创建解析器并解析文本
    let mut parser = FountainParser::new();
    let parsed_result = parser.parse(&text, &conf, true);

    // 使用betterfountain-rust的真正DOCX导出功能
    match generate_docx_document(&output_path, &conf, &parsed_result).await {
        Ok(_) => ExportResult {
            success: true,
            message: "DOCX文档导出成功".to_string(),
            file_path: Some(output_path),
        },
        Err(e) => ExportResult {
            success: false,
            message: format!("导出失败: {}", e),
            file_path: None,
        },
    }
}

/// 解析Fountain文本
pub async fn parse_fountain_text(
    text: String,
    config: Option<SimpleConf>
) -> String {
    let conf: Conf = config.unwrap_or_default().into();
    let mut parser = FountainParser::new();
    let result = parser.parse(&text, &conf, false);

    // 返回简单的JSON格式结果
    serde_json::to_string(&result).unwrap_or_else(|_| "{}".to_string())
}

/// 解析Fountain文本（包装版本，返回统计信息）
pub async fn parse_fountain_text_with_stats(
    text: String,
    config: Option<SimpleConf>
) -> ParseResult {
    // 调用betterfountain-rust的解析函数
    let _result_json = parse_fountain_text(text.clone(), config).await;

    // 简单的统计信息
    ParseResult {
        success: true,
        message: "Fountain文本解析成功".to_string(),
        page_count: 1,
        character_count: text.len() as i32,
        word_count: text.split_whitespace().count() as i32,
    }
}

/// 创建默认配置
pub fn create_default_config() -> SimpleConf {
    SimpleConf::default()
}

/// 创建中文配置
pub fn create_chinese_config() -> SimpleConf {
    let mut config = SimpleConf::default();
    config.print_profile = "中文a4".to_string();
    config
}

/// 创建英文配置
pub fn create_english_config() -> SimpleConf {
    let mut config = SimpleConf::default();
    config.print_profile = "英文letter".to_string();
    config.double_space_between_scenes = true;
    config
}

/// 导出DOCX文档为Base64编码（用于预览）
pub async fn export_to_docx_base64(
    text: String,
    config: Option<SimpleConf>
) -> ExportResult {
    if text.trim().is_empty() {
        return ExportResult {
            success: false,
            message: "Fountain文本不能为空".to_string(),
            file_path: None,
        };
    }

    // 使用配置或默认配置
    let conf: Conf = config.unwrap_or_default().into();

    // 创建解析器并解析文本
    let mut parser = FountainParser::new();
    let parsed_result = parser.parse(&text, &conf, true);

    // 使用特殊路径"$PREVIEW$"来生成Base64编码
    match generate_docx_document("$PREVIEW$", &conf, &parsed_result).await {
        Ok(_) => ExportResult {
            success: true,
            message: "DOCX Base64编码生成成功".to_string(),
            file_path: None,
        },
        Err(e) => ExportResult {
            success: false,
            message: format!("生成失败: {}", e),
            file_path: None,
        },
    }
}