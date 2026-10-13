/**
 * =============================================================================
 * 时钟卡片视图（ClockCardView.ets）
 * =============================================================================
 *
 * 【这个文件是干什么的】
 * 时钟卡片的界面实现：按所选格式（时间+日期 / 仅时间 / 仅日期 / 农历）
 * 显示时间，并自动「排版」——根据卡片实际宽高计算最合适的主字号和
 * 副字号，保证任何尺寸的格子里都不挤不空。
 *
 * 【刷新机制：为什么不自己开定时器】
 * 所有时钟卡片把一个监听器注册到全局心跳（Ticker）：平时每分钟整点跳一次，
 * 只有开了「显示秒」才升级为每秒跳。好处：多个时钟（屏保 + 预览）共享
 * 一个定时器，后台自动停表，省电且不重复。
 *
 * 【自适应字号（本文件最核心的算法）】
 * buildPlan() 在每次刷新时计算一份「排版方案」：
 *   1. fitFont()：按「可用宽度 / 字符数」和「可用高度」两个约束算出
 *      满足条件的最大字号，取两者较小值；
 *   2. 乘上用户的字号档位系数 fontStepFactor()（小 0.85 / 标准 1 /
 *      大 1.25 / 跟随系统）；
 *   3. clampFont()：夹在 [12, 160] 之间，小卡片额外抬到 32 下限，
 *      避免字号小到看不清。
 * 卡片尺寸变化（编辑模式缩放）时 onAreaChange 触发重新计算。
 * =============================================================================
 */

import { common } from '@kit.AbilityKit';
import { screenSaverTicker, ScreenSaverTickListener } from '../common/Ticker';
import { screenSaverResolveDensity } from './CardCatalog';
import {
  screenSaverFormatDate,
  screenSaverFormatDateFull,
  screenSaverFormatLunar,
  screenSaverFormatLunarShort,
  screenSaverFormatTime,
  screenSaverFormatWeekdayFull,
  ScreenSaverLunarParts,
  ScreenSaverTimeParts
} from '../common/DateFormats';
import {
  SCREEN_SAVER_CLOCK_MAX_FONT,
  SCREEN_SAVER_CLOCK_MIN_FONT,
  SCREEN_SAVER_CLOCK_SMALL_FONT,
  ScreensaverCardDensity,
  ScreensaverCardInstance,
  ScreensaverCardMode
} from '../model/ConfigModels';

/**
 * 时钟文字的可读性光晕（变更项 1，实现侧方案，待确认）。
 * 只作用于文字本身：radius 6px 的深色模糊 + 1px 下偏移，
 * 让浅色文字压在浅色照片/视频画面上时仍可辨认。
 * 明确**不是**卡片底色/边框/遮罩，也不做实时模糊——卡片依旧全透明。
 */
const SCREEN_SAVER_CLOCK_TEXT_SHADOW: ShadowOptions = {
  radius: 6,
  color: '#CC000000',
  offsetX: 0,
  offsetY: 1
};

/**
 * 一次刷新计算出的完整排版方案：
 * 主文字/副文字/上下午的内容 + 主字号/副字号。
 * 把「算什么」和「怎么显示」分开，代码更清晰。
 */
interface ScreenSaverClockFontPlan {
  mainFont: number;
  subFont: number;
  mainText: string;
  periodText: string;
  subText: string;
  secondText: string;
}

@ComponentV2
export struct ScreensaverClockCard {
  @Param card: ScreensaverCardInstance = new ScreensaverCardInstance();
  @Param cardMode: ScreensaverCardMode = 'play';

  /**
   * 当前尺寸对应的内容密度档（尺寸矩阵查表得到）。
   * 直接读 card 的跨度而不是父组件透传的 @Param：@Trace 字段变化会立即
   * 触发本视图重算，不受 ForEach 复用/@Builder 按值传参的影响。
   */
  private density(): ScreensaverCardDensity {
    return screenSaverResolveDensity(this.card.cardType, this.card.colSpan, this.card.rowSpan);
  }

