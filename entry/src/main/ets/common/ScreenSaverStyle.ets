export interface ScreenSaverColors {
  bg: string;
  bgElevated: string;
  cardBg: string;
  textPrimary: string;
  textSecondary: string;
  textTertiary: string;
  accent: string;
  accentStrong: string;
  danger: string;
  success: string;
  divider: string;
  canvasBg: string;
  white: string;
  canvasChipBg: string;
}

export interface ScreenSaverMetrics {
  pagePadding: number;
  cardRadius: number;
  panelRadius: number;
  capsuleHeight: number;
  handleHitSize: number;
  handleVisualSize: number;
  snapThresholdVp: number;
  longPressMs: number;
  capsuleAutoHideMs: number;
}

export const SCREEN_SAVER_COLORS: ScreenSaverColors = {
  bg: '#0E0E10',
  bgElevated: '#1A1A1E',
  cardBg: '#141418',
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
  canvasChipBg: '#33FFFFFF'
};

export const SCREEN_SAVER_METRICS: ScreenSaverMetrics = {
  pagePadding: 16,
  cardRadius: 10,
  panelRadius: 10,
  capsuleHeight: 40,
  handleHitSize: 44,
  handleVisualSize: 28,
  snapThresholdVp: 8,
  longPressMs: 500,
  capsuleAutoHideMs: 2000
};

export const SCREEN_SAVER_WEEK_NAMES: string[] = ['日', '一', '二', '三', '四', '五', '六'];
