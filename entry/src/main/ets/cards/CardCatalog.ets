/**
 * =============================================================================
 * 卡片目录（CardCatalog.ets）
 * =============================================================================
 *
 * 【这个文件是干什么的】
 * 「卡片类型说明书」+「尺寸矩阵」两件事都在这里：
 *   1. 静态登记每种卡片（时钟/相册/视频/Git）的展示名、描述、默认尺寸、
 *      是否唯一、以及**尺寸矩阵**（允许哪些「列×行」跨度、每个跨度下
 *      内容按哪一档密度排版）；
 *   2. 提供一组纯函数，把「尺寸」相关的规则收口成可复用、可测试的逻辑：
 *        screenSaverIsSizeAllowed  尺寸是否合法
 *        screenSaverSnapCardSize   非法尺寸吸附到最近的合法值
 *        screenSaverResolveDensity 尺寸 → 内容密度（minimal/compact/full）
 *        screenSaverSizePresets    设置面板的尺寸快捷胶囊
 *
 * 【为什么用数据表而不是 if/else 写死】
 * 卡片库页面、编辑面板、AppModel 的增删改查都基于同一份目录数据工作。
 * 尺寸规则如果散落在各处 if-else 里，改一处忘一处就会出现「编辑面板允许、
 * 拖拽缩放却拒绝」这类不一致。集中成表后：
 *   - 新增尺寸 = 表里加一行；
 *   - 新增卡片 = 表里加一段 + 实现一个视图组件。
 *
 * 【尺寸矩阵怎么读（以时钟为例）】
 *   { colSpan: 1, rowSpan: 1, density: 'minimal' }  → 1×1 只排「极简」内容
 *   { colSpan: 4, rowSpan: 2, density: 'full', presetLabel: '4×2' }
 *     → 4×2 排「完整」内容，并且作为设置面板里的「4×2」快捷按钮
 *   { colSpan: 0, rowSpan: 0, density: 'full' }     → 兜底行（相机/视频用）：
 *     区间内其余任意矩形都合法，密度取 full
 *
 * 【网格基准（定为实现侧方案，待设计确认）】
 * 手机档 4 列 × 8 行；折叠屏 8×8；平板 12×7（见 ConfigModels 常量）。
 * 单元尺寸自适应（格宽 = 网格宽/列数、格高 = 网格高/行数，360vp 宽手机约
 * 90×90vp）；卡片间距 0vp（紧贴，靠圆角与卡面/描边分界）；画布边距 0vp。
 * =============================================================================
 */

import {
  ScreensaverCardDensity,
  ScreensaverCardMeta,
  ScreensaverCardSizeEntry,
  ScreensaverCardSizeSpec,
  ScreensaverCardType,
  ScreensaverSizePreset
} from '../model/ConfigModels';

/** 兜底行的判定：列与行跨度都为 0。 */
function screenSaverIsFallbackEntry(entry: ScreensaverCardSizeEntry): boolean {
  return entry.colSpan <= 0 || entry.rowSpan <= 0;
}

// ---------------- 时钟：1×1 到 4×4 ----------------
// 理由：时钟的信息量随行高增长（时间一行、日期/农历各需一行），
// 1×1≈90×90vp 只容得下一行大字，因此 1 行高的尺寸一律走「极简（只显示时间）」。
const CLOCK_SIZE_SPEC: ScreensaverCardSizeSpec = {
  minColSpan: 1,
  minRowSpan: 1,
  maxColSpan: 4,
  maxRowSpan: 4,
  entries: [
    { colSpan: 1, rowSpan: 1, density: 'minimal', presetLabel: '' },
    { colSpan: 2, rowSpan: 1, density: 'minimal', presetLabel: '2×1' },
    { colSpan: 3, rowSpan: 1, density: 'minimal', presetLabel: '3×1' },
    { colSpan: 4, rowSpan: 1, density: 'compact', presetLabel: '4×1' },
    { colSpan: 1, rowSpan: 2, density: 'compact', presetLabel: '' },
    { colSpan: 1, rowSpan: 3, density: 'minimal', presetLabel: '1×3' },
    { colSpan: 2, rowSpan: 2, density: 'compact', presetLabel: '2×2' },
    { colSpan: 3, rowSpan: 2, density: 'compact', presetLabel: '3×2' },
    { colSpan: 2, rowSpan: 3, density: 'full', presetLabel: '' },
    { colSpan: 4, rowSpan: 2, density: 'full', presetLabel: '4×2' },
    { colSpan: 3, rowSpan: 3, density: 'compact', presetLabel: '3×3' },
    { colSpan: 4, rowSpan: 3, density: 'full', presetLabel: '4×3' },
    { colSpan: 2, rowSpan: 4, density: 'full', presetLabel: '2×4' },
    { colSpan: 3, rowSpan: 4, density: 'full', presetLabel: '3×4' },
    { colSpan: 4, rowSpan: 4, density: 'full', presetLabel: '4×4' }
  ]
};

