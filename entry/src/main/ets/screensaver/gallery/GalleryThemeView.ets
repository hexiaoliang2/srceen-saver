/**
 * 固定锁屏单页主题视图（按 2026-10-24 新版设计稿重做）。
 *
 * - 背景使用设计稿裁切并去除烘焙时间/日期/天气后的整屏图片；
 * - 只支持点击互动：时间 / 天气 / 背景；植物温室额外支持叶片；
 * - 所有互动均为一次性 300/400ms 反馈，结束后归零，静止态无常驻动画；
 * - 不含任何滑动切主题逻辑。
 */

import { ScreenSaverLogger } from '../../common/Logger';
import {
  ScreensaverGalleryTheme,
  ScreensaverWeatherCondition
} from '../../model/ConfigModels';
import {
  screenSaverGalleryPalette,
  screenSaverGalleryThemeName,
  ScreensaverGalleryPalette
} from './GalleryThemePalette';

interface GalleryTextLayout {
  center: boolean;
  topRatio: number;
  leftRatio: number;
  timeRatio: number;
  weatherInCorner: boolean;
}

interface GalleryPixelSpark {
  dx: number;
  dy: number;
  size: number;
}

const GALLERY_PIXEL_SPARKS: GalleryPixelSpark[] = [
  { dx: -1.0, dy: -0.2, size: 3 },
  { dx: -0.7, dy: -0.7, size: 2 },
  { dx: -0.2, dy: -1.0, size: 3 },
  { dx: 0.3, dy: -0.9, size: 2 },
  { dx: 0.8, dy: -0.5, size: 3 },
  { dx: 1.0, dy: 0.1, size: 2 },
  { dx: 0.7, dy: 0.7, size: 3 },
  { dx: 0.2, dy: 1.0, size: 2 },
  { dx: -0.4, dy: 0.9, size: 3 },
  { dx: -0.9, dy: 0.5, size: 2 }
];

const GALLERY_PIXEL_BARS: string[] = [
  '#FFD76A', '#FFA84B', '#FF6B8A', '#63E6FF',
  '#4B9BFF', '#F2C36B', '#FFD76A', '#63E6FF'
];

const GALLERY_EFFECT_TIME_MS: number = 300;
const GALLERY_EFFECT_BG_MS: number = 400;
const GALLERY_EFFECT_PLANT_MS: number = 400;

@ComponentV2
export struct ScreensaverGalleryThemeView {
  @Param theme: ScreensaverGalleryTheme = ScreensaverGalleryTheme.Ink;
  @Param widthVp: number = 0;
  @Param heightVp: number = 0;
  @Param timeText: string = '';
  @Param dateText: string = '';
  @Param tempText: string = '--°';
  @Param weatherText: string = '';
  @Param condition: ScreensaverWeatherCondition = 'unknown';
  @Event onScreenTap: () => void = (): void => {};

  @Local private effectKind: string = 'none';
  @Local private effectProgress: number = 0;

  private effectStartTimer: number = -1;
  private effectResetTimer: number = -1;
  private backgroundTapTimer: number = -1;
  private lastForegroundTapMs: number = 0;

  aboutToDisappear(): void {
    this.clearEffectTimer();
    this.clearBackgroundTapTimer();
  }

  @Monitor('theme')
  onThemeChanged(): void {
    this.clearEffectTimer();
    this.clearBackgroundTapTimer();
    this.effectKind = 'none';
    this.effectProgress = 0;
  }

  private palette(): ScreensaverGalleryPalette {
    return screenSaverGalleryPalette(this.theme);
  }

  private isLandscape(): boolean {
    return this.widthVp > this.heightVp;
  }

