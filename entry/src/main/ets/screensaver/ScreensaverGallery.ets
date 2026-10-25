/**
 * 固定主题锁屏（gallery，2026-10-24 新交互版）。
 *
 * - 全屏主题页：时间、日期、天气 + 主题点击互动；
 * - 仅点击，不含任何滑动切主题；主题由「屏保设置」选择并持久化；
 * - 时钟只在分钟边界更新一次，静止态没有常驻动画。
 */

import {
  ScreensaverWeatherCondition,
  screenSaverClampGalleryTheme
} from '../model/ConfigModels';
import { screenSaverWeatherViewModel } from '../model/WeatherViewModel';
import { ScreensaverGalleryThemeView } from './gallery/GalleryThemeView';
import { screenSaverGalleryThemeOf } from './gallery/GalleryThemePalette';

const GALLERY_WEEKDAYS: string[] = ['星期日', '星期一', '星期二', '星期三', '星期四', '星期五', '星期六'];

@ComponentV2
export struct ScreensaverGallery {
  @Param themeIndex: number = 0;
  @Param active: boolean = true;
  // 固定屏保互动已全部注释：不再向外转发屏幕点击（胶囊/主题特效均不触发）
  // @Event onScreenTap: () => void = (): void => {};

  @Local private viewWidth: number = 0;
  @Local private viewHeight: number = 0;
  @Local private nowMs: number = Date.now();

  private clockTimer: number = -1;

  aboutToAppear(): void {
    this.refreshClock();
    this.scheduleClock();
  }

  aboutToDisappear(): void {
    this.clearClockTimer();
  }

  @Monitor('active')
  onActiveChanged(): void {
    if (this.active) {
      this.refreshClock();
      this.scheduleClock();
    } else {
      this.clearClockTimer();
    }
  }

  private refreshClock(): void {
    this.nowMs = Date.now();
  }

  private clearClockTimer(): void {
    if (this.clockTimer >= 0) {
      clearTimeout(this.clockTimer);
      this.clockTimer = -1;
    }
  }

  private scheduleClock(): void {
    this.clearClockTimer();
    if (!this.active) {
      return;
    }
    const delay = 60000 - (Date.now() % 60000) + 30;
    this.clockTimer = setTimeout((): void => {
      this.clockTimer = -1;
      this.refreshClock();
      this.scheduleClock();
    }, delay);
  }

  private timeText(): string {
    const date = new Date(this.nowMs);
    const hour = date.getHours().toString().padStart(2, '0');
    const minute = date.getMinutes().toString().padStart(2, '0');
    return `${hour}:${minute}`;
  }

  private dateText(): string {
    const date = new Date(this.nowMs);
    return `${date.getMonth() + 1}月${date.getDate()}日 ${GALLERY_WEEKDAYS[date.getDay()]}`;
  }

  private hasWeather(): boolean {
    const model = screenSaverWeatherViewModel;
    return (model.state === 'success' || model.state === 'offline') && model.fetchedAt > 0;
  }

  private tempText(): string {
    if (!this.hasWeather()) {
      return '--°';
    }
    return `${Math.round(screenSaverWeatherViewModel.tempC)}°`;
  }

  private weatherText(): string {
    if (!this.hasWeather()) {
      return '';
    }
    return screenSaverWeatherViewModel.description;
  }

  private condition(): ScreensaverWeatherCondition {
    if (!this.hasWeather()) {
      return 'unknown';
    }
    return screenSaverWeatherViewModel.condition;
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.viewWidth > 0) {
        ScreensaverGalleryThemeView({
          theme: screenSaverGalleryThemeOf(screenSaverClampGalleryTheme(this.themeIndex)),
          widthVp: this.viewWidth,
          heightVp: this.viewHeight,
          timeText: this.timeText(),
          dateText: this.dateText(),
          tempText: this.tempText(),
          weatherText: this.weatherText(),
          condition: this.condition()
          // 固定屏保互动已全部注释：不再向外转发屏幕点击
          // onScreenTap: (): void => {
          //   this.onScreenTap();
          // }
        })
      }
    }
    .width('100%')
    .height('100%')
    .clip(true)
    .onAreaChange((oldArea: Area, newArea: Area): void => {
      this.viewWidth = typeof newArea.width === 'number' ? newArea.width : 0;
      this.viewHeight = typeof newArea.height === 'number' ? newArea.height : 0;
    })
  }
}