// ---------------- 相册：1..4 × 1..6 全域放开（兜底行） ----------------
// 理由：照片是纯图像内容，Cover 裁剪对任意矩形都成立，没有「摆不下」的形态；
// 唯一的差别是文字信息条——窄条/小尺寸藏起来，中等尺寸缩一号，大尺寸正常显示。
// 显式登记的「窄条」尺寸（1×3 这类奇数跨度）也有明确档位，不会落到兜底档上错版。
const PHOTO_SIZE_SPEC: ScreensaverCardSizeSpec = {
  minColSpan: 1,
  minRowSpan: 1,
  maxColSpan: 4,
  maxRowSpan: 6,
  entries: [
    { colSpan: 1, rowSpan: 1, density: 'minimal', presetLabel: '1×1' },
    { colSpan: 2, rowSpan: 1, density: 'minimal', presetLabel: '' },
    { colSpan: 1, rowSpan: 2, density: 'minimal', presetLabel: '' },
    { colSpan: 1, rowSpan: 3, density: 'minimal', presetLabel: '1×3' },
    { colSpan: 1, rowSpan: 4, density: 'minimal', presetLabel: '' },
    { colSpan: 1, rowSpan: 5, density: 'minimal', presetLabel: '' },
    { colSpan: 1, rowSpan: 6, density: 'minimal', presetLabel: '' },
    { colSpan: 3, rowSpan: 1, density: 'compact', presetLabel: '' },
    { colSpan: 2, rowSpan: 2, density: 'compact', presetLabel: '2×2' },
    { colSpan: 2, rowSpan: 3, density: 'compact', presetLabel: '' },
    { colSpan: 3, rowSpan: 2, density: 'compact', presetLabel: '' },
    { colSpan: 4, rowSpan: 4, density: 'full', presetLabel: '4×4' },
    { colSpan: 0, rowSpan: 0, density: 'full', presetLabel: '' }
  ]
};

// ---------------- 视频：1..4 × 1..4（兜底行） ----------------
// 理由：上限压到 4 行是**功耗约束**（解码面积越大越耗电），不是视觉原因；
// 窄条/扁条（1×N、N×1）只放封面帧 + 播放角标，不塞文字。
const VIDEO_SIZE_SPEC: ScreensaverCardSizeSpec = {
  minColSpan: 1,
  minRowSpan: 1,
  maxColSpan: 4,
  maxRowSpan: 4,
  entries: [
    { colSpan: 1, rowSpan: 1, density: 'minimal', presetLabel: '1×1' },
    { colSpan: 2, rowSpan: 1, density: 'minimal', presetLabel: '' },
    { colSpan: 1, rowSpan: 2, density: 'minimal', presetLabel: '' },
    { colSpan: 1, rowSpan: 3, density: 'minimal', presetLabel: '1×3' },
    { colSpan: 1, rowSpan: 4, density: 'minimal', presetLabel: '' },
    { colSpan: 3, rowSpan: 1, density: 'minimal', presetLabel: '' },
    { colSpan: 4, rowSpan: 1, density: 'minimal', presetLabel: '' },
    { colSpan: 2, rowSpan: 2, density: 'compact', presetLabel: '2×2' },
    { colSpan: 3, rowSpan: 2, density: 'compact', presetLabel: '' },
    { colSpan: 2, rowSpan: 3, density: 'compact', presetLabel: '' },
    { colSpan: 4, rowSpan: 3, density: 'full', presetLabel: '4×3' },
    { colSpan: 0, rowSpan: 0, density: 'full', presetLabel: '' }
  ]
};

