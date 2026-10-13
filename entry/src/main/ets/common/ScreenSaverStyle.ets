/**
 * =============================================================================
 * 视觉设计令牌（Design Tokens）（ScreenSaverStyle.ets）
 * =============================================================================
 *
 * 【这个文件是干什么的】
 * 集中定义全应用的「颜色」「尺寸规格」和「星期名称」。
 * 所谓设计令牌，就是把设计师定下的规范值变成代码里的常量，
 * 所有界面只引用这里的值，不写魔法数字。
 *
 * 【为什么必须集中管理】
 * 1. 风格统一：卡片圆角、强调蓝、文字灰全应用只有一种值，不会出现
 *    「这个页面 10px 圆角、那个页面 12px」的不一致。
 * 2. 改版容易：想换主题色，改一行 accent 即可，全应用跟着变。
 * 3. 可读性好：SCREEN_SAVER_COLORS.danger 比 '#E67A7A' 一眼能看懂含义。
 * =============================================================================
 */

/** 全应用颜色表：背景、卡片底、文字三档灰、强调色、语义色等。 */
export interface ScreenSaverColors {
  bg: string;            // 页面最底层背景（近黑）
  bgElevated: string;    // 比页面高一级的背景（如列表项、小方块）
  cardBg: string;        // 卡片内部背景
  cardSurface: string;   // 屏保画布上卡片的统一卡面（缺陷 2：所有卡片同色，边界一致）
  cardHairline: string;  // 卡面细描边（缺陷 2：靠 1vp 描边区分边界，而不是靠色差）
  textPrimary: string;   // 主文字（接近白）
  textSecondary: string; // 次要文字（中灰）
  textTertiary: string;  // 辅助文字（更深一档的灰，用于 tip）
  accent: string;        // 强调色（亮蓝，用于可点击文字）
  accentStrong: string;  // 强调色（实底蓝，用于选中态/按钮）
  danger: string;        // 危险操作（删除）
  success: string;       // 成功状态
  divider: string;       // 分隔线/未选中底色
  canvasBg: string;      // 屏保画布纯黑背景
  white: string;         // 纯白
  canvasChipBg: string;  // 屏保画布上胶囊的半透明白底（8 位 ARGB）
}

/** 交互尺寸规格：间距、圆角、热区大小、手势判定阈值等。 */
export interface ScreenSaverMetrics {
  pagePadding: number;        // 页面左右留白
  cardRadius: number;         // 卡片圆角
  panelRadius: number;        // 半模态面板圆角
  capsuleHeight: number;      // 屏保底栏「＋」胶囊高度
  handleHitSize: number;      // 编辑手柄的点击热区（比视觉尺寸大，好按）
  handleVisualSize: number;   // 编辑手柄的视觉尺寸
  snapThresholdVp: number;    // 拖拽小于这个距离视为「点按」而非移动
  longPressMs: number;        // 长按判定时长（500ms 后进入编辑模式）
  capsuleAutoHideMs: number;  // 胶囊自动隐藏的延时
}

// 深色主题色板：屏保场景长时间注视，深色更护眼也更省电（OLED）。
export const SCREEN_SAVER_COLORS: ScreenSaverColors = {
  bg: '#0E0E10',
  bgElevated: '#1A1A1E',
  cardBg: '#141418',
  // 缺陷 2（静态对比）：所有卡片统一卡面 + 1vp 细描边。
  // 画布保持纯黑 #000000（OLED 省电），卡面只比它亮一点点（ΔL*≈3），
  // 边界主要靠 12% 白的细描边区分，避免大块灰色面板的「突兀感」。
  // 数值来源：自定，待核实（工程内无 Pixso 第 11 页导出可引用）。
  cardSurface: '#0D0D10',
  cardHairline: '#1FFFFFFF',
  textPrimary: '#F2F2F2',
  textSecondary: '#A8A8AE',
  textTertiary: '#8A8A90',
  accent: '#4A9EFF',
  accentStrong: '#3D6FBF',
  danger: '#E67A7A',
  success: '#7BD88F',
  divider: '#26262B',
  canvasBg: '#000000',
  white: '#FFFFFF',
  canvasChipBg: '#33FFFFFF' // 33 前缀 = 20% 透明度的白色
};

export const SCREEN_SAVER_METRICS: ScreenSaverMetrics = {
  pagePadding: 16,
  cardRadius: 10,
  panelRadius: 10,
  capsuleHeight: 40,
  handleHitSize: 44,      // 44vp 是移动端公认的最小舒适热区
  handleVisualSize: 28,
  snapThresholdVp: 8,     // 8vp 内的位移不算拖拽，避免手指微颤误判
  longPressMs: 500,
  capsuleAutoHideMs: 2000
};

// 星期名称表：Date.getDay() 返回 0~6（0 是周日），直接按下标取名。
export const SCREEN_SAVER_WEEK_NAMES: string[] = ['日', '一', '二', '三', '四', '五', '六'];