  // ---------- 界面状态（排版方案执行后的显示值） ----------
  @Local mainText: string = '--:--';
  @Local periodText: string = '';
  @Local subText: string = '';
  @Local secondText: string = '';
  @Local mainFont: number = 40;
  @Local subFont: number = 14;
  /** 卡片实际宽高（vp），自适应字号的依据。onAreaChange 里更新。 */
  @Local cardW: number = 0;
  @Local cardH: number = 0;

  /**
   * 注册到全局心跳的监听器对象。
   * needsSecondTick 动态回答「当前是否需要秒级刷新」：
   * 开了显示秒、且不是纯日期/农历格式才需要——
   * 心跳会据此自动在分钟表和秒表之间切换。
   */
  private tickListener: ScreenSaverTickListener = {
    onTick: (): void => {
      this.refreshTime();
    },
    needsSecondTick: (): boolean => {
      return this.card.clock.showSeconds && this.card.clock.format !== 'dateOnly' &&
        this.card.clock.format !== 'lunar';
    }
  };

  /** 组件挂载：立即刷一次时间 + 注册心跳。 */
  aboutToAppear(): void {
    this.refreshTime();
    screenSaverTicker.addListener(this.tickListener);
  }

  /** 组件销毁：注销心跳，防止内存泄漏和僵尸刷新。 */
  aboutToDisappear(): void {
    screenSaverTicker.removeListener(this.tickListener);
  }

  /**
   * 设置面板里改了格式/24小时制/秒/字号档，或卡片尺寸/密度档变化时触发：
   * 先让心跳重新评估「要不要秒级」，再立即刷新界面。
   * （尺寸变化还要参与排版决策，所以 colSpan/rowSpan 也一起监听。）
   */
  @Monitor('card.clock.format', 'card.clock.use24Hour', 'card.clock.showSeconds', 'card.clock.fontStep',
    'card.colSpan', 'card.rowSpan')
  onClockConfigChanged(): void {
    screenSaverTicker.reschedule();
    this.refreshTime();
  }

  /** 每次心跳：按当前时间重算排版方案并写入界面状态。 */
  private refreshTime(): void {
    const now = new Date();
    const plan = this.buildPlan(now);
    this.mainText = plan.mainText;
    this.periodText = plan.periodText;
    this.subText = plan.subText;
    this.secondText = plan.secondText;
    this.mainFont = plan.mainFont;
    this.subFont = plan.subFont;
  }

  /**
   * 字号档位 → 缩放系数。
   * fontStep: -1 跟随系统 / 0 小 / 1 标准 / 2 大。
   * 跟随系统时读系统字号配置并夹在 [0.85, 1.25]——
   * 系统字号太极端也不能把时钟撑爆。
   */
  private fontStepFactor(): number {
    if (this.card.clock.fontStep < 0) {
      return this.systemFontFactor();
    }
    if (this.card.clock.fontStep === 0) {
      return 0.85;
    }
    if (this.card.clock.fontStep >= 2) {
      return 1.25;
    }
    return 1;
  }

  /**
   * 读取系统字号缩放（跟随系统档位）。
   * fontSizeScale 类型是 number|undefined，必须逐项防御：
   * undefined / 非有限数 / 非正数都回退 1（标准）。
   */
  private systemFontFactor(): number {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext | undefined;
    if (context === undefined) {
      return 1;
    }
    const scale = context.config.fontSizeScale;
    if (scale === undefined || !Number.isFinite(scale) || scale <= 0) {
      return 1;
    }
    return Math.min(1.25, Math.max(0.85, scale));
  }