// ---------------- Git 贡献：1×1 起，最大 4×4 ----------------
// 理由：热力图每个格子代表一天，小于 2×2 时格子会小到不可辨认，
// 因此小尺寸不走热力图，改成「总提交数 + 近 7 天迷你条」的数字摘要。
const GIT_SIZE_SPEC: ScreensaverCardSizeSpec = {
  minColSpan: 1,
  minRowSpan: 1,
  maxColSpan: 4,
  maxRowSpan: 4,
  entries: [
    { colSpan: 1, rowSpan: 1, density: 'minimal', presetLabel: '' },
    { colSpan: 2, rowSpan: 1, density: 'minimal', presetLabel: '' },
    { colSpan: 3, rowSpan: 1, density: 'compact', presetLabel: '3×1' },
    { colSpan: 1, rowSpan: 2, density: 'minimal', presetLabel: '' },
    { colSpan: 1, rowSpan: 3, density: 'minimal', presetLabel: '1×3' },
    { colSpan: 4, rowSpan: 1, density: 'compact', presetLabel: '' },
    { colSpan: 2, rowSpan: 2, density: 'compact', presetLabel: '' },
    { colSpan: 3, rowSpan: 2, density: 'compact', presetLabel: '' },
    { colSpan: 2, rowSpan: 3, density: 'compact', presetLabel: '' },
    { colSpan: 2, rowSpan: 4, density: 'compact', presetLabel: '2×4' },
    { colSpan: 4, rowSpan: 2, density: 'full', presetLabel: '4×2' },
    { colSpan: 3, rowSpan: 3, density: 'compact', presetLabel: '3×3' },
    { colSpan: 4, rowSpan: 3, density: 'full', presetLabel: '4×3' },
    { colSpan: 3, rowSpan: 4, density: 'full', presetLabel: '3×4' },
    { colSpan: 4, rowSpan: 4, density: 'full', presetLabel: '4×4' }
  ]
};

// ---------------- 天气（需求 A）：1×1 起，最大 4×4 ----------------
// 理由：小尺寸只留「温度」这一个信息量最高的数字；城市名/高低温/署名
// 都需要额外行高与宽度，只有 4×N 的尺寸才放得下。
const WEATHER_SIZE_SPEC: ScreensaverCardSizeSpec = {
  minColSpan: 1,
  minRowSpan: 1,
  maxColSpan: 4,
  maxRowSpan: 4,
  entries: [
    { colSpan: 1, rowSpan: 1, density: 'minimal', presetLabel: '1×1' },
    { colSpan: 2, rowSpan: 1, density: 'minimal', presetLabel: '2×1' },
    { colSpan: 3, rowSpan: 1, density: 'compact', presetLabel: '3×1' },
    { colSpan: 1, rowSpan: 2, density: 'minimal', presetLabel: '' },
    { colSpan: 1, rowSpan: 3, density: 'minimal', presetLabel: '' },
    { colSpan: 1, rowSpan: 4, density: 'minimal', presetLabel: '' },
    { colSpan: 2, rowSpan: 2, density: 'compact', presetLabel: '2×2' },
    { colSpan: 3, rowSpan: 2, density: 'compact', presetLabel: '3×2' },
    { colSpan: 2, rowSpan: 3, density: 'compact', presetLabel: '2×3' },
    { colSpan: 3, rowSpan: 3, density: 'compact', presetLabel: '3×3' },
    { colSpan: 4, rowSpan: 1, density: 'compact', presetLabel: '4×1' },
    { colSpan: 4, rowSpan: 2, density: 'full', presetLabel: '4×2' },
    { colSpan: 2, rowSpan: 4, density: 'compact', presetLabel: '2×4' },
    { colSpan: 4, rowSpan: 3, density: 'full', presetLabel: '4×3' },
    { colSpan: 3, rowSpan: 4, density: 'full', presetLabel: '3×4' },
    { colSpan: 4, rowSpan: 4, density: 'full', presetLabel: '4×4' }
  ]
};

