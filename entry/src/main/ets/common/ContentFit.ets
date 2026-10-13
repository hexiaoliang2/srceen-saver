/**
 * =============================================================================
 * 内容适配判据（ContentFit.ets）——变更项 4
 * =============================================================================
 *
 * 【这个文件是干什么的】
 * 把「图片/视频画面怎么放进卡片」这件事抽成**纯函数 + 明确判据**，供卡片视图与
 * 解码器共用，避免各处在 if-else 里各写一遍：
 *
 *   规则（硬性）：
 *     1. 内容一律「等比完全显示」（contain）——绝不裁切；
 *     2. 是否出现黑边，由「内容宽高比」与「卡片宽高比」是否一致决定：
 *          · 比例一致（相对差 ≤ 容差）→ 无黑边（内容正好铺满卡片）
 *          · 内容更宽（contentRatio > cardRatio）→ 上下黑边（letterbox）
 *          · 内容更高（contentRatio < cardRatio）→ 左右黑边（pillarbox）
 *
 *   对应四种典型组合：
 *     方图 + 方卡   → 无黑边
 *     方图 + 长方卡 → 有黑边（上下或左右，取决于卡片是横向还是纵向）
 *     长方图 + 长方卡（比例一致）→ 无黑边
 *     长方图 + 方卡 → 有黑边
 *
 * 【为什么判据要独立成文件，而不是只依赖框架的 Contain】
 * 只写 `ImageFit.Contain` 框架会替我们把画面摆好，但「到底该不该有黑边、黑边在哪一侧、
 * 解码尺寸该开多大」这些决策没有代码级依据，无法回归、也无法验证。
 * 这里把判据显式写出来，用途有三：
 *   a. 日志可核对（每次解码打印 card/content 比例与 bars 结论）；
 *   b. 黑边底色可以按 bars 决定（当前统一用纯黑，见 PhotoCardView 常量）；
 *   c. 解码尺寸按「实际显示像素」算（screenSaverFittedSize），
 *      既不会整张原图解码，也不会把位图放大后再显示导致模糊。
 *
 * 【实现侧方案，待确认】
 * - 容差取 2%（`SCREEN_SAVER_FIT_RATIO_TOLERANCE`）：比例差在 2% 以内视为「一致」，
 *   日志记为无黑边；这只是一个**判定阈值**，不影响实际渲染（渲染始终是 contain，
 *   真到 1px 级别的比例差依旧由框架按等比缩放处理，不会裁切）。
 * =============================================================================
 */

/** 黑边出现的方向：none 无黑边 / horizontal 上下黑边 / vertical 左右黑边。 */
export type ScreenSaverFitBars = 'none' | 'horizontal' | 'vertical';

/** 一次适配判定的结果。 */
export interface ScreenSaverFitDecision {
  bars: ScreenSaverFitBars;
  contentRatio: number;
  cardRatio: number;
  /** 相对差：|内容比例 - 卡片比例| / 卡片比例。 */
  relativeGap: number;
}

/** 比例一致的判定容差（实现侧方案，待确认）。 */
export const SCREEN_SAVER_FIT_RATIO_TOLERANCE: number = 0.02;

/** 解码结果的尺寸（px），保持内容原始宽高比。 */
export interface ScreenSaverFitSize {
  width: number;
  height: number;
}

/**
 * 判据主体：内容尺寸 + 卡片尺寸 → 黑边结论。
 * 任一参数非法（≤0）时按「无黑边、比例视为一致」处理，调用方按兜底渲染。
 */
export function screenSaverDecideFit(contentWidth: number, contentHeight: number, cardWidth: number,
  cardHeight: number): ScreenSaverFitDecision {
  if (contentWidth <= 0 || contentHeight <= 0 || cardWidth <= 0 || cardHeight <= 0) {
    const fallback: ScreenSaverFitDecision = {
      bars: 'none',
      contentRatio: 0,
      cardRatio: 0,
      relativeGap: 0
    };
    return fallback;
  }
  const contentRatio = contentWidth / contentHeight;
  const cardRatio = cardWidth / cardHeight;
  const relativeGap = Math.abs(contentRatio - cardRatio) / cardRatio;
  let bars: ScreenSaverFitBars = 'none';
  if (relativeGap > SCREEN_SAVER_FIT_RATIO_TOLERANCE) {
    bars = contentRatio > cardRatio ? 'horizontal' : 'vertical';
  }
  const decision: ScreenSaverFitDecision = {
    bars: bars,
    contentRatio: contentRatio,
    cardRatio: cardRatio,
    relativeGap: relativeGap
  };
  return decision;
}

/**
 * 计算解码尺寸（px）：把原图**等比缩到刚好放进卡片显示区**，并夹住长边上限。
 *
 * 三条硬约束：
 *   1. **禁止整张原图解码**：返回值只会在「卡片显示区」范围内，解码器按它做子采样；
 *   2. **禁止放大**：缩放系数 fit 不超过 1（小图保持原尺寸，放大交给渲染层）；
 *   3. **保持宽高比**：短边不足 1px 时抬到 1px，绝不为了凑最小值而拉伸画面。
 * 极端比例（超宽/超高）由长边上限 maxEdge 兜底，防止超大位图占内存。
 */
export function screenSaverFittedSize(originWidth: number, originHeight: number, containerWidth: number,
  containerHeight: number, maxEdge: number): ScreenSaverFitSize {
  if (originWidth <= 0 || originHeight <= 0) {
    const empty: ScreenSaverFitSize = { width: 1, height: 1 };
    return empty;
  }
  const safeContainerW = containerWidth > 0 ? containerWidth : originWidth;
  const safeContainerH = containerHeight > 0 ? containerHeight : originHeight;
  // 等比放进容器：取宽、高两个方向缩放系数的较小值；不放大（上限 1）
  const fit = Math.min(1, safeContainerW / originWidth, safeContainerH / originHeight);
  let width = Math.max(1, Math.round(originWidth * fit));
  let height = Math.max(1, Math.round(originHeight * fit));
  const longEdge = Math.max(width, height);
  const safeMaxEdge = maxEdge > 0 ? maxEdge : longEdge;
  if (longEdge > safeMaxEdge) {
    const shrink = safeMaxEdge / longEdge;
    width = Math.max(1, Math.round(width * shrink));
    height = Math.max(1, Math.round(height * shrink));
  }
  const size: ScreenSaverFitSize = { width: width, height: height };
  return size;
}