  /**
   * 排版核心：先按「格式 × 内容密度」决定显示哪些文字，再按可用宽高算字号。
   *
   * 密度（来自尺寸矩阵，见 CardCatalog.CLOCK_SIZE_SPEC）：
   *   - minimal（1×1/2×1/3×1）：只显示主行（时间/日期/农历），副行一律不显示；
   *   - compact（4×1/1×2/2×2）：时间类格式追加一行「日期（宽卡带星期）」；
   *   - full（2×3/4×2/4×3/4×4）：完整内容，时间 + 日期·农历，显示秒只在 full 且 ≥2 行时开启。
   * 副行有没有决定主行占多少高度（有副行 62%、没有 86%）。
   */
  private buildPlan(now: Date): ScreenSaverClockFontPlan {
    const format = this.card.clock.format;
    const density = this.density();
    // 卡片还没测出尺寸时用安全默认值，避免除零/NaN
    const width = this.cardW > 0 ? this.cardW : 160;
    const height = this.cardH > 0 ? this.cardH : 80;
    const factor = this.fontStepFactor();
    // ---------- 1. 先决定显示哪些文字 ----------
    let mainText = '';
    let periodText = '';
    let subText = '';
    let subRatio = 0.24;
    if (format === 'dateOnly') {
      // 纯日期：主行「2026年10月13日」，副行「星期二」
      mainText = screenSaverFormatDateFull(now);
      if (density !== 'minimal') {
        subText = screenSaverFormatWeekdayFull(now);
        subRatio = 0.42;
      }
    } else if (format === 'lunar') {
      // 农历：主行「丙午年 · 正月初一」，副行公历对照（仅完整档）
      const parts: ScreenSaverLunarParts = screenSaverFormatLunar(now);
      mainText = parts.lunarLine;
      if (density === 'full') {
        subText = parts.solarLine;
        subRatio = 0.38;
      }
    } else {
      // 时间类格式（timeDate / timeOnly）
      // 显示秒只在「完整档 + 卡片 ≥2 行」时开启（1 行塞不下秒）
      const showSeconds = this.card.clock.showSeconds && density === 'full' && this.card.rowSpan >= 2;
      const timeParts: ScreenSaverTimeParts = screenSaverFormatTime(now, this.card.clock.use24Hour, showSeconds);
      mainText = timeParts.mainText;
      periodText = timeParts.periodText;
      if (format === 'timeDate' && density !== 'minimal') {
        // 副行内容随卡片宽度伸缩：宽卡带星期，窄卡只写日期
        const withWeekday = density === 'full' ? this.card.colSpan >= 4 : this.card.colSpan >= 3;
        subText = screenSaverFormatDate(now, withWeekday);
        if (density === 'full') {
          subText = `${subText} · ${screenSaverFormatLunarShort(now)}`;
        }
      }
    }
    // ---------- 2. 再按「有没有副行」分高度、算字号 ----------
    const charCount = mainText.length + (periodText.length > 0 ? 1.5 : 0);
    const hasSubtitle = subText.length > 0;
    const timeHeightShare = hasSubtitle ? 0.62 : 0.86;
    // 宽度能放下的字号上限：小卡片的「字号地板」不能超过它，
    // 否则 1×1/1×3 这类窄卡会把时间挤出卡片（被省略号截断）。
    const widthLimit = this.widthFitFont(width, charCount, 0.62);
    const mainFont = this.fitFont(width, height * timeHeightShare, charCount, 0.62) * factor;
    const plan: ScreenSaverClockFontPlan = {
      mainFont: this.clampFont(mainFont, SCREEN_SAVER_CLOCK_MIN_FONT, SCREEN_SAVER_CLOCK_MAX_FONT, widthLimit),
      subFont: this.clampFont(mainFont * subRatio, 10, 28, widthLimit),
      mainText: mainText,
      periodText: periodText,
      subText: subText,
      secondText: ''
    };
    return plan;
  }

  /** 只按宽度算的「能放下的最大字号」（用于限制字号地板，防止溢出）。 */
  private widthFitFont(width: number, charCount: number, widthRatio: number): number {
    const usableChars = charCount > 0 ? charCount : 5;
    return (width * 0.9) / (widthRatio * usableChars);
  }