// ---------------- 应用入口（需求 A）：1×1 起，最大 4×4 ----------------
// 理由：1×1 放不下「打开」按钮，改成整卡可点；名称/链接/按钮需要宽度。
const ENTRY_SIZE_SPEC: ScreensaverCardSizeSpec = {
  minColSpan: 1,
  minRowSpan: 1,
  maxColSpan: 4,
  maxRowSpan: 4,
  entries: [
    { colSpan: 1, rowSpan: 1, density: 'minimal', presetLabel: '1×1' },
    { colSpan: 2, rowSpan: 1, density: 'minimal', presetLabel: '2×1' },
    { colSpan: 3, rowSpan: 1, density: 'compact', presetLabel: '3×1' },
    { colSpan: 1, rowSpan: 2, density: 'minimal', presetLabel: '' },
    { colSpan: 4, rowSpan: 1, density: 'compact', presetLabel: '4×1' },
    { colSpan: 2, rowSpan: 2, density: 'compact', presetLabel: '2×2' },
    { colSpan: 3, rowSpan: 2, density: 'compact', presetLabel: '3×2' },
    { colSpan: 2, rowSpan: 3, density: 'compact', presetLabel: '2×3' },
    { colSpan: 4, rowSpan: 2, density: 'compact', presetLabel: '4×2' },
    { colSpan: 3, rowSpan: 3, density: 'compact', presetLabel: '3×3' },
    { colSpan: 2, rowSpan: 4, density: 'compact', presetLabel: '2×4' },
    { colSpan: 4, rowSpan: 3, density: 'full', presetLabel: '4×3' },
    { colSpan: 3, rowSpan: 4, density: 'full', presetLabel: '3×4' },
    { colSpan: 4, rowSpan: 4, density: 'full', presetLabel: '4×4' }
  ]
};

/**
 * 六种卡片的元数据表（唯一数据源）。
 * unique=true 的卡片（时钟、Git）全局最多一张；相册、视频、天气、入口可加多张。
 */