  private layout(): GalleryTextLayout {
    const landscape = this.isLandscape();
    if (this.theme === ScreensaverGalleryTheme.Neon) {
      if (landscape) {
        return {
          center: false, topRatio: 0.11, leftRatio: 0.058,
          timeRatio: 0.065, weatherInCorner: true
        };
      }
      return {
        center: false, topRatio: 0.07, leftRatio: 0.05,
        timeRatio: 0.18, weatherInCorner: true
      };
    }
    if (this.theme === ScreensaverGalleryTheme.Pixel) {
      if (landscape) {
        return {
          center: true, topRatio: 0.072, leftRatio: 0,
          timeRatio: 0.085, weatherInCorner: false
        };
      }
      return {
        center: true, topRatio: 0.115, leftRatio: 0,
        timeRatio: 0.21, weatherInCorner: false
      };
    }
    if (this.theme === ScreensaverGalleryTheme.Greenhouse) {
      if (landscape) {
        return {
          center: true, topRatio: 0.139, leftRatio: 0,
          timeRatio: 0.082, weatherInCorner: false
        };
      }
      return {
        center: true, topRatio: 0.123, leftRatio: 0,
        timeRatio: 0.21, weatherInCorner: false
      };
    }
    if (landscape) {
      return {
        center: false, topRatio: 0.105, leftRatio: 0.04,
        timeRatio: 0.095, weatherInCorner: false
      };
    }
    return {
      center: true, topRatio: 0.07, leftRatio: 0,
      timeRatio: 0.25, weatherInCorner: false
    };
  }

  private timeFontSize(): number {
    const l = this.layout();
    return Math.max(40, Math.min(this.widthVp * l.timeRatio, this.heightVp * 0.34));
  }

  private dateFontSize(): number {
    return Math.max(13, this.timeFontSize() * 0.20);
  }

  private tempFontSize(): number {
    return Math.max(15, this.timeFontSize() * 0.24);
  }

  private weatherFontSize(): number {
    return Math.max(12, this.timeFontSize() * 0.17);
  }

  private glyphSize(): number {
    return Math.max(22, this.timeFontSize() * 0.26);
  }

  private topPad(): number {
    return this.heightVp * this.layout().topRatio;
  }

  private leftPad(): number {
    return this.widthVp * this.layout().leftRatio;
  }

  private galleryBackground(): Resource {
    if (this.theme === ScreensaverGalleryTheme.Neon) {
      return this.isLandscape() ? $r('app.media.gallery_neon_landscape') : $r('app.media.gallery_neon_portrait');
    }
    if (this.theme === ScreensaverGalleryTheme.Pixel) {
      return this.isLandscape() ? $r('app.media.gallery_pixel_landscape') : $r('app.media.gallery_pixel_portrait');
    }
    if (this.theme === ScreensaverGalleryTheme.Greenhouse) {
      return this.isLandscape() ? $r('app.media.gallery_plant_landscape') : $r('app.media.gallery_plant_portrait');
    }
    return this.isLandscape() ? $r('app.media.gallery_ink_landscape') : $r('app.media.gallery_ink_portrait');
  }

  private textShadow(): ShadowOptions {
    if (this.theme === ScreensaverGalleryTheme.Ink) {
      return { radius: 0, color: '#00000000', offsetX: 0, offsetY: 0 };
    }
    return { radius: 0, color: '#59000000', offsetX: 0, offsetY: 1 };
  }

  private ringShadow(): ShadowOptions {
    const glow = this.palette().ringGlow;
    if (glow.length === 0) {
      return { radius: 0, color: '#00000000', offsetX: 0, offsetY: 0 };
    }
    return { radius: 14, color: glow, offsetX: 0, offsetY: 0 };
  }

  private effectWave(): number {
    return Math.sin(this.effectProgress * Math.PI);
  }

  private clearEffectTimer(): void {
    if (this.effectStartTimer >= 0) {
      clearTimeout(this.effectStartTimer);
      this.effectStartTimer = -1;
    }
    if (this.effectResetTimer >= 0) {
      clearTimeout(this.effectResetTimer);
      this.effectResetTimer = -1;
    }
  }

  private clearBackgroundTapTimer(): void {
    if (this.backgroundTapTimer >= 0) {
      clearTimeout(this.backgroundTapTimer);
      this.backgroundTapTimer = -1;
    }
  }

  private effectDuration(kind: string): number {
    if (kind === 'background') {
      return GALLERY_EFFECT_BG_MS;
    }
    if (this.theme === ScreensaverGalleryTheme.Greenhouse) {
      return GALLERY_EFFECT_PLANT_MS;
    }
    return GALLERY_EFFECT_TIME_MS;
  }

