/**
 * =============================================================================
 * 卡片目录（CardCatalog.ets）
 * =============================================================================
 *
 * 【这个文件是干什么的】
 * 「卡片类型说明书」：静态登记四种卡片（时钟/相册/视频/Git）各自的
 * 展示名、描述、默认尺寸、最小/最大尺寸、尺寸快捷预设、是否唯一。
 *
 * 【为什么用数据表而不是 if/else 写死】
 * 卡片库页面、编辑面板、AppModel 的增删改查都基于同一份目录数据工作：
 *   - 卡片库遍历它渲染「可添加的卡片」列表；
 *   - AppModel 用 defaultColSpan/defaultRowSpan 找空位建卡，
 *     用 min/max 限制缩放范围；
 *   - 界面用 unique 字段决定是否显示「已添加」标记。
 * 新增一种卡片只需要在这里加一项 + 实现一个视图组件。
 * =============================================================================
 */

import { ScreensaverCardMeta, ScreensaverCardType, ScreensaverSizePreset } from '../model/ConfigModels';

// 时钟卡的尺寸快捷预设（编辑面板「尺寸」按钮组）。
const CLOCK_SIZE_PRESETS: ScreensaverSizePreset[] = [
  { colSpan: 2, rowSpan: 1, label: '2×1' },
  { colSpan: 4, rowSpan: 2, label: '4×2' },
  { colSpan: 4, rowSpan: 3, label: '4×3' }
];

/**
 * 四种卡片的元数据表（唯一数据源）。
 * unique=true 的卡片（时钟、Git）全局最多一张；相册、视频可加多张。
 */
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

/** 按类型查元数据（找不到返回 undefined，调用方自行兜底）。 */
export function screenSaverFindCardMeta(cardType: ScreensaverCardType): ScreensaverCardMeta | undefined {
  return SCREEN_SAVER_CARD_CATALOG.find((meta: ScreensaverCardMeta): boolean => meta.cardType === cardType);
}

/** 按类型取显示名（找不到兜底「卡片」，保证界面文案永不空）。 */
export function screenSaverCardTypeName(cardType: ScreensaverCardType): string {
  const meta = screenSaverFindCardMeta(cardType);
  return meta !== undefined ? meta.displayName : '卡片';
}