  /**
   * 估算字号：在给定宽高里放下 charCount 个字符的最大字号。
   * 宽度约束：可用宽度 × 0.9 / (字符宽高比 × 字符数)；
   * 高度约束：字号不能超过高度本身；
   * 取两者较小值（宽和高哪个先顶到就用哪个）。
   */
  private fitFont(width: number, height: number, charCount: number, widthRatio: number): number {
    const usableChars = charCount > 0 ? charCount : 5;
    const byWidth = (width * 0.9) / (widthRatio * usableChars);
    const byHeight = height;
    return Math.min(byWidth, byHeight);
  }

  /**
   * 字号夹取到合法范围。
   * 小卡片（格子数<4，如 1×1/2×1/1×3）下限抬到 32vp：时钟是屏保主视觉，
   * 再小就失去「一眼看清时间」的意义。但下限不得超过「宽度能放下的字号」
   * （widthLimit），否则窄卡里时间会被省略号截断——宁可字小一点也要完整显示。
   */
  private clampFont(value: number, min: number = SCREEN_SAVER_CLOCK_MIN_FONT,
    max: number = SCREEN_SAVER_CLOCK_MAX_FONT, widthLimit: number = max): number {
    const rawFloor = this.isMinimalSize() ? SCREEN_SAVER_CLOCK_SMALL_FONT : min;
    const minimal = Math.max(SCREEN_SAVER_CLOCK_MIN_FONT, Math.min(rawFloor, widthLimit));
    if (value < minimal) {
      return minimal;
    }
    if (value > max) {
      return max;
    }
    return value;
  }

  /** 是否属于「小卡片」（时钟卡格子上限是 4×4=16，<4 算很小）。 */
  private isMinimalSize(): boolean {
    return this.card.colSpan * this.card.rowSpan < 4;
  }

  build() {
    Column() {
      // 主行：时间（或日期/农历）+ 可选的 AM/PM 小标
      Row({ space: 4 }) {
        Text(this.mainText)
          .fontSize(this.mainFont)
          .fontColor('#F2F2F2')
          .fontWeight(FontWeight.Medium)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          // 可读性方案（变更项 1，实现侧方案待确认）：文字自带深色光晕，
          // 在任意背景上都可辨认；不引入底色/边框/模糊/遮罩，仍是全透明。
          .textShadow(SCREEN_SAVER_CLOCK_TEXT_SHADOW)
        if (this.periodText.length > 0) {
          // AM/PM 贴着时间底部对齐（VerticalAlign.Bottom），像真实时钟
          Text(this.periodText)
            .fontSize(Math.max(10, this.mainFont * 0.28))
            .fontColor('#B3B3B3')
            .maxLines(1)
            .textShadow(SCREEN_SAVER_CLOCK_TEXT_SHADOW)
        }
      }
      .alignItems(VerticalAlign.Bottom)

      // 副行：日期·农历 / 星期 / 公历对照（没有就不渲染）
      if (this.subText.length > 0) {
        Text(this.subText)
          .fontSize(this.subFont)
          .fontColor('#8C8C8C')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 4 })
          .padding({ left: 2, right: 2 })
          .textShadow(SCREEN_SAVER_CLOCK_TEXT_SHADOW)
      }
    }
    .width('100%')
    .height('100%')
    .padding({ left: 10, right: 10 })
    .justifyContent(FlexAlign.Center)
    // 尺寸变化（编辑模式缩放/断点切换）时记录新尺寸并重新排版。
    // 用「变化超过 1vp 才刷新」的阈值，避免布局系统微抖动引发连环重算。
    .onAreaChange((oldArea: Area, newArea: Area): void => {
      const width = typeof newArea.width === 'number' ? newArea.width : 0;
      const height = typeof newArea.height === 'number' ? newArea.height : 0;
      const changed = Math.abs(width - this.cardW) > 1 || Math.abs(height - this.cardH) > 1;
      this.cardW = width;
      this.cardH = height;
      if (changed) {
        this.refreshTime();
      }
    })
  }
}