  private triggerEffect(kind: string): void {
    if (this.widthVp <= 0 || this.heightVp <= 0) {
      return;
    }
    ScreenSaverLogger.info(`gallery theme effect: ${screenSaverGalleryThemeName(this.theme)} ${kind}`);
    this.clearEffectTimer();
    this.effectKind = kind;
    this.effectProgress = 0.001;
    const duration = this.effectDuration(kind);
    this.effectStartTimer = setTimeout((): void => {
      this.effectStartTimer = -1;
      this.getUIContext().animateTo({
        duration: duration,
        curve: Curve.EaseOut
      }, (): void => {
        this.effectProgress = 1;
      });
    }, 16);
    this.effectResetTimer = setTimeout((): void => {
      this.effectResetTimer = -1;
      this.effectProgress = 0;
      this.effectKind = 'none';
    }, duration + 60);
  }

  private triggerForeground(kind: string): void {
    this.lastForegroundTapMs = Date.now();
    this.onScreenTap();
    this.triggerEffect(kind);
  }

  private onBackgroundTap(): void {
    this.onScreenTap();
    this.clearBackgroundTapTimer();
    this.backgroundTapTimer = setTimeout((): void => {
      this.backgroundTapTimer = -1;
      if (Date.now() - this.lastForegroundTapMs < 120) {
        return;
      }
      this.triggerEffect('background');
    }, 0);
  }

  private backgroundShiftX(): number {
    if (this.effectKind !== 'background') {
      return 0;
    }
    const wave = this.effectWave();
    if (this.theme === ScreensaverGalleryTheme.Neon) {
      return 12 * wave;
    }
    if (this.theme === ScreensaverGalleryTheme.Pixel) {
      return 10 * wave;
    }
    if (this.theme === ScreensaverGalleryTheme.Greenhouse) {
      return 0;
    }
    return 10 * wave;
  }

  private backgroundShiftY(): number {
    if (this.effectKind !== 'background') {
      return 0;
    }
    const wave = this.effectWave();
    if (this.theme === ScreensaverGalleryTheme.Neon) {
      return 2 * wave;
    }
    if (this.theme === ScreensaverGalleryTheme.Pixel) {
      return -2 * wave;
    }
    if (this.theme === ScreensaverGalleryTheme.Greenhouse) {
      return 0;
    }
    return -5 * wave;
  }

  private pixelTimeAngle(): number {
    if (this.theme !== ScreensaverGalleryTheme.Pixel || this.effectKind !== 'time') {
      return 0;
    }
    return this.effectWave() * 82;
  }

  private dateColor(): string {
    if (this.effectKind === 'time' && this.theme === ScreensaverGalleryTheme.Ink) {
      return this.palette().textPrimary;
    }
    return this.palette().textSecondary;
  }

  private dateHighlight(): string {
    if (this.effectKind !== 'time') {
      return '#00000000';
    }
    return this.palette().dateHighlight;
  }

  private showStatusBars(): boolean {
    return this.theme === ScreensaverGalleryTheme.Pixel && this.effectKind === 'time';
  }

  // ==================== 天气图标（纯图形） ====================

  @Builder
  sunGlyph(size: number) {
    Stack() {
      if (this.palette().weatherOutline) {
        Circle()
          .width(size * 0.48)
          .height(size * 0.48)
          .fill('#00000000')
          .stroke(this.palette().weatherAccent)
          .strokeWidth(1.2)
          .position({ x: size * 0.26, y: size * 0.26 })
      } else {
        Circle()
          .width(size * 0.48)
          .height(size * 0.48)
          .fill(this.palette().weatherAccent)
          .position({ x: size * 0.26, y: size * 0.26 })
      }
      Row()
        .width(size * 0.16)
        .height(1.2)
        .backgroundColor(this.palette().weatherAccent)
        .position({ x: size * 0.42, y: 0 })
      Row()
        .width(size * 0.16)
        .height(1.2)
        .backgroundColor(this.palette().weatherAccent)
        .position({ x: size * 0.42, y: size * 0.97 })
      Row()
        .width(1.2)
        .height(size * 0.16)
        .backgroundColor(this.palette().weatherAccent)
        .position({ x: 0, y: size * 0.42 })
      Row()
        .width(1.2)
        .height(size * 0.16)
        .backgroundColor(this.palette().weatherAccent)
        .position({ x: size * 0.97, y: size * 0.42 })
      Row()
        .width(size * 0.14)
        .height(1.2)
        .backgroundColor(this.palette().weatherAccent)
        .position({ x: size * 0.20, y: size * 0.20 })
        .rotate({ angle: 45 })
      Row()
        .width(size * 0.14)
        .height(1.2)
        .backgroundColor(this.palette().weatherAccent)
        .position({ x: size * 0.66, y: size * 0.20 })
        .rotate({ angle: -45 })
      Row()
        .width(size * 0.14)
        .height(1.2)
        .backgroundColor(this.palette().weatherAccent)
        .position({ x: size * 0.20, y: size * 0.66 })
        .rotate({ angle: -45 })
      Row()
        .width(size * 0.14)
        .height(1.2)
        .backgroundColor(this.palette().weatherAccent)
        .position({ x: size * 0.66, y: size * 0.66 })
        .rotate({ angle: 45 })
    }
    .width(size)
    .height(size)
  }

