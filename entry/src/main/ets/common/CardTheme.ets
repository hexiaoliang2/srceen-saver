/**
 * =============================================================================
 * 卡片主题（CardTheme.ets）—— 变更项 1~3 的统一视觉定义
 * =============================================================================
 *
 * 【这个文件是干什么的】
 * 把屏保画布上**所有卡片**的「文字颜色 / 图标与装饰素材版本 / 可读性兜底投影」
 * 抽成一份统一的主题定义，卡片视图只查表、不各自硬编码色值：
 *
 *   1. 两套调色板（按文字墨色档）：
 *      · light 墨色（浅色文字/图标）→ 配深色整体背景；
 *      · dark  墨色（深色文字/图标）→ 配浅色整体背景；
 *   2. 文字色三档（变更项 3.2）：'auto'（默认，按整体背景明度自动判定）/
 *      'dark'（手动黑字）/ 'light'（手动白字）；选择结果随布局持久化
 *      （AppModel 读写 textTone / textHalo）。
 *   3. 自动判定算法（唯一来源 = 整体背景明度）：
 *      · 纯色背景：直接用色值的 WCAG 相对亮度；
 *      · 图片 / 离屏模糊图背景：用背景图的主色（effectKit ColorPicker，
 *        等价于「主要区域平均色」）算相对亮度；在背景图解码/模糊完成时
 *        计算一次并缓存（见 CanvasBackground.cachedLuminance），不重复计算；
 *      · 阈值 SCREEN_SAVER_INK_LUMINANCE_THRESHOLD = 0.179：
 *        这是「白字对比度 = 黑字对比度」的数学交叉点
 *        （(L+0.05)² = 0.05×1.05 ⇒ L ≈ 0.1791），取该点可保证纯色背景下
 *        所选文字色对比度 ≥ 4.58:1（覆盖 WCAG AA 正文下限 4.5:1）；
 *        L < 0.179 → 深色背景 → 浅色文字；L ≥ 0.179 → 浅色背景 → 深色文字。
 *   4. 判定结果**同时驱动**文字颜色与图标/装饰素材版本（变更项 3.2/3.4），
 *      避免「黑字配白色图标」这类不协调。
 *   5. 可读性兜底（变更项 3.3）：复杂背景（图片/模糊图）或主文字理论对比度
 *      不足 4.5:1 时，为文字启用轻投影（radius 6px），由全局开关 textHalo 控制；
 *      投影不改变卡片全透明的性质。
 *
 * 【取色依据（实现侧方案，待确认）】
 * 工程内没有 Pixso 导出/guid 可引用，以下色值均为自定：
 *   · 浅色文字三档沿用旧卡片观感（#F2F2F2/#D6D6D6/#ABABAB），
 *     在纯黑背景上对比度约 18.8 / 14.6 / 9.1（≥4.5 ✓）；
 *   · 深色文字三档（#111111/#3D3D3D/#5F5F5F）在纯白背景上约 18.9 / 10.9 / 6.4；
 *   · 图标/装饰的深色版（浅色背景用）均按「对纯白 ≥ 3:1（图形对比度下限）」
 *     设计，浅色版（深色背景用）按「对纯黑 ≥ 3:1」设计。
 * =============================================================================
 */

import { screenSaverAppModel } from '../model/AppModel';
import { ScreensaverInkTone, ScreensaverTextToneMode } from '../model/ConfigModels';
import { screenSaverCanvasBackground } from './CanvasBackground';
import { screenSaverContrastRatio, screenSaverRelativeLuminance } from './ImageLoader';

/**
 * 自动判定的明度阈值（WCAG 相对亮度，0~1）。
 * 取值 = 黑白文字对比度交叉点 ≈ 0.1791（见文件头说明），是实现侧推导值。
 */
export const SCREEN_SAVER_INK_LUMINANCE_THRESHOLD: number = 0.179;

/** 正文文字的对比度下限（WCAG AA 参考值，变更项 3.3 的内部验收判据）。 */
export const SCREEN_SAVER_TEXT_CONTRAST_MIN: number = 4.5;

/** 文字轻投影（兜底）的模糊半径（px；0 = 不画投影，见 ShadowOptions 语义）。 */
export const SCREEN_SAVER_TEXT_SHADOW_RADIUS_PX: number = 6;

/**
 * 一次卡片皮肤判定的结果：墨色档 + 是否启用投影兜底。
 * 屏保页算一次、整棵卡片树共用（同一来源，避免逐卡片各算各的）。
 */
