import { ScreenSaverGlowButton } from '../../common/GlowButton';
import { screenSaverTicker } from '../../common/Ticker';
import { screenSaverAppModel } from '../../model/AppModel';
import { ScreenSaverCardInstance, ScreenSaverNumberOption } from '../../model/ConfigModels';

const SCREEN_SAVER_FONT_SCALE_OPTIONS: ScreenSaverNumberOption[] = [
  { value: 0.8, label: '小' },
  { value: 1.0, label: '中' },
  { value: 1.3, label: '大' }
];

@ComponentV2
export struct ScreenSaverClockSettingsPanel {
  @Param card: ScreenSaverCardInstance = new ScreenSaverCardInstance();
  @Event onDone: () => void = (): void => {};

  private applyCardChange(): void {
    screenSaverAppModel.save();
    screenSaverTicker.reschedule();
  }

  build() {
    Column({ space: 10 }) {
      Row() {
        Text('时钟设置')
          .fontSize(15)
          .fontColor('#F2F2F2')
        Blank()
        ScreenSaverGlowButton({
          label: '完成',
          textColor: '#8AB4F8',
          fontSize: 13,
          btnHeight: 28,
          hPadding: 12,
          onTap: (): void => {
            this.onDone();
          }
        })
      }
      .width('100%')

      Row() {
        Text('显示秒')
          .fontSize(14)
          .fontColor('#CCCCCC')
        Blank()
        Toggle({ type: ToggleType.Switch, isOn: this.card.clock.showSeconds })
          .selectedColor('#3D6FBF')
          .onChange((isOn: boolean): void => {
            this.card.clock.showSeconds = isOn;
            this.applyCardChange();
          })
      }
      .width('100%')

      Row() {
        Text('显示日期')
          .fontSize(14)
          .fontColor('#CCCCCC')
        Blank()
        Toggle({ type: ToggleType.Switch, isOn: this.card.clock.showDate })
          .selectedColor('#3D6FBF')
          .onChange((isOn: boolean): void => {
            this.card.clock.showDate = isOn;
            this.applyCardChange();
          })
      }
      .width('100%')

      Row() {
        Text('24 小时制')
          .fontSize(14)
          .fontColor('#CCCCCC')
        Blank()
        Toggle({ type: ToggleType.Switch, isOn: this.card.clock.use24Hour })
          .selectedColor('#3D6FBF')
          .onChange((isOn: boolean): void => {
            this.card.clock.use24Hour = isOn;
            this.applyCardChange();
          })
      }
      .width('100%')

      Row() {
        Text('字号')
          .fontSize(14)
          .fontColor('#CCCCCC')
        Blank()
        ForEach(SCREEN_SAVER_FONT_SCALE_OPTIONS, (option: ScreenSaverNumberOption) => {
          ScreenSaverGlowButton({
            label: option.label,
            textColor: this.card.clock.fontScale === option.value ? '#FFFFFF' : '#BBBBBB',
            baseColor: this.card.clock.fontScale === option.value ? '#3D6FBF' : '#26262B',
            glowColor: '#4A9EFF',
            fontSize: 12,
            btnHeight: 28,
            hPadding: 12,
            marginLeft: 6,
            onTap: (): void => {
              this.card.clock.fontScale = option.value;
              this.applyCardChange();
            }
          })
        }, (option: ScreenSaverNumberOption): string => option.label)
      }
      .width('100%')
    }
    .width('100%')
    .padding(16)
  }
}
