/**
 * =============================================================================
 * 卡片字号令牌（CardTypography.ets）
 * =============================================================================
 *
 * 全工程卡片文字字号只从这里取，禁止在卡片视图里写死数字。
 *
 * 需求给定的 L0~L5 六档：
 *   L0 36 / L1 28 / L2 24 / L3 20 / L4 16 / L5 14
 * 但屏保卡片存在 1×1（约 90×90vp）这类极小格位，若全部按 L5=14fp 起排，
 * 名称+涨跌幅+状态标签会立刻溢出。因此在 L5 之下补充两个「密集辅助档」：
 *   L6 12 / L7 10
 * 它们只允许用于：状态标签、时间、代码、免责声明、窄条辅助行；
 * 任何文字不得低于 10fp（硬性下限，见 SCREEN_SAVER_FONT_FLOOR）。
 *
 * 主数字（L0）在 1×1 中若被宽度约束压缩（例如时钟），以实际测量为准，
 * 不得为了凑 L0 而截断内容——见交付文档的逐档实测表。
 * =============================================================================
 */

/** 卡片字号令牌（vp/fp 数值；ArkUI 的 fontSize 数值默认单位 vp，与 fp 等价）。 */
export class ScreenSaverFontTokens {
  readonly L0: number = 36;
  readonly L1: number = 28;
  readonly L2: number = 24;
  readonly L3: number = 20;
  readonly L4: number = 16;
  readonly L5: number = 14;
  /** 密集辅助档（状态标签/代码/时间/免责声明）。 */
  readonly L6: number = 12;
  /** 极小注档，等于硬性下限。 */
  readonly L7: number = 10;
}

export const SCREEN_SAVER_FONT: ScreenSaverFontTokens = new ScreenSaverFontTokens();

/** 任何文字不得低于该值。 */
export const SCREEN_SAVER_FONT_FLOOR: number = 10;

/** 取一个不低于下限的字号（防止后续维护时误写 8/9）。 */
export function screenSaverFontAtLeast(value: number, floor: number = SCREEN_SAVER_FONT_FLOOR): number {
  return value < floor ? floor : value;
}

/**
 * 主数字字号：大卡直接用 L0；小卡按可用高度收缩，但不低于下限。
 * 仅用于「时钟时间/温度/股价/倒计时天数/待办数量」这类主视觉数字。
 */
export function screenSaverDisplayFont(availableHeight: number): number {
  if (availableHeight <= 0) {
    return SCREEN_SAVER_FONT.L0;
  }
  const fitted = Math.floor(availableHeight * 0.52);
  return screenSaverFontAtLeast(Math.min(SCREEN_SAVER_FONT.L0, fitted));
}
