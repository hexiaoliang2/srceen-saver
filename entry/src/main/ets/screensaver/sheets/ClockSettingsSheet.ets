/**
 * =============================================================================
 * 时钟卡片设置面板（ClockSettingsSheet.ets）
 * =============================================================================
 *
 * 【这个文件是干什么的】
 * 时钟卡片的设置抽屉：实时预览 + 格式（时间+日期/纯时间/纯日期/农历）、
 * 12/24 小时制、显示秒、字号档位、尺寸预设、删除卡片。
 *
 * 【最特殊的业务规则：2×1 最小尺寸只支持「纯时间」】
 * 2×1 格子太小，放不下日期/农历，所以：
 *   - setFormat()：最小尺寸下选其它格式会被拦截并 toast 提示；
 *   - 界面上：chipEnabled 让不可用的格式胶囊直接置灰。
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

import { ScreenSaverChip, ScreenSaverDeleteCardRow, ScreenSaverSheetHeader, ScreenSaverToggleRow } from '../../common/SheetParts';
import { SCREEN_SAVER_COLORS } from '../../common/ScreenSaverStyle';
import { ScreenSaverLogger } from '../../common/Logger';
import { screenSaverAppModel } from '../../model/AppModel';
import { screenSaverFindCardMeta } from '../../cards/CardCatalog';
import { ScreensaverClockCard } from '../../cards/ClockCardView';
import {
  ClockFormat,
  ScreensaverCardInstance,
  ScreensaverNumberOption,
  ScreensaverSizePreset
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
   * 是否为最小尺寸（面积 < 4 格，即 2×1）。
   * 最小尺寸只支持纯时间格式，见 setFormat() 的拦截逻辑。
   */
  private isMinimal(): boolean {
    return this.card.colSpan * this.card.rowSpan < 4;
  }

  /** 改动后的统一收尾：持久化到磁盘。 */
  private applyChange(): void {
    screenSaverAppModel.save();
  }

  /**
   * 切换显示格式。
   * 最小尺寸（2×1）下除「纯时间」以外的格式都被拦截——
   * 小格子放不下日期/农历，硬塞会溢出或字号过小。
   */
  private setFormat(format: ClockFormat): void {
    if (this.isMinimal() && format !== 'timeOnly') {
      this.toast('2×1 尺寸仅支持纯时间，请先调整尺寸');
      return;
    }
    this.card.clock.format = format;
    this.applyChange();
  }

  /**
   * 应用尺寸预设：调用 AppModel 的 resizeCardTo（带碰撞/越界校验）。
   * 失败说明目标尺寸与其它卡片重叠或超出网格，toast 提示用户。
   */
  private applySizePreset(preset: ScreensaverSizePreset): void {
    const resized = screenSaverAppModel.resizeCardTo(this.card.id, preset.colSpan, preset.rowSpan);
    if (!resized) {
      this.toast('该尺寸不可用（与其它卡片重叠或越界）');
    }
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

  build() {
    Column() {
      // ---------- 顶栏（标题 + 完成） ----------
      ScreenSaverSheetHeader({
        title: '时钟卡片',
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
          // chipEnabled：最小尺寸时除「纯时间」外的胶囊置灰不可点；
          // 下方再补一行小字说明原因。
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
                  chipEnabled: !this.isMinimal() || option.value === 'timeOnly',
                  onTap: (): void => {
                    this.setFormat(option.value);
                  }
                })
              }, (option: ClockFormatOption): string => option.value)
            }
            .width('100%')
            if (this.isMinimal()) {
              Text('2×1 最小尺寸下仅支持纯时间 32fp')
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

          // ---------- 尺寸预设 ----------
          // 预设列表来自卡片目录（CardCatalog），选中态比对当前跨格数。
          Row() {
            Text('尺寸')
              .fontSize(14)
              .fontColor('#CCCCCC')
            Blank()
            Row({ space: 8 }) {
              ForEach(screenSaverFindCardMeta('clock')?.sizePresets ?? [], (preset: ScreensaverSizePreset) => {
                ScreenSaverChip({
                  label: preset.label,
                  selected: this.card.colSpan === preset.colSpan && this.card.rowSpan === preset.rowSpan,
                  onTap: (): void => {
                    this.applySizePreset(preset);
                  }
                })
              }, (preset: ScreensaverSizePreset): string => preset.label)
            }
          }
          .width('100%')

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
