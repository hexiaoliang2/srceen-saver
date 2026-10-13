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

const FORMAT_OPTIONS: ClockFormatOption[] = [
  { value: 'timeDate', label: '时间+日期' },
  { value: 'timeOnly', label: '纯时间' },
  { value: 'dateOnly', label: '纯日期' },
  { value: 'lunar', label: '农历' }
];

const FONT_STEP_OPTIONS: ScreensaverNumberOption[] = [
  { value: -1, label: '跟随系统' },
  { value: 0, label: '小' },
  { value: 1, label: '标准' },
  { value: 2, label: '大' }
];

@ComponentV2
export struct ScreenSaverClockSettingsPanel {
  @Param card: ScreensaverCardInstance = new ScreensaverCardInstance();
  @Event onDone: () => void = (): void => {};
  @Event onDelete: () => void = (): void => {};

  private isMinimal(): boolean {
    return this.card.colSpan * this.card.rowSpan < 4;
  }

  private applyChange(): void {
    screenSaverAppModel.save();
  }

  private setFormat(format: ClockFormat): void {
    if (this.isMinimal() && format !== 'timeOnly') {
      this.toast('2×1 尺寸仅支持纯时间，请先调整尺寸');
      return;
    }
    this.card.clock.format = format;
    this.applyChange();
  }

  private applySizePreset(preset: ScreensaverSizePreset): void {
    const resized = screenSaverAppModel.resizeCardTo(this.card.id, preset.colSpan, preset.rowSpan);
    if (!resized) {
      this.toast('该尺寸不可用（与其它卡片重叠或越界）');
    }
  }

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
      ScreenSaverSheetHeader({
        title: '时钟卡片',
        onDone: (): void => {
          this.onDone();
        }
      })
      .padding({ left: 16, right: 16 })

      Scroll() {
        Column({ space: 12 }) {
          Column() {
            ScreensaverClockCard({ card: this.card, cardMode: 'edit' })
          }
          .width('100%')
          .height(120)
          .borderRadius(8)
          .backgroundColor(SCREEN_SAVER_COLORS.cardBg)
          .clip(true)

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

          ScreenSaverToggleRow({
            label: '显示秒',
            tip: '开启后每秒刷新，更耗电',
            isOn: this.card.clock.showSeconds,
            onChange: (value: boolean): void => {
              this.card.clock.showSeconds = value;
              this.applyChange();
            }
          })

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