  @Builder
  cloudGlyph(size: number) {
    Stack() {
      Circle()
        .width(size * 0.34)
        .height(size * 0.34)
        .fill(this.palette().weatherAccent)
        .position({ x: size * 0.16, y: size * 0.16 })
      Row()
        .width(size * 0.62)
        .height(size * 0.22)
        .borderRadius(size * 0.11)
        .backgroundColor(this.palette().weatherAccent)
        .position({ x: size * 0.22, y: size * 0.28 })
      Row()
        .width(size * 0.84)
        .height(size * 0.24)
        .borderRadius(size * 0.12)
        .backgroundColor(this.palette().weatherAccent)
        .position({ x: size * 0.08, y: size * 0.50 })
    }
    .width(size)
    .height(size)
  }

  @Builder
  weatherGlyph(size: number) {
    if (this.condition === 'cloudy' || this.condition === 'overcast' ||
      this.condition === 'rain' || this.condition === 'drizzle' ||
      this.condition === 'showers' || this.condition === 'freezing' ||
      this.condition === 'snow' || this.condition === 'fog' ||
      this.condition === 'thunder') {
      this.cloudGlyph(size)
    } else {
      this.sunGlyph(size)
    }
  }

  // ==================== 一次性互动层 ====================

  @Builder
  inkDiffusion() {
    Stack() {
      Circle()
        .width(46)
        .height(46)
        .fill('#2B3E49')
        .scale({ x: 0.2 + this.effectProgress * 1.7, y: 0.2 + this.effectProgress * 1.7 })
        .opacity((1 - this.effectProgress) * 0.18)
      Circle()
        .width(34)
        .height(34)
        .fill('#4C616B')
        .scale({ x: 0.3 + this.effectProgress * 1.9, y: 0.3 + this.effectProgress * 1.9 })
        .opacity((1 - this.effectProgress) * 0.24)
      Circle()
        .width(16)
        .height(16)
        .fill('#1F2A33')
        .scale({ x: 0.5 + this.effectProgress * 2.2, y: 0.5 + this.effectProgress * 2.2 })
        .opacity((1 - this.effectProgress) * 0.32)
    }
    .width(40)
    .height(40)
  }

  @Builder
  neonGlow() {
    Stack() {
      Circle()
        .width(40)
        .height(40)
        .fill(this.palette().accent)
        .scale({ x: 0.4 + this.effectProgress * 1.6, y: 0.4 + this.effectProgress * 1.6 })
        .opacity((1 - this.effectProgress) * 0.30)
      Circle()
        .width(24)
        .height(24)
        .fill(this.palette().accentSoft)
        .scale({ x: 0.5 + this.effectProgress * 1.8, y: 0.5 + this.effectProgress * 1.8 })
        .opacity((1 - this.effectProgress) * 0.38)
    }
    .width(40)
    .height(40)
  }

  @Builder
  pixelFlicker() {
    Stack() {
      ForEach(GALLERY_PIXEL_SPARKS, (spark: GalleryPixelSpark) => {
        Row()
          .width(spark.size)
          .height(spark.size)
          .backgroundColor(this.palette().accent)
          .translate({
            x: spark.dx * this.effectProgress * 30,
            y: spark.dy * this.effectProgress * 30
          })
          .opacity(1 - this.effectProgress)
      }, (spark: GalleryPixelSpark, index: number): string => `spark_${spark.dx}_${index}`)
    }
    .width(40)
    .height(40)
  }

