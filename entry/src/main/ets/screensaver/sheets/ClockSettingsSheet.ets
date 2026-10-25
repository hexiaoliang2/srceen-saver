/**
 * =============================================================================
 * 时钟卡片设置面板（ClockSettingsSheet.ets）
 * =============================================================================
 *
 * 【这个文件是干什么的】
 * 时钟卡片的设置抽屉：实时预览 + 格式（时间+日期/纯时间/纯日期/农历）、
 * 12/24 小时制、显示秒、字号档位、删除卡片。
 *
 * 【小尺寸怎么处理（缺陷 3 之后的新规则）】
 * 尺寸矩阵（CardCatalog 的 CLOCK_SIZE_SPEC）给每个跨度定义了内容密度：
 *   - minimal（1×1/2×1/3×1）：只渲染时间；
 *   - compact（4×1/1×2/2×2）：时间 + 一行日期；
 *   - full（2×3/4×2/4×3/4×4）：时间 + 日期·农历（遵循下面选的格式）。
 * 格式选择**不再被拦截**，用户选什么就存什么，放大卡片后自动生效；
 * 面板下方用一行小字说明「当前尺寸决定的显示档位」。
 *
 * 【统一交互模式】
 * 每次改动 → 改 card 上的字段（@ObservedV2 自动刷新预览）→ applyChange()
 *   → screenSaverAppModel.save() 持久化。
 *
 * 【预览即真组件】
 * 顶部预览直接渲染 ScreensaverClockCard（cardMode: 'edit'），
 * 所见即所得，不是假图。
 * =============================================================================
 */

import {
  ScreenSaverChip,
  ScreenSaverDeleteCardRow,
  ScreenSaverSheetHeader,
  ScreenSaverToggleRow,
} from '../../common/SheetParts';
import { SCREEN_SAVER_COLORS } from '../../common/ScreenSaverStyle';
import { ScreenSaverLogger } from '../../common/Logger';
import { screenSaverAppModel } from '../../model/AppModel';
import { screenSaverResolveDensity } from '../../cards/CardCatalog';
import { ScreensaverClockCard } from '../../cards/ClockCardView';
import {
  ClockFormat,
  ScreensaverCardDensity,
  ScreensaverCardInstance,
  ScreensaverNumberOption,
} from '../../model/ConfigModels';

interface ClockFormatOption {
  value: ClockFormat;
  label: string;
}

/** 时钟显示格式的四个可选项（label 是胶囊上显示的文字）。 */
const FORMAT_OPTIONS: ClockFormatOption[] = [
  { value: 'timeDate', label: '时间+日期' },
  { value: 'timeOnly', label: '纯时间' },
  { value: 'dateOnly', label: '纯日期' },
  { value: 'lunar', label: '农历' }
];

/** 字号档位：-1 跟随系统、0 小、1 标准、2 大（卡片内会换算成缩放系数）。 */
const FONT_STEP_OPTIONS: ScreensaverNumberOption[] = [
  { value: -1, label: '跟随系统' },
  { value: 0, label: '小' },
  { value: 1, label: '标准' },
  { value: 2, label: '大' }
];

@ComponentV2
export struct ScreenSaverClockSettingsPanel {
  @Param card: ScreensaverCardInstance = new ScreensaverCardInstance();
  /** 「完成」按钮回调（由宿主 ScreensaverPage 关闭抽屉）。 */
  @Event onDone: () => void = (): void => {};
  /** 「删除卡片」回调（宿主负责确认和真正删除）。 */
  @Event onDelete: () => void = (): void => {};

  /**
   * 当前尺寸的内容密度档（尺寸矩阵查表得到）。
   * 用来告诉用户「为什么现在只显示时间」——是尺寸决定的渲染降级，
   * 而不是把他的格式设置改掉了。
   */
  private density(): ScreensaverCardDensity {
    return screenSaverResolveDensity(this.card.cardType, this.card.colSpan, this.card.rowSpan);
  }

  /** 改动后的统一收尾：持久化到磁盘。 */
  private applyChange(): void {
    screenSaverAppModel.save();
  }

  /**
   * 面板标题：带实例标识（如「时钟 · 设置」「相册 1 · 设置」）。
   * 缺陷 1 的验收要求「面板显示且仅显示该卡片的数据」，
   * 标题里写明是哪张卡片，肉眼即可核对。
   */
  private panelTitle(): string {
    return `${screenSaverAppModel.cardInstanceTitle(this.card)} · 设置`;
  }

  /**
   * 切换显示格式。
   * 小尺寸下不再拦截点击：尺寸矩阵会决定实际渲染密度（极简/紧凑/完整），
   * 用户的格式选择照常保存，等卡片放大后自然生效。
   */
  private setFormat(format: ClockFormat): void {
    this.card.clock.format = format;
    this.applyChange();
  }

