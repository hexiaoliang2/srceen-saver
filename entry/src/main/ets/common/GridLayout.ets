/**
 * =============================================================================
 * 网格布局与坐标换算（GridLayout.ets）—— 变更项 1 的统一坐标基准
 * =============================================================================
 *
 * 【这个文件是干什么的】
 * 把「网格坐标 ↔ 画面坐标」的全部换算收口成一组纯函数：
 *   格宽 = 画布宽 / 列数；格高 = 画布高 / 行数；
 *   卡片画面矩形 = (colStart*格宽, rowStart*格高, colSpan*格宽, rowSpan*格高)；
 *   手指位移 → 跨了几个格子（四舍五入）。
 *
 * 【为什么必须独立成模块（变更项 1 的根因约束）】
 * 修复前，编辑态与屏保展示态各自维护了一套垂直基准：
 *   · 屏保展示态给网格容器额外加了一个「剩余空行折半下移」的 translate
 *     （旧 playCenterOffsetY，只在 !editMode 时返回非 0）；
 *   · 编辑态恒为 0；
 *   · 悬浮层（时钟）又是第三套坐标（绝对定位，不带这个 translate）。
 * 结果就是「进入屏保后网格卡片整体下移，悬浮时钟不动」。
 *
 * 现在两个状态的卡片位置都由本模块的同一组函数推导，页面只负责把度量
 * （画布宽高）与布局数据（卡片跨度）喂进来——**没有任何按模式区分的偏移**，
 * 因此编辑态与屏保展示态的卡片位置按构造就一致。
 *
 * 【单位约定（变更项 3 的根因相关）】
 * 本模块的所有输入输出都是 **vp**（虚拟像素），与 ArkUI 布局、触摸事件
 * （TouchObject.windowX/windowY 官方单位即 vp）保持一致；
 * 仅解码图片时才在调用方把 vp 换算成 px（见 ImageLoader.screenSaverVpToPx）。
 * 严禁把 vp 当成 px 再做一次 px2vp 转换——那会把位移压缩约 1/屏幕密度。
 * =============================================================================
 */

/** 网格度量：画布尺寸 + 行列数 + 单元格尺寸（vp）。 */
export interface ScreenSaverGridMetrics {
  width: number;
  height: number;
  columns: number;
  rows: number;
  cellWidth: number;
  cellHeight: number;
}

/** 行/列跨度（可正可负：负值表示向左/向上）。 */
export interface ScreenSaverSpan {
  colSpan: number;
  rowSpan: number;
}

/** 画布上的矩形（vp，相对画布左上角）。 */
export interface ScreenSaverCanvasRect {
  x: number;
  y: number;
  width: number;
  height: number;
}

/** 数值夹取（网格计算的通用消毒）。 */
export function screenSaverGridClamp(value: number, min: number, max: number): number {
  if (value < min) {
    return min;
  }
  if (value > max) {
    return max;
  }
  return value;
}

/**
 * 由画布尺寸与行列数算出单元格尺寸。
 * 任一参数非法（画布未量出/行列数 ≤0）时退回 1vp 的安全格子，
 * 保证拖动换算不会除零、也不会产生 NaN。
 */
export function screenSaverGridMetrics(width: number, height: number, columns: number,
  rows: number): ScreenSaverGridMetrics {
  const safeColumns = columns > 0 ? columns : 1;
  const safeRows = rows > 0 ? rows : 1;
  const metrics: ScreenSaverGridMetrics = {
    width: width > 0 ? width : 0,
    height: height > 0 ? height : 0,
    columns: safeColumns,
    rows: safeRows,
    cellWidth: width > 0 ? width / safeColumns : 1,
    cellHeight: height > 0 ? height / safeRows : 1
  };
  return metrics;
}

/** 手指位移（vp）→ 跨了几格（四舍五入；负值 = 向左/向上）。 */
export function screenSaverCellDelta(offsetX: number, offsetY: number,
  metrics: ScreenSaverGridMetrics): ScreenSaverSpan {
  const delta: ScreenSaverSpan = {
    colSpan: Math.round(offsetX / metrics.cellWidth),
    rowSpan: Math.round(offsetY / metrics.cellHeight)
  };
  return delta;
}

/**
 * 拉伸（改尺寸）用：手指位移（vp）+ 起始跨度 → 用户「想要」的跨度（未吸附）。
 * 基准必须是**拖动前的跨度**（origin*），否则会以预览中的跨度为基准逐帧叠加，
 * 尺寸会失控放大（见 ScreensaverPage.updateResize 的注释）。
 * 结果下限为 1：网格里不存在 0 列/0 行的卡片，非法值交给尺寸矩阵吸附。
 */
export function screenSaverSpanFromOffset(originColSpan: number, originRowSpan: number, offsetX: number,
  offsetY: number, metrics: ScreenSaverGridMetrics): ScreenSaverSpan {
  const delta = screenSaverCellDelta(offsetX, offsetY, metrics);
  const span: ScreenSaverSpan = {
    colSpan: Math.max(1, originColSpan + delta.colSpan),
    rowSpan: Math.max(1, originRowSpan + delta.rowSpan)
  };
  return span;
}

/** 网格坐标 → 画布矩形（vp）。卡片渲染位置与悬浮层位置共用这一条换算。 */
export function screenSaverRectOf(colStart: number, rowStart: number, colSpan: number, rowSpan: number,
  metrics: ScreenSaverGridMetrics): ScreenSaverCanvasRect {
  const rect: ScreenSaverCanvasRect = {
    x: colStart * metrics.cellWidth,
    y: rowStart * metrics.cellHeight,
    width: colSpan * metrics.cellWidth,
    height: rowSpan * metrics.cellHeight
  };
  return rect;
}

/**
 * 「单卡片垂直居中」（全局设置 singleCardCentered）的行偏移（行）。
 * 语义（编辑态与屏保展示态完全一致——这是变更项 1 的关键）：
 *   只有一张网格卡、没有悬浮卡时才生效；偏移 = 剩余空行的 1/2。
 * 由于偏移只依赖**卡片自身的跨度**（不依赖位置），拖动过程中它是常数，
 * 不会出现「卡片追着手指一格格跳动」的反馈回路。
 */
export function screenSaverCenteredRowOffset(rowStart: number, rowSpan: number, totalRows: number): number {
  const freeRows = totalRows - (rowStart + rowSpan);
  if (freeRows <= 0) {
    return 0;
  }
  return freeRows / 2;
}

/** 行偏移 → vp 偏移。 */
export function screenSaverRowOffsetToVp(rowOffset: number, metrics: ScreenSaverGridMetrics): number {
  return rowOffset * metrics.cellHeight;
}
