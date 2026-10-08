import { screenSaverTicker, ScreenSaverTickListener } from '../common/Ticker';
import {
  SCREEN_SAVER_CLOCK_MAX_FONT,
  SCREEN_SAVER_CLOCK_MIN_FONT,
  ScreenSaverCardInstance,
  ScreenSaverCardMode
} from '../model/ConfigModels';

const SCREEN_SAVER_WEEK_NAMES: string[] = ['日', '一', '二', '三', '四', '五', '六'];

@ComponentV2
export struct ScreenSaverClockCard {
  @Param card: ScreenSaverCardInstance = new ScreenSaverCardInstance();
  @Param cardMode: ScreenSaverCardMode = 'play';

  @Local timeText: string = '--:--';
  @Local periodText: string = '';
  @Local dateText: string = '';
  @Local cardW: number = 0;
  @Local cardH: number = 0;

  private tickListener: ScreenSaverTickListener = {
    onTick: (): void => {
      this.refreshTime();
    },
    needsSecondTick: (): boolean => {
      return this.card.clock.showSeconds;
    }
  };

  aboutToAppear(): void {
    this.refreshTime();
    screenSaverTicker.addListener(this.tickListener);
  }

  aboutToDisappear(): void {
    screenSaverTicker.removeListener(this.tickListener);
  }

  private refreshTime(): void {
    const now = new Date();
    const showSeconds = this.card.clock.showSeconds;
    const use24Hour = this.card.clock.use24Hour;
    let hours = now.getHours();
    let period = '';
    if (!use24Hour) {
      period = hours >= 12 ? 'PM' : 'AM';
      hours = hours % 12;
      if (hours === 0) {
        hours = 12;
      }
    }
    const minutes = now.getMinutes().toString().padStart(2, '0');
    let text = `${hours.toString().padStart(2, '0')}:${minutes}`;
    if (showSeconds) {
      text = `${text}:${now.getSeconds().toString().padStart(2, '0')}`;
    }
    this.timeText = text;
    this.periodText = period;
    if (this.card.clock.showDate) {
      this.dateText = `${now.getMonth() + 1}月${now.getDate()}日 周${SCREEN_SAVER_WEEK_NAMES[now.getDay()]}`;
    }
  }

  private timeFontSize(): number {
    const width = this.cardW > 0 ? this.cardW : 120;
    const height = this.cardH > 0 ? this.cardH : 80;
    let charCount = this.card.clock.showSeconds ? 8 : 5;
    if (!this.card.clock.use24Hour) {
      charCount += 1.5;
    }
    const byWidth = (width * 0.9) / (0.6 * charCount);
    const byHeight = height * 0.52;
    const base = Math.min(byWidth, byHeight) * this.card.clock.fontScale;
    return Math.max(SCREEN_SAVER_CLOCK_MIN_FONT, Math.min(base, SCREEN_SAVER_CLOCK_MAX_FONT));
  }

  private dateVisible(): boolean {
    return this.card.clock.showDate && this.card.rowSpan >= 2;
  }

  build() {
    Column() {
      Row({ space: 4 }) {
        Text(this.timeText)
          .fontSize(this.timeFontSize())
          .fontColor('#F2F2F2')
          .fontWeight(FontWeight.Medium)
          .maxLines(1)
        if (this.periodText.length > 0) {
          Text(this.periodText)
            .fontSize(this.timeFontSize() * 0.3)
            .fontColor('#B3B3B3')
            .maxLines(1)
        }
      }
      .alignItems(VerticalAlign.Bottom)

      if (this.dateVisible()) {
        Text(this.dateText)
          .fontSize(Math.max(10, this.timeFontSize() * 0.28))
          .fontColor('#8C8C8C')
          .maxLines(1)
          .margin({ top: 2 })
      }
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .onAreaChange((oldArea: Area, newArea: Area): void => {
      this.cardW = typeof newArea.width === 'number' ? newArea.width : 0;
      this.cardH = typeof newArea.height === 'number' ? newArea.height : 0;
    })
  }
}