  @Builder
  greenhouseGlow() {
    Stack() {
      Circle()
        .width(38)
        .height(38)
        .fill(this.palette().accent)
        .scale({ x: 0.3 + this.effectProgress * 1.8, y: 0.3 + this.effectProgress * 1.8 })
        .opacity((1 - this.effectProgress) * 0.28)
    }
    .width(40)
    .height(40)
  }

  @Builder
  weatherEffectLayer() {
    if (this.theme === ScreensaverGalleryTheme.Neon) {
      this.neonGlow()
    } else if (this.theme === ScreensaverGalleryTheme.Pixel) {
      this.pixelFlicker()
    } else if (this.theme === ScreensaverGalleryTheme.Greenhouse) {
      this.greenhouseGlow()
    } else {
      this.inkDiffusion()
    }
  }

  @Builder
  timeRing() {
    Row()
      .width(this.timeFontSize() * 3.4)
      .height(this.timeFontSize() * 1.55)
      .borderRadius(this.timeFontSize())
      .border({ width: 1.2, color: this.palette().ringColor })
      .shadow(this.ringShadow())
      .opacity(this.effectWave() * 0.55)
      .scale({
        x: 0.94 + this.effectProgress * 0.08,
        y: 0.94 + this.effectProgress * 0.08
      })
  }

  @Builder
  pixelStatusBars() {
    Row({ space: 3 }) {
      ForEach(GALLERY_PIXEL_BARS, (color: string, index: number) => {
        Row()
          .width(this.timeFontSize() * 0.075)
          .height(this.timeFontSize() * 0.05)
          .backgroundColor(color)
      }, (color: string, index: number): string => `bar_${index}`)
    }
    .opacity(this.showStatusBars() ? this.effectWave() : 0)
  }

  // ==================== 天气行 ====================