export const SCREEN_SAVER_CARD_CATALOG: ScreensaverCardMeta[] = [
  {
    cardType: 'clock',
    displayName: '时钟',
    description: '时间 / 日期 / 农历多格式切换',
    unique: true,
    defaultColSpan: 4,
    defaultRowSpan: 2,
    sizeSpec: CLOCK_SIZE_SPEC
  },
  {
    cardType: 'git',
    displayName: 'Git 贡献',
    description: 'GitHub 贡献热力图，断网缓存',
    unique: true,
    defaultColSpan: 4,
    defaultRowSpan: 2,
    sizeSpec: GIT_SIZE_SPEC
  },
  {
    cardType: 'photo',
    displayName: '相册',
    description: '照片轮播 · 自适应尺寸更省电',
    unique: false,
    defaultColSpan: 4,
    defaultRowSpan: 4,
    sizeSpec: PHOTO_SIZE_SPEC
  },
  {
    cardType: 'video',
    displayName: '视频',
    description: '静音循环播放 · 默认显示封面帧',
    unique: false,
    defaultColSpan: 4,
    defaultRowSpan: 3,
    sizeSpec: VIDEO_SIZE_SPEC
  },
  {
    cardType: 'weather',
    displayName: '天气',
    description: '城市天气（数据源 Open-Meteo，需手动开启联网）',
    unique: false,
    defaultColSpan: 2,
    defaultRowSpan: 2,
    sizeSpec: WEATHER_SIZE_SPEC
  },
  {
    cardType: 'entry',
    displayName: '应用入口',
    description: '点击跳转到指定应用/链接（名称与链接自行填写）',
    unique: false,
    defaultColSpan: 2,
    defaultRowSpan: 1,
    sizeSpec: ENTRY_SIZE_SPEC
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

/** 按类型取尺寸规格（找不到返回 undefined）。 */
export function screenSaverFindSizeSpec(cardType: ScreensaverCardType): ScreensaverCardSizeSpec | undefined {
  const meta = screenSaverFindCardMeta(cardType);
  return meta !== undefined ? meta.sizeSpec : undefined;
}

/** 规格里是否存在「兜底行」（存在则区间内任意矩形都合法）。 */
function screenSaverHasFallback(spec: ScreensaverCardSizeSpec): boolean {
  return spec.entries.some((entry: ScreensaverCardSizeEntry): boolean => screenSaverIsFallbackEntry(entry));
}

/** 取兜底行（没有则返回 undefined）。 */
function screenSaverFallbackEntry(spec: ScreensaverCardSizeSpec): ScreensaverCardSizeEntry | undefined {
  return spec.entries.find((entry: ScreensaverCardSizeEntry): boolean => screenSaverIsFallbackEntry(entry));
}

/**
 * 尺寸是否合法：分两种情况（与尺寸矩阵表一一对应）。
 * - 表里有兜底行（相册/视频）：范围内任意「列×行」合法；
 * - 表里没有兜底行（时钟/Git）：只认表里精确登记过的跨度。
 */
export function screenSaverIsSizeAllowed(cardType: ScreensaverCardType, colSpan: number, rowSpan: number): boolean {
  const spec = screenSaverFindSizeSpec(cardType);
  if (spec === undefined) {
    return colSpan >= 1 && rowSpan >= 1;
  }
  if (colSpan < spec.minColSpan || rowSpan < spec.minRowSpan ||
    colSpan > spec.maxColSpan || rowSpan > spec.maxRowSpan) {
    return false;
  }
  if (screenSaverHasFallback(spec)) {
    return true;
  }
  return spec.entries.some((entry: ScreensaverCardSizeEntry): boolean =>
  entry.colSpan === colSpan && entry.rowSpan === rowSpan);
}

/**
 * 把一个「任意跨度」吸附到最近的合法尺寸，返回命中的矩阵行。
 *
 * 选取规则（确定性、可测试）：
 *   1. 候选 = 表里所有精确行 + 兜底行存在时范围内其余矩形；
 *   2. 只保留 colSpan ≤ maxColSpan、rowSpan ≤ maxRowSpan 的候选（网格边界约束）；
 *   3. 先比「曼哈顿距离」|Δ列|+|Δ行| 最小；
 *   4. 平局比面积大者优先（宁可略大不小，避免内容被挤没）；
 *   5. 再平局比列跨度小者优先（同面积下方块更稳）；
 *   6. 全都不满足（理论上不会）时退回规格里最小的那一行。
 */
export function screenSaverSnapCardSize(cardType: ScreensaverCardType, colSpan: number, rowSpan: number,
  maxColSpan: number, maxRowSpan: number): ScreensaverCardSizeEntry {
  const spec = screenSaverFindSizeSpec(cardType);
  if (spec === undefined) {
    const fallback: ScreensaverCardSizeEntry = {
      colSpan: Math.max(1, Math.min(colSpan, maxColSpan)),
      rowSpan: Math.max(1, Math.min(rowSpan, maxRowSpan)),
      density: 'full',
      presetLabel: ''
    };
    return fallback;
  }
  const candidates: ScreensaverCardSizeEntry[] = [];
  for (const entry of spec.entries) {
    if (screenSaverIsFallbackEntry(entry)) {
      continue;
    }
    if (entry.colSpan <= maxColSpan && entry.rowSpan <= maxRowSpan) {
      candidates.push(entry);
    }
  }
  if (screenSaverHasFallback(spec)) {
    // 兜底行：把范围内其余矩形也加入候选，保证「1×3」这类奇数跨度真能命中
    for (let cols = spec.minColSpan; cols <= spec.maxColSpan; cols++) {
      for (let rows = spec.minRowSpan; rows <= spec.maxRowSpan; rows++) {
        if (cols > maxColSpan || rows > maxRowSpan) {
          continue;
        }
        const already = candidates.some((entry: ScreensaverCardSizeEntry): boolean =>
        entry.colSpan === cols && entry.rowSpan === rows);
        if (already) {
          continue;
        }
        const generated: ScreensaverCardSizeEntry = {
          colSpan: cols,
          rowSpan: rows,
          density: 'full',
          presetLabel: ''
        };
        candidates.push(generated);
      }
    }
  }
  if (candidates.length === 0) {
    const minimal: ScreensaverCardSizeEntry = {
      colSpan: Math.max(1, Math.min(spec.minColSpan, maxColSpan)),
      rowSpan: Math.max(1, Math.min(spec.minRowSpan, maxRowSpan)),
      density: 'minimal',
      presetLabel: ''
    };
    return minimal;
  }
  let best = candidates[0];
  let bestScore = Math.abs(best.colSpan - colSpan) + Math.abs(best.rowSpan - rowSpan);
  for (const candidate of candidates) {
    const score = Math.abs(candidate.colSpan - colSpan) + Math.abs(candidate.rowSpan - rowSpan);
    if (score < bestScore) {
      best = candidate;
      bestScore = score;
      continue;
    }
    if (score === bestScore) {
      const bestArea = best.colSpan * best.rowSpan;
      const candidateArea = candidate.colSpan * candidate.rowSpan;
      if (candidateArea > bestArea) {
        best = candidate;
      } else if (candidateArea === bestArea && candidate.colSpan < best.colSpan) {
        best = candidate;
      }
    }
  }
  return best;
}

/**
 * 尺寸 → 内容密度。查找顺序：矩阵表的精确行 → 兜底行 → 'full'。
 * 卡片视图只依赖这一个函数决定「显示多少内容」，尺寸判断不散落在各视图里。
 */
export function screenSaverResolveDensity(cardType: ScreensaverCardType, colSpan: number,
  rowSpan: number): ScreensaverCardDensity {
  const spec = screenSaverFindSizeSpec(cardType);
  if (spec === undefined) {
    return 'full';
  }
  const exact = spec.entries.find((entry: ScreensaverCardSizeEntry): boolean =>
  !screenSaverIsFallbackEntry(entry) && entry.colSpan === colSpan && entry.rowSpan === rowSpan);
  if (exact !== undefined) {
    return exact.density;
  }
  const fallback = screenSaverFallbackEntry(spec);
  if (fallback !== undefined) {
    return fallback.density;
  }
  return 'full';
}

/**
 * 需求给定的 13 档「标准尺寸」（变更项 2 通道 A：设置面板可选尺寸集合）。
 * 原文顺序为 4×4,4×3,4×2,4×1,3×4,3×3,3×2,3×1,2×4,2×3,2×2,2×1,1×1；
 * 面板按「从小到大」展示更利于点选，因此这里按列优先升序排列（集合完全一致）。
 * 六类卡片的尺寸矩阵都必须把这 13 档登记为合法尺寸（各自密度按类型定义），
 * 由 CardCatalog 的数据表保证；吸附函数（screenSaverSnapCardSize）据此工作。
 */
export const SCREEN_SAVER_STANDARD_SIZES: ScreensaverSizePreset[] = [
  { colSpan: 1, rowSpan: 1, label: '1×1' },
  { colSpan: 2, rowSpan: 1, label: '2×1' },
  { colSpan: 3, rowSpan: 1, label: '3×1' },
  { colSpan: 4, rowSpan: 1, label: '4×1' },
  { colSpan: 2, rowSpan: 2, label: '2×2' },
  { colSpan: 3, rowSpan: 2, label: '3×2' },
  { colSpan: 4, rowSpan: 2, label: '4×2' },
  { colSpan: 2, rowSpan: 3, label: '2×3' },
  { colSpan: 3, rowSpan: 3, label: '3×3' },
  { colSpan: 4, rowSpan: 3, label: '4×3' },
  { colSpan: 2, rowSpan: 4, label: '2×4' },
  { colSpan: 3, rowSpan: 4, label: '3×4' },
  { colSpan: 4, rowSpan: 4, label: '4×4' }
];

/**
 * 设置面板的「尺寸」快捷胶囊（变更项 2 通道 A）。
 *
 * 组成 = 13 档标准尺寸（按类型过滤为合法） + 矩阵里额外登记的预设
 * （如相册/视频的 1×3、1×4 窄条）。这样：
 *   · 需求列出的 13 档在六类卡片上都可点选；
 *   · 既有的窄条尺寸不会因为列表改版而消失（保持既有能力）。
 */
export function screenSaverSizePresets(cardType: ScreensaverCardType): ScreensaverSizePreset[] {
  const spec = screenSaverFindSizeSpec(cardType);
  const presets: ScreensaverSizePreset[] = [];
  for (const standard of SCREEN_SAVER_STANDARD_SIZES) {
    if (screenSaverIsSizeAllowed(cardType, standard.colSpan, standard.rowSpan)) {
      presets.push(standard);
    }
  }
  if (spec === undefined) {
    return presets;
  }
  for (const entry of spec.entries) {
    if (screenSaverIsFallbackEntry(entry) || entry.presetLabel.length === 0) {
      continue;
    }
    const already = presets.some((preset: ScreensaverSizePreset): boolean =>
    preset.colSpan === entry.colSpan && preset.rowSpan === entry.rowSpan);
    if (already) {
      continue;
    }
    const preset: ScreensaverSizePreset = {
      colSpan: entry.colSpan,
      rowSpan: entry.rowSpan,
      label: entry.presetLabel
    };
    presets.push(preset);
  }
  return presets;
}
