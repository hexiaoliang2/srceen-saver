import { screenSaverTicker, ScreenSaverTickListener } from '../common/Ticker';
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
  ScreensaverCardInstance,
  ScreensaverCardMode
} from '../model/ConfigModels';

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

  @Local mainText: string = '--:--';
  @Local periodText: string = '';
  @Local subText: string = '';
  @Local secondText: string = '';
  @Local mainFont: number = 40;
  @Local subFont: number = 14;
  @Local cardW: number = 0;
  @Local cardH: number = 0;

  private tickListener: ScreenSaverTickListener = {
    onTick: (): void => {
      this.refreshTime();
    },
    needsSecondTick: (): boolean => {
      return this.card.clock.showSeconds && this.card.clock.format !== 'dateOnly' &&
        this.card.clock.format !== 'lunar';
    }
  };

  aboutToAppear(): void {
    this.refreshTime();
    screenSaverTicker.addListener(this.tickListener);
  }

  aboutToDisappear(): void {
    screenSaverTicker.removeListener(this.tickListener);
  }

  @Monitor('card.clock.format', 'card.clock.use24Hour', 'card.clock.showSeconds', 'card.clock.fontStep')
  onClockConfigChanged(): void {
    screenSaverTicker.reschedule();
    this.refreshTime();
  }

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

  private fontStepFactor(): number {
    if (this.card.clock.fontStep <= 0) {
      return 0.85;
    }
    if (this.card.clock.fontStep >= 2) {
      return 1.25;
    }
    return 1;
  }

  private buildPlan(now: Date): ScreenSaverClockFontPlan {
    const format = this.card.clock.format;
    const width = this.cardW > 0 ? this.cardW : 160;
    const height = this.cardH > 0 ? this.cardH : 80;
    const factor = this.fontStepFactor();
    if (format === 'dateOnly') {
      const main = screenSaverFormatDateFull(now);
      const sub = screenSaverFormatWeekdayFull(now);
      const mainFont = this.fitFont(width, height * 0.5, main.length, 0.6) * factor;
      const plan: ScreenSaverClockFontPlan = {
        mainFont: this.clampFont(mainFont),
        subFont: this.clampFont(mainFont * 0.42),
        mainText: main,
        periodText: '',
        subText: sub,
        secondText: ''
      };
      return plan;
    }
    if (format === 'lunar') {
      const parts: ScreenSaverLunarParts = screenSaverFormatLunar(now);
      const mainFont = this.fitFont(width, height * 0.5, parts.lunarLine.length, 0.62) * factor;
      const plan: ScreenSaverClockFontPlan = {
        mainFont: this.clampFont(mainFont),
        subFont: this.clampFont(mainFont * 0.38),
        mainText: parts.lunarLine,
        periodText: '',
        subText: parts.solarLine,
        secondText: ''
      };
      return plan;
    }
    const timeParts: ScreenSaverTimeParts = screenSaverFormatTime(now, this.card.clock.use24Hour,
      this.card.clock.showSeconds && this.card.rowSpan >= 2);
    const charCount = timeParts.mainText.length + (timeParts.periodText.length > 0 ? 1.5 : 0);
    const hasSubtitle = format === 'timeDate' && this.card.rowSpan >= 2;
    const timeHeightShare = hasSubtitle ? 0.62 : 0.86;
    let mainFont = this.fitFont(width, height * timeHeightShare, charCount, 0.62) * factor;
    let subText = '';
    if (hasSubtitle) {
      const withWeekday = this.card.colSpan >= 4;
      subText = `${screenSaverFormatDate(now, withWeekday)} · ${screenSaverFormatLunarShort(now)}`;
    }
    const plan: ScreenSaverClockFontPlan = {
      mainFont: this.clampFont(mainFont),
      subFont: this.clampFont(mainFont * 0.24, 10, 28),
      mainText: timeParts.mainText,
      periodText: timeParts.periodText,
      subText: subText,
      secondText: ''
    };
    return plan;
  }

  private fitFont(width: number, height: number, charCount: number, widthRatio: number): number {
    const usableChars = charCount > 0 ? charCount : 5;
    const byWidth = (width * 0.9) / (widthRatio * usableChars);
    const byHeight = height;
    return Math.min(byWidth, byHeight);
  }

  private clampFont(value: number, min: number = SCREEN_SAVER_CLOCK_MIN_FONT,
    max: number = SCREEN_SAVER_CLOCK_MAX_FONT): number {
    const minimal = this.isMinimalSize() ? SCREEN_SAVER_CLOCK_SMALL_FONT : min;
    if (value < minimal) {
      return minimal;
    }
    if (value > max) {
      return max;
    }
    return value;
  }

  private isMinimalSize(): boolean {
    return this.card.colSpan * this.card.rowSpan < 4;
  }

  build() {
    Column() {
      Row({ space: 4 }) {
        Text(this.mainText)
          .fontSize(this.mainFont)
          .fontColor('#F2F2F2')
          .fontWeight(FontWeight.Medium)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.periodText.length > 0) {
          Text(this.periodText)
            .fontSize(Math.max(10, this.mainFont * 0.28))
            .fontColor('#B3B3B3')
            .maxLines(1)
        }
      }
      .alignItems(VerticalAlign.Bottom)

      if (this.subText.length > 0) {
        Text(this.subText)
          .fontSize(this.subFont)
          .fontColor('#8C8C8C')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 4 })
          .padding({ left: 2, right: 2 })
      }
    }
    .width('100%')
    .height('100%')
    .padding({ left: 10, right: 10 })
    .justifyContent(FlexAlign.Center)
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