  /** 弹 toast 提示。 */
  private toast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message, duration: 1500 });
    } catch (err) {
      const error = err as Error;
      ScreenSaverLogger.warn(`toast failed: ${error.message}`);
    }
  }

  /**
   * 切换「悬浮层」（需求 B）：
   * 悬浮后卡片不占网格单元、始终渲染在其他卡片之上，位置在编辑态直接拖动。
   * 取消悬浮时若网格没有空位，模型会返回原因，这里 toast 出来并保持悬浮。
   */
  private setFloating(floating: boolean): void {
    const reason = screenSaverAppModel.setCardFloating(this.card.id, floating);
    if (reason.length > 0) {
      this.toast(reason);
    }
  }

  build() {
    Column() {
      // ---------- 顶栏（标题 + 完成） ----------
      ScreenSaverSheetHeader({
        title: this.panelTitle(),
        onDone: (): void => {
          this.onDone();
        }
      })
      .padding({ left: 16, right: 16 })

      Scroll() {
        Column({ space: 12 }) {
          // ---------- 实时预览 ----------
          // 直接渲染真卡片组件（edit 模式：不响应点击手势，纯展示）。
          Column() {
            ScreensaverClockCard({ card: this.card, cardMode: 'edit' })
          }
          .width('100%')
          .height(120)
          .borderRadius(8)
          .backgroundColor(SCREEN_SAVER_COLORS.cardBg)
          .clip(true)

          // ---------- 格式选择 ----------
          // 小尺寸下不拦截点击：尺寸矩阵决定实际渲染密度，
          // 选择本身照常保存，卡片放大后自动生效（下方小字说明当前状态）。
          Column({ space: 6 }) {
            Text('格式')
              .fontSize(13)
              .fontColor(SCREEN_SAVER_COLORS.textTertiary)
              .width('100%')
            Row({ space: 8 }) {
              ForEach(FORMAT_OPTIONS, (option: ClockFormatOption) => {
                ScreenSaverChip({
                  label: option.label,
                  selected: this.card.clock.format === option.value,
                  onTap: (): void => {
                    this.setFormat(option.value);
                  }
                })
              }, (option: ClockFormatOption): string => option.value)
            }
            .width('100%')
            if (this.density() !== 'full') {
              Text(this.density() === 'minimal' ?
                '当前尺寸为极简档：只显示时间，放大卡片后恢复完整格式' :
                '当前尺寸为紧凑档：显示时间 + 一行日期，放大后显示农历')
                .fontSize(11)
                .fontColor(SCREEN_SAVER_COLORS.textTertiary)
                .width('100%')
            }
          }
          .width('100%')

          // ---------- 12/24 小时制 ----------
          Row() {
            Text('时间制式')
              .fontSize(14)
              .fontColor('#CCCCCC')
            Blank()
            Row({ space: 8 }) {
              ScreenSaverChip({
                label: '12小时',
                selected: !this.card.clock.use24Hour,
                onTap: (): void => {
                  this.card.clock.use24Hour = false;
                  this.applyChange();
                }
              })
              ScreenSaverChip({
                label: '24小时',
                selected: this.card.clock.use24Hour,
                onTap: (): void => {
                  this.card.clock.use24Hour = true;
                  this.applyChange();
                }
              })
            }
          }
          .width('100%')

          // ---------- 显示秒 ----------
          // 开启后卡片从每分钟刷新变成每秒刷新（Ticker 频率切换），更耗电。
          ScreenSaverToggleRow({
            label: '显示秒',
            tip: '开启后每秒刷新，更耗电',
            isOn: this.card.clock.showSeconds,
            onChange: (value: boolean): void => {
              this.card.clock.showSeconds = value;
              this.applyChange();
            }
          })

          // ---------- 字号 ----------
          Row() {
            Text('字号')
              .fontSize(14)
              .fontColor('#CCCCCC')
            Blank()
            Row({ space: 8 }) {
              ForEach(FONT_STEP_OPTIONS, (option: ScreensaverNumberOption) => {
                ScreenSaverChip({
                  label: option.label,
                  selected: this.card.clock.fontStep === option.value,
                  onTap: (): void => {
                    this.card.clock.fontStep = option.value;
                    this.applyChange();
                  }
                })
              }, (option: ScreensaverNumberOption): string => option.label)
            }
          }
          .width('100%')

          // ---------- 悬浮层（需求 B） ----------
          // 悬浮后不占网格、始终在其他卡片之上；位置在编辑态拖动。
          ScreenSaverToggleRow({
            label: '悬浮层',
            tip: '不占用网格，始终显示在其他卡片之上；位置在编辑态直接拖动',
            isOn: this.card.floating,
            onChange: (value: boolean): void => {
              this.setFloating(value);
            }
          })
          if (this.card.floating) {
            ScreenSaverToggleRow({
              label: '锁定位置',
              tip: '开启后编辑态拖动不会改变悬浮位置，避免误触',
              isOn: this.card.floatLocked,
              onChange: (value: boolean): void => {
                screenSaverAppModel.setFloatLocked(this.card.id, value);
              }
            })
          }

          // ---------- 删除卡片 ----------
          ScreenSaverDeleteCardRow({
            onDelete: (): void => {
              this.onDelete();
            }
          })
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 28 })
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .margin({ top: 4 })
    }
    .width('100%')
    .height('100%')
  }
}