  @Builder
  weatherIconBox() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.effectKind === 'weather' && this.effectProgress > 0) {
        this.weatherEffectLayer()
      }
      this.weatherGlyph(this.glyphSize())
    }
    .width(this.glyphSize() * 1.25)
    .height(this.glyphSize() * 1.25)
  }

  @Builder
  weatherReadout() {
    Row({ space: 4 }) {
      Text(this.tempText)
        .fontSize(this.tempFontSize())
        .fontColor(this.palette().textPrimary)
        .fontWeight(FontWeight.Medium)
        .maxLines(1)
        .textShadow(this.textShadow())
      if (this.weatherText.length > 0) {
        Text(this.weatherText)
          .fontSize(this.weatherFontSize())
          .fontColor(this.palette().textSecondary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textShadow(this.textShadow())
      }
    }
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  weatherRow() {
    Row({ space: 6 }) {
      this.weatherIconBox()
      this.weatherReadout()
    }
    .alignItems(VerticalAlign.Center)
    // 固定屏保互动已全部注释：点击天气不再触发点按特效 / 唤胶囊
    // .onClick((): void => {
    //   this.triggerForeground('weather');
    // })
  }

  @Builder
  cornerWeather() {
    Column({ space: 2 }) {
      this.weatherIconBox()
      this.weatherReadout()
    }
    .alignItems(HorizontalAlign.Center)
    // 固定屏保互动已全部注释：点击角落天气不再触发点按特效 / 唤胶囊
    // .onClick((): void => {
    //   this.triggerForeground('weather');
    // })
  }

  // ==================== 时间 / 日期 ====================

  @Builder
  timeAndDate() {
    Column({ space: 2 }) {
      Stack({ alignContent: Alignment.Center }) {
        if (this.effectKind === 'time' && this.theme !== ScreensaverGalleryTheme.Pixel) {
          this.timeRing()
        }
        Text(this.timeText)
          .fontSize(this.timeFontSize())
          .fontColor(this.palette().textPrimary)
          .fontFamily(this.palette().fontFamily)
          .fontWeight(this.palette().fontWeight)
          .letterSpacing(this.palette().letterSpacing)
          .lineHeight(this.timeFontSize() * 1.05)
          .maxLines(1)
          .textShadow(this.textShadow())
          .rotate({ x: 1, y: 0, z: 0, angle: this.pixelTimeAngle() })
      }
      .width(this.timeFontSize() * 3.4)

      Text(this.dateText)
        .fontSize(this.dateFontSize())
        .fontColor(this.dateColor())
        .fontFamily(this.palette().fontFamily)
        .maxLines(1)
        .textShadow(this.textShadow())
        .padding({ left: 6, right: 6, top: 2, bottom: 2 })
        .borderRadius(4)
        .backgroundColor(this.dateHighlight())

      if (this.theme === ScreensaverGalleryTheme.Pixel) {
        this.pixelStatusBars()
      }
    }
    .alignItems(this.layout().center ? HorizontalAlign.Center : HorizontalAlign.Start)
    // 固定屏保互动已全部注释：点击时间/日期不再触发点按特效 / 唤胶囊
    // .onClick((): void => {
    //   this.triggerForeground('time');
    // })
    .hitTestBehavior(HitTestMode.Default)
  }

  @Builder
  textOverlay() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column({ space: 2 }) {
        this.timeAndDate()
        if (!this.layout().weatherInCorner) {
          Column() {
            this.weatherRow()
          }
          .margin({ top: this.timeFontSize() * 0.02 })
        }
      }
      .width('100%')
      .alignItems(this.layout().center ? HorizontalAlign.Center : HorizontalAlign.Start)
      .padding({
        top: this.topPad(),
        left: this.layout().center ? 0 : this.leftPad(),
        right: 0
      })
      .hitTestBehavior(HitTestMode.Transparent)

      if (this.layout().weatherInCorner) {
        Row() {
          this.cornerWeather()
        }
        .width('100%')
        .justifyContent(FlexAlign.End)
        .padding({ right: this.widthVp * 0.045 })
        .position({ x: 0, y: this.topPad() })
        .hitTestBehavior(HitTestMode.Transparent)
      }
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.Transparent)
  }

  // ==================== 背景 / 植物 ====================

  @Builder
  plantGlassReflection() {
    Row()
      .width(this.widthVp * 0.30)
      .height(this.heightVp * 0.92)
      .backgroundColor('#4DFFFFFF')
      .blur(26)
      .rotate({ angle: -22 })
      .position({
        x: this.widthVp * 0.62 + this.effectProgress * this.widthVp * 0.10,
        y: -this.heightVp * 0.16
      })
      .opacity(this.effectKind === 'background' ? this.effectWave() * 0.55 : 0)
      .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  leafTouch() {
    Stack({ alignContent: Alignment.Center }) {
      Circle()
        .width(this.widthVp * 0.22)
        .height(this.widthVp * 0.22)
        .fill(this.palette().accent)
        .opacity(this.effectKind === 'leaf' ? this.effectWave() * 0.26 : 0)
        .scale({
          x: 0.6 + this.effectProgress * 0.8,
          y: 0.6 + this.effectProgress * 0.8
        })
      Row()
        .width(this.widthVp * 0.28)
        .height(this.widthVp * 0.075)
        .borderRadius(this.widthVp * 0.04)
        .backgroundColor('#33FFD27E')
        .rotate({ angle: -18 + this.effectWave() * 6 })
        .opacity(this.effectKind === 'leaf' ? this.effectWave() : 0)
    }
    .width(this.widthVp * (this.isLandscape() ? 0.30 : 0.34))
    .height(this.heightVp * 0.26)
    .position({
      x: this.widthVp * 0.02,
      y: this.heightVp * (this.isLandscape() ? 0.42 : 0.30)
    })
    .rotate({ angle: this.isLandscape() ? -10 : -8 })
    // 固定屏保互动已全部注释：点击叶片不再触发点按特效 / 唤胶囊
    // .onClick((): void => {
    //   this.triggerForeground('leaf');
    // })
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Stack() {
        Image(this.galleryBackground())
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Fill)
          .interpolation(ImageInterpolation.High)
      }
      .width(this.widthVp * 1.04)
      .height(this.heightVp * 1.04)
      .translate({
        x: -this.widthVp * 0.02 + this.backgroundShiftX(),
        y: -this.heightVp * 0.02 + this.backgroundShiftY()
      })
      // 固定屏保互动已全部注释：点击背景不再触发背景点按特效 / 唤胶囊
      // .onClick((): void => {
      //   this.onBackgroundTap();
      // })

      if (this.theme === ScreensaverGalleryTheme.Greenhouse) {
        this.plantGlassReflection()
        this.leafTouch()
      }

      this.textOverlay()
    }
    .width(this.widthVp)
    .height(this.heightVp)
    .clip(true)
  }
}