export interface ScreensaverCardSkin {
  tone: ScreensaverInkTone;
  halo: boolean;
}

/** 天气装饰调色板（各状态对应的静态插画色）。 */
export interface ScreensaverWeatherArtPalette {
  sun: string;
  sunCore: string;
  cloud: string;
  cloudDark: string;
  rain: string;
  snow: string;
  fog: string;
  bolt: string;
}

/** 一张卡片的完整调色板（文字 + 图标 + 装饰素材版本 + Git 热力图配色）。 */
export interface ScreensaverCardPalette {
  textPrimary: string;
  textSecondary: string;
  textTertiary: string;
  /** 投影兜底色（8 位 ARGB）：浅色文字配深影，深色文字配浅影。 */
  halo: string;
  /** 行情涨跌配色：上涨 / 下跌 / 平盘（红涨绿跌时 up=红、down=绿）。 */
  quoteUp: string;
  quoteDown: string;
  quoteFlat: string;
  /** 倒计时“休 / 班”/行情状态标签的半透明底色（元素级，不是卡片底板）。 */
  restTag: string;
  workTag: string;
  tagBackground: string;
  /** 可选的卡片细描边（“显示卡片边框”开启时使用；默认透明无边框）。 */
  cardBorder: string;
  /** 应用入口卡「中性图标」的首字色与 6 档底色。 */
  iconInitial: string;
  iconTints: string[];
  /**
   * Git 热力图分级配色（index 0 不使用：0 级格全透明，见变更项 3.1 确认结论；
   * 1~4 级 = 提交次数递增）。
   */
  gitLevelsGreen: string[];
  gitLevelsBlue: string[];
  gitLevelsGray: string[];
  weather: ScreensaverWeatherArtPalette;
}

/**
 * 两套调色板。键名沿用既有模型语义：
 *   'light' = 浅色文字/图标（背景偏深时使用）；'dark' = 深色文字/图标（背景偏浅）。
 */
export const SCREEN_SAVER_CARD_PALETTES: Record<ScreensaverInkTone, ScreensaverCardPalette> = {
  'light': {
    textPrimary: '#F2F2F2',
    textSecondary: '#D6D6D6',
    textTertiary: '#ABABAB',
    halo: '#CC000000',
    quoteUp: '#FF6B6B',
    quoteDown: '#4CD97B',
    quoteFlat: '#D6D6D6',
    restTag: '#4CD97B',
    workTag: '#F2B75E',
    tagBackground: '#22FFFFFF',
    cardBorder: '#59FFFFFF',
    iconInitial: '#1B1B1B',
    iconTints: ['#AFC3D4', '#BFD2C2', '#D9C3A8', '#C6BCD9', '#D9B4BE', '#AFD0D6'],
    gitLevelsGreen: ['', '#0E4429', '#006D32', '#26A641', '#39D353'],
    gitLevelsBlue: ['', '#0A3069', '#0969DA', '#218BFF', '#79C0FF'],
    gitLevelsGray: ['', '#2E2E30', '#444446', '#5A5A5C', '#707072'],
    weather: {
      sun: '#F2B75E',
      sunCore: '#F9D9A0',
      cloud: '#C8D2DC',
      cloudDark: '#A9B4C0',
      rain: '#8FB7E8',
      snow: '#E8F1FA',
      fog: '#B9C3CC',
      bolt: '#F2C14E'
    }
  },
  'dark': {
    textPrimary: '#111111',
    textSecondary: '#3D3D3D',
    textTertiary: '#5F5F5F',
    halo: '#CCFFFFFF',
    quoteUp: '#C62828',
    quoteDown: '#1B7F3A',
    quoteFlat: '#3D3D3D',
    restTag: '#1B7F3A',
    workTag: '#B26A00',
    tagBackground: '#14000000',
    cardBorder: '#59000000',
    iconInitial: '#F7F7F7',
    iconTints: ['#3F5A75', '#3F6B52', '#6E4F2F', '#544569', '#6E3D48', '#2F5F6B'],
    gitLevelsGreen: ['', '#0E4429', '#1B7F3A', '#249449', '#2E9E4C'],
    gitLevelsBlue: ['', '#0A3069', '#0B5FC4', '#1470D6', '#2F8FE8'],
    gitLevelsGray: ['', '#3A3A3C', '#565658', '#6E6E70', '#8E8E90'],
    weather: {
      sun: '#C07A12',
      sunCore: '#E0A94E',
      cloud: '#5B6B7A',
      cloudDark: '#49535E',
      rain: '#2F6FB0',
      snow: '#5B84AB',
      fog: '#7E8894',
      bolt: '#B8860B'
    }
  }
};

