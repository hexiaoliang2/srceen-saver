import { ScreensaverCardMeta, ScreensaverCardType, ScreensaverSizePreset } from '../model/ConfigModels';

const CLOCK_SIZE_PRESETS: ScreensaverSizePreset[] = [
  { colSpan: 2, rowSpan: 1, label: '2×1' },
  { colSpan: 4, rowSpan: 2, label: '4×2' },
  { colSpan: 4, rowSpan: 3, label: '4×3' }
];

export const SCREEN_SAVER_CARD_CATALOG: ScreensaverCardMeta[] = [
  {
    cardType: 'clock',
    displayName: '时钟',
    description: '时间 / 日期 / 农历多格式切换',
    unique: true,
    defaultColSpan: 4,
    defaultRowSpan: 2,
    minColSpan: 2,
    minRowSpan: 1,
    maxColSpan: 4,
    maxRowSpan: 4,
    sizePresets: CLOCK_SIZE_PRESETS
  },
  {
    cardType: 'git',
    displayName: 'Git 贡献',
    description: 'GitHub 贡献热力图，断网缓存',
    unique: true,
    defaultColSpan: 4,
    defaultRowSpan: 2,
    minColSpan: 2,
    minRowSpan: 2,
    maxColSpan: 4,
    maxRowSpan: 4,
    sizePresets: []
  },
  {
    cardType: 'photo',
    displayName: '相册',
    description: '照片轮播 · 自适应尺寸更省电',
    unique: false,
    defaultColSpan: 4,
    defaultRowSpan: 4,
    minColSpan: 2,
    minRowSpan: 2,
    maxColSpan: 4,
    maxRowSpan: 6,
    sizePresets: []
  },
  {
    cardType: 'video',
    displayName: '视频',
    description: '静音循环播放 · 默认显示封面帧',
    unique: false,
    defaultColSpan: 4,
    defaultRowSpan: 3,
    minColSpan: 2,
    minRowSpan: 2,
    maxColSpan: 4,
    maxRowSpan: 4,
    sizePresets: []
  }
];

export function screenSaverFindCardMeta(cardType: ScreensaverCardType): ScreensaverCardMeta | undefined {
  return SCREEN_SAVER_CARD_CATALOG.find((meta: ScreensaverCardMeta): boolean => meta.cardType === cardType);
}

export function screenSaverCardTypeName(cardType: ScreensaverCardType): string {
  const meta = screenSaverFindCardMeta(cardType);
  return meta !== undefined ? meta.displayName : '卡片';
}
