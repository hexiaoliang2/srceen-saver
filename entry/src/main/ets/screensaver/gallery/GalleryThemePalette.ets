/**
 * 固定锁屏 4 套主题的配色与元信息（本轮新增）。
 * 枚举值持久化在 galleryThemeIndex；这里只做展示映射，禁止在页面里散落字符串。
 */

import { ScreensaverGalleryTheme } from '../../model/ConfigModels';

export interface ScreensaverGalleryPalette {
  /** 主文字（时间）。 */
  textPrimary: string;
  /** 日期/天气说明。 */
  textSecondary: string;
  /** 主题强调色（互动光效）。 */
  accent: string;
  /** 次要光效色。 */
  accentSoft: string;
  /** 天气图形颜色（水墨为墨线，霓虹为暖黄）。 */
  weatherAccent: string;
  /** 水墨天气图形使用描边而非实心。 */
  weatherOutline: boolean;
  /** 点击时间时的环颜色。 */
  ringColor: string;
  /** 点击时间时的环外发光（空串表示不发光）。 */
  ringGlow: string;
  /** 点击时间时日期的高亮底色（空串表示不高亮）。 */
  dateHighlight: string;
  /** 时间字体族（serif/monospace 由系统做可用性回退）。 */
  fontFamily: string;
  /** 时间字重。 */
  fontWeight: FontWeight;
  /** 时间字距。 */
  letterSpacing: number;
}

/** 数字索引 → 主题枚举（持久化值是 number，禁止用 as 强转）。 */
export function screenSaverGalleryThemeOf(index: number): ScreensaverGalleryTheme {
  if (index === 1) {
    return ScreensaverGalleryTheme.Neon;
  }
  if (index === 2) {
    return ScreensaverGalleryTheme.Pixel;
  }
  if (index === 3) {
    return ScreensaverGalleryTheme.Greenhouse;
  }
  return ScreensaverGalleryTheme.Ink;
}

export function screenSaverGalleryThemeName(theme: ScreensaverGalleryTheme): string {
  if (theme === ScreensaverGalleryTheme.Neon) {
    return '未来霓虹';
  }
  if (theme === ScreensaverGalleryTheme.Pixel) {
    return '复古像素';
  }
  if (theme === ScreensaverGalleryTheme.Greenhouse) {
    return '植物温室';
  }
  return '水墨山水';
}

export function screenSaverGalleryPalette(theme: ScreensaverGalleryTheme): ScreensaverGalleryPalette {
  if (theme === ScreensaverGalleryTheme.Neon) {
    const neon: ScreensaverGalleryPalette = {
      textPrimary: '#F4F7F2',
      textSecondary: '#C6D4E2',
      accent: '#63E6FF',
      accentSoft: '#FF5AC8',
      weatherAccent: '#FFD45E',
      weatherOutline: false,
      ringColor: '#63E6FF',
      ringGlow: '#9963E6FF',
      dateHighlight: '#3363E6FF',
      fontFamily: 'sans-serif',
      fontWeight: FontWeight.Medium,
      letterSpacing: 1
    };
    return neon;
  }
  if (theme === ScreensaverGalleryTheme.Pixel) {
    const pixel: ScreensaverGalleryPalette = {
      textPrimary: '#FFD76A',
      textSecondary: '#F2C36B',
      accent: '#FFC24B',
      accentSoft: '#63E6FF',
      weatherAccent: '#FFD76A',
      weatherOutline: false,
      ringColor: '#FFC24B',
      ringGlow: '',
      dateHighlight: '#66000000',
      fontFamily: 'monospace',
      fontWeight: FontWeight.Bold,
      letterSpacing: 2
    };
    return pixel;
  }
  if (theme === ScreensaverGalleryTheme.Greenhouse) {
    const greenhouse: ScreensaverGalleryPalette = {
      textPrimary: '#F8ECD7',
      textSecondary: '#E8D9BE',
      accent: '#FFD27E',
      accentSoft: '#9FCB8F',
      weatherAccent: '#FFD27E',
      weatherOutline: false,
      ringColor: '#FFD27E',
      ringGlow: '#66FFD27E',
      dateHighlight: '',
      fontFamily: 'serif',
      fontWeight: FontWeight.Medium,
      letterSpacing: 0
    };
    return greenhouse;
  }
  const ink: ScreensaverGalleryPalette = {
    textPrimary: '#1F2A33',
    textSecondary: '#53636C',
    accent: '#C4553A',
    accentSoft: '#7C8F93',
    weatherAccent: '#3A4B55',
    weatherOutline: true,
    ringColor: '#2B3E49',
    ringGlow: '',
    dateHighlight: '#00000000',
    fontFamily: 'serif',
    fontWeight: FontWeight.Medium,
    letterSpacing: 0
  };
  return ink;
}