/** 取某个墨色档的调色板。 */
export function screenSaverCardPalette(tone: ScreensaverInkTone): ScreensaverCardPalette {
  return SCREEN_SAVER_CARD_PALETTES[tone];
}

/**
 * 亮度 → 墨色档（自动判定的核心，纯函数）。
 * ≥ 阈值（默认 0.179）→ 浅色背景 → 深色文字；否则 → 深色背景 → 浅色文字。
 */
export function screenSaverInkToneFromLuminance(luminance: number): ScreensaverInkTone {
  if (luminance >= SCREEN_SAVER_INK_LUMINANCE_THRESHOLD) {
    return 'dark';
  }
  return 'light';
}

/**
 * 整体背景的当前相对亮度（0~1）——自动判定的**唯一来源**。
 *   · 设置了背景图片且位图已就绪 → 用缓存的主色亮度（整图主色 ≈ 主要区域平均色）；
 *   · 否则（纯色背景 / 图片还没加载完）→ 用背景色值的相对亮度；
 * 缓存说明：图片亮度在背景图解码（或离屏模糊）完成时计算一次并随位图缓存
 * （CanvasBackground.cachedLuminance），卡片每次重绘只读缓存，不重复取样。
 */
export function screenSaverCanvasLuminance(): number {
  const settings = screenSaverAppModel.layout.settings;
  if (settings.canvasImageUri.length > 0) {
    const imageLuminance = screenSaverCanvasBackground.cachedLuminance();
    if (imageLuminance >= 0) {
      return imageLuminance;
    }
  }
  return screenSaverRelativeLuminance(settings.canvasColor);
}

/** 文字色档位 → 生效墨色档（自动档查背景明度，手动档直接用用户选择）。 */
export function screenSaverEffectiveInkTone(): ScreensaverInkTone {
  const mode: ScreensaverTextToneMode = screenSaverAppModel.layout.settings.textTone;
  if (mode === 'dark') {
    return 'dark';
  }
  if (mode === 'light') {
    return 'light';
  }
  return screenSaverInkToneFromLuminance(screenSaverCanvasLuminance());
}

/**
 * 当前屏保画布的完整卡片皮肤（墨色档 + 投影兜底开关）。
 *
 * 投影触发条件（变更项 3.3）：
 *   1. 全局开关 textHalo 打开（设置页「文字投影兜底」）；
 *   2. 且满足其一：背景为图片/模糊图（局部像素不可预知，复杂背景）；
 *      或主文字对背景的理论对比度 < 4.5:1（兜底补强）。
 * 纯色背景 + 自动档下阈值为黑白交叉点，理论对比度 ≥ 4.58:1，
 * 因此纯色背景默认不画投影（保持屏保静止态的纯净）。
 */
export function screenSaverCurrentCardSkin(): ScreensaverCardSkin {
  const settings = screenSaverAppModel.layout.settings;
  const tone = screenSaverEffectiveInkTone();
  const palette = screenSaverCardPalette(tone);
  const luminance = screenSaverCanvasLuminance();
  const textLuminance = screenSaverRelativeLuminance(palette.textPrimary);
  const contrast = screenSaverContrastRatio(textLuminance, luminance);
  const complexBackground = settings.canvasImageUri.length > 0;
  const skin: ScreensaverCardSkin = {
    tone: tone,
    halo: settings.textHalo && (complexBackground || contrast < SCREEN_SAVER_TEXT_CONTRAST_MIN)
  };
  return skin;
}

/**
 * 文字轻投影参数（兜底）：halo=false 时 radius 置 0（ShadowOptions 语义 = 无阴影），
 * 不用条件渲染分支，避免各卡片写两套 Text。
 */
export function screenSaverTextShadow(halo: boolean, haloColor: string): ShadowOptions {
  const options: ShadowOptions = {
    radius: halo ? SCREEN_SAVER_TEXT_SHADOW_RADIUS_PX : 0,
    color: haloColor,
    offsetX: 0,
    offsetY: 1
  };
  return options;
}

/** 文字「下方实际像素」的对比度（用于验证报告与判定链路的可回归性）。 */
export function screenSaverTextContrast(hex: string, backgroundLuminance: number): number {
  return screenSaverContrastRatio(screenSaverRelativeLuminance(hex), backgroundLuminance);
}
