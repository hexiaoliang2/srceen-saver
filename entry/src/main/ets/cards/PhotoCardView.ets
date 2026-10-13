import { image } from '@kit.ImageKit';
import { ScreenSaverLogger } from '../common/Logger';
import { screenSaverDarkenHex, screenSaverImageLoader, screenSaverVpToPx } from '../common/ImageLoader';
import { screenSaverTicker } from '../common/Ticker';
import { screenSaverNetProbe } from '../common/NetProbe';
import { screenSaverMediaAccess, screenSaverPhotoAccessFlag } from '../common/MediaAccess';
import { screenSaverMotionDuration, SCREEN_SAVER_MOTION_PHOTO_FADE_MS } from '../common/Motion';
import {
  SCREEN_SAVER_PHOTO_MIN_INTERVAL_SEC,
  SCREEN_SAVER_PHOTO_RECENT_DEDUP,
  ScreensaverCardInstance,
  ScreensaverCardMode
} from '../model/ConfigModels';

const SCREEN_SAVER_REFIT_DEBOUNCE_MS: number = 300;
const SCREEN_SAVER_DEFERRED_RELEASE_MS: number = 100;
const SCREEN_SAVER_PLACEHOLDER_NEUTRAL: string = '#1A1A1E';
const SCREEN_SAVER_PLACEHOLDER_DARKEN: number = 0.45;

@ComponentV2
export struct ScreensaverPhotoCard {
  @Param card: ScreensaverCardInstance = new ScreensaverCardInstance();
  @Param cardMode: ScreensaverCardMode = 'play';
  @Param cardActive: boolean = true;
  @Param manualAdvanceSeed: number = 0;

  @Local currentPixel: image.PixelMap | undefined = undefined;
  @Local incomingPixel: image.PixelMap | undefined = undefined;
  @Local fadeOpacity: number = 0;
  @Local placeholderVisible: boolean = true;
  @Local placeholderColor: string = SCREEN_SAVER_PLACEHOLDER_NEUTRAL;
  @Local infoText: string = '';
  @Local deniedVisible: boolean = false;
  @Local emptyVisible: boolean = false;

  private playList: string[] = [];
  private excludedUris: string[] = [];
  private recentUris: string[] = [];
  private cursor: number = 0;
  private generation: number = 0;
  private intervalTimer: number = -1;
  private refitTimer: number = -1;
  private retiringMap: image.PixelMap | undefined = undefined;
  private cardW: number = 0;
  private cardH: number = 0;
  private started: boolean = false;

  aboutToAppear(): void {
    this.buildPlayList();
    this.syncEmptyStates();
  }

  aboutToDisappear(): void {
    this.generation++;
    this.stopTimer();
    this.stopRefitTimer();
    this.releaseMapDeferred(this.currentPixel);
    this.releaseMapDeferred(this.incomingPixel);
    this.releaseMapDeferred(this.retiringMap);
    this.currentPixel = undefined;
    this.incomingPixel = undefined;
    this.retiringMap = undefined;
  }

  @Monitor('card.photo.uris')
  onUrisChanged(): void {
    this.excludedUris = [];
    this.recentUris = [];
    this.syncEmptyStates();
    this.restartPipeline();
  }

  @Monitor('card.photo.order')
  onOrderChanged(): void {
    this.recentUris = [];
    this.restartPipeline();
  }

  @Monitor('card.photo.intervalSec')
  onIntervalChanged(): void {
    this.restartTimer();
  }

  @Monitor('card.photo.showInfo')
  onInfoChanged(): void {
    this.updateInfoText();
  }

  @Monitor('cardActive', 'cardMode')
  onActivityChanged(): void {
    if (this.cardMode === 'play' && this.cardActive) {
      this.restartTimer();
    } else {
      this.stopTimer();
    }
  }

  @Monitor('manualAdvanceSeed')
  onManualAdvance(): void {
    if (this.cardMode !== 'edit' || this.playList.length <= 1 || !this.started) {
      return;
    }
    void this.advanceNow();
  }

  private async advanceNow(): Promise<void> {
    const targetPixel = this.incomingPixel;
    const targetIndex = this.pendingNextIndex;
    if (targetPixel !== undefined && targetIndex >= 0) {
      this.retiringMap = this.currentPixel;
      this.pendingNextIndex = -1;
      this.completeFade(targetPixel, targetIndex);
      this.releaseMapDeferred(this.retiringMap);
      this.retiringMap = undefined;
      return;
    }
    this.cursor = this.pickNextIndex();
    const gen = this.generation;
    await this.loadCurrent(gen, 0);
  }

  private syncEmptyStates(): void {
    const hasUris = this.card.photo.uris.length > 0;
    this.deniedVisible = !hasUris && this.card.photo.sourceAlbum !== 'all' && screenSaverPhotoAccessFlag.albumDenied;
    this.emptyVisible = !hasUris && !this.deniedVisible;
  }

  private buildPlayList(): void {
    const uris = this.card.photo.uris;
    const list: string[] = [];
    for (const uri of uris) {
      if (uri.length > 0) {
        list.push(uri);
      }
    }
    if (this.card.photo.order === 'shuffle' && this.cardMode === 'play') {
      this.playList = list;
    } else {
      this.playList = list;
    }
    if (this.cursor >= this.playList.length) {
      this.cursor = 0;
    }
  }

  private pickNextIndex(): number {
    if (this.playList.length === 0) {
      return -1;
    }
    if (this.card.photo.order !== 'shuffle' || this.cardMode !== 'play') {
      this.cursor = (this.cursor + 1) % this.playList.length;
      return this.cursor;
    }
    if (this.recentUris.length >= SCREEN_SAVER_PHOTO_RECENT_DEDUP) {
      this.recentUris.shift();
    }
    const candidates: number[] = [];
    for (let index = 0; index < this.playList.length; index++) {
      const uri = this.playList[index];
      if (uri === this.playList[this.cursor] && this.playList.length > 1) {
        continue;
      }
      if (this.recentUris.indexOf(uri) < 0) {
        candidates.push(index);
      }
    }
    if (candidates.length === 0) {
      this.recentUris = [];
      for (let index = 0; index < this.playList.length; index++) {
        if (index !== this.cursor) {
          candidates.push(index);
        }
      }
      if (candidates.length === 0) {
        return this.cursor;
      }
    }
    const pick = candidates[Math.floor(Math.random() * candidates.length)];
    this.cursor = pick;
    return pick;
  }

  private noteRecent(uri: string): void {
    if (this.recentUris.indexOf(uri) >= 0) {
      return;
    }
    this.recentUris.push(uri);
    if (this.recentUris.length > SCREEN_SAVER_PHOTO_RECENT_DEDUP) {
      this.recentUris.shift();
    }
  }

  private restartPipeline(): void {
    this.generation++;
    this.stopTimer();
    this.stopRefitTimer();
    this.releaseIncoming();
    this.fadeOpacity = 0;
    this.buildPlayList();
    if (this.playList.length === 0) {
      const retire = this.currentPixel;
      this.currentPixel = undefined;
      this.releaseMapDeferred(retire);
      this.placeholderVisible = true;
      return;
    }
    if (this.started) {
      this.beginPlayback();
    } else {
      this.placeholderVisible = true;
    }
  }

  private beginPlayback(): void {
    this.generation++;
    const gen = this.generation;
    this.stopTimer();
    this.releaseIncoming();
    this.cursor = 0;
    this.placeholderVisible = false;
    void this.loadCurrent(gen, 0);
    this.restartTimer();
  }

  private async loadCurrent(gen: number, attempt: number): Promise<void> {
    if (this.playList.length === 0) {
      return;
    }
    if (attempt >= this.playList.length) {
      const retire = this.currentPixel;
      this.currentPixel = undefined;
      this.releaseMapDeferred(retire);
      this.placeholderVisible = true;
      return;
    }
    const uri = this.playList[this.cursor];
    const map = await this.decodeUri(uri);
    if (gen !== this.generation) {
      this.releaseMap(map);
      return;
    }
    if (map === undefined) {
      this.noteBroken(uri);
      const nextIndex = this.pickNextIndex();
      if (nextIndex < 0 || nextIndex === this.cursor) {
        this.placeholderVisible = true;
        return;
      }
      void this.loadCurrent(gen, attempt + 1);
      return;
    }
    const retire = this.currentPixel;
    this.currentPixel = map;
    this.releaseMapDeferred(retire);
    this.fadeOpacity = 0;
    this.placeholderVisible = false;
    this.noteRecent(uri);
    this.updateInfoText();
    void this.preloadNext(0);
  }

  private async advance(): Promise<void> {
    if (!this.cardActive || !screenSaverTicker.isActive()) {
      return;
    }
    if (this.playList.length <= 1) {
      return;
    }
    const targetPixel = this.incomingPixel;
    const targetIndex = this.pendingNextIndex;
    if (targetPixel === undefined || targetIndex < 0) {
      this.cursor = this.pickNextIndex();
      const gen = this.generation;
      void this.loadCurrent(gen, 0);
      return;
    }
    this.retiringMap = this.currentPixel;
    this.pendingNextIndex = -1;
    const gen = this.generation;
    const fadeMs = screenSaverMotionDuration(SCREEN_SAVER_MOTION_PHOTO_FADE_MS);
    if (fadeMs <= 0) {
      this.completeFade(targetPixel, targetIndex);
      this.releaseMapDeferred(this.retiringMap);
      this.retiringMap = undefined;
      return;
    }
    this.getUIContext().animateTo({
      duration: fadeMs,
      curve: Curve.EaseInOut,
      onFinish: (): void => {
        if (gen !== this.generation) {
          return;
        }
        this.completeFade(targetPixel, targetIndex);
      }
    }, (): void => {
      this.fadeOpacity = 1;
    });
  }

  private pendingNextIndex: number = -1;

  private async preloadNext(attempt: number): Promise<void> {
    if (this.playList.length <= 1 || attempt >= this.playList.length) {
      return;
    }
    if (this.card.photo.wifiOnlyPrefetch) {
      const metered = await screenSaverNetProbe.isMetered();
      if (metered) {
        return;
      }
    }
    const gen = this.generation;
    const index = this.pickNextIndex();
    if (index < 0) {
      return;
    }
    const uri = this.playList[index];
    const map = await this.decodeUri(uri);
    if (gen !== this.generation) {
      this.releaseMap(map);
      return;
    }
    if (map === undefined) {
      this.noteBroken(uri);
      void this.preloadNext(attempt + 1);
      return;
    }
    const retire = this.incomingPixel;
    this.incomingPixel = map;
    this.pendingNextIndex = index;
    this.releaseMapDeferred(retire);
  }

  private completeFade(targetPixel: image.PixelMap, targetIndex: number): void {
    const retire = this.retiringMap;
    this.retiringMap = undefined;
    this.currentPixel = targetPixel;
    this.cursor = targetIndex;
    this.incomingPixel = undefined;
    this.fadeOpacity = 0;
    this.releaseMapDeferred(retire);
    this.noteRecent(this.playList[targetIndex]);
    this.updateInfoText();
    void this.preloadNext(0);
  }

  private updateInfoText(): void {
    if (!this.card.photo.showInfo || this.playList.length === 0) {
      this.infoText = '';
      return;
    }
    const uri = this.playList[this.cursor];
    const taken = this.formatTakenDate(uri);
    if (taken.length > 0) {
      this.infoText = taken;
      return;
    }
    const slash = uri.lastIndexOf('/');
    const name = slash >= 0 ? uri.substring(slash + 1) : uri;
    this.infoText = name.length > 40 ? `${name.substring(0, 40)}…` : name;
  }

  private formatTakenDate(uri: string): string {
    const raw = this.card.photo.uriDates[uri];
    if (raw === undefined || raw.length === 0) {
      return '';
    }
    const value = Number(raw);
    if (!Number.isFinite(value) || value <= 0) {
      return '';
    }
    const ms = value < 10000000000 ? value * 1000 : value;
    const date = new Date(ms);
    const time = date.getTime();
    if (!Number.isFinite(time) || time <= 0) {
      return '';
    }
    return `${date.getFullYear()}/${date.getMonth() + 1}/${date.getDate()}`;
  }

  private scheduleRefit(): void {
    this.stopRefitTimer();
    this.refitTimer = setTimeout((): void => {
      this.refitTimer = -1;
      this.refitCurrent();
    }, SCREEN_SAVER_REFIT_DEBOUNCE_MS);
  }

  private refitCurrent(): void {
    if (this.playList.length === 0 || !this.started) {
      return;
    }
    this.generation++;
    const gen = this.generation;
    this.releaseIncoming();
    void this.reloadCurrent(gen);
  }

  private async reloadCurrent(gen: number): Promise<void> {
    const uri = this.playList[this.cursor];
    const map = await this.decodeUri(uri);
    if (gen !== this.generation) {
      this.releaseMap(map);
      return;
    }
    if (map === undefined) {
      return;
    }
    const retire = this.currentPixel;
    this.currentPixel = map;
    this.releaseMapDeferred(retire);
    this.placeholderVisible = false;
    void this.preloadNext(0);
  }

  private async decodeUri(uri: string): Promise<image.PixelMap | undefined> {
    if (this.excludedUris.indexOf(uri) >= 0) {
      return undefined;
    }
    const map = await screenSaverImageLoader.decodeForRegion(uri, this.targetWidthPx(), this.targetHeightPx());
    if (map !== undefined) {
      const avg = await screenSaverImageLoader.extractMainColor(map);
      if (avg !== undefined) {
        this.placeholderColor = screenSaverDarkenHex(avg, SCREEN_SAVER_PLACEHOLDER_DARKEN);
      }
    }
    return map;
  }

  private targetWidthPx(): number {
    const width = this.cardW > 0 ? this.cardW : 320;
    return screenSaverVpToPx(width);
  }

  private targetHeightPx(): number {
    const height = this.cardH > 0 ? this.cardH : 480;
    return screenSaverVpToPx(height);
  }

  private noteBroken(uri: string): void {
    if (this.excludedUris.indexOf(uri) < 0) {
      this.excludedUris.push(uri);
      ScreenSaverLogger.warn(`skip broken photo: ${uri}`);
    }
  }

  private restartTimer(): void {
    this.stopTimer();
    if (!this.started || this.playList.length <= 1) {
      return;
    }
    if (this.cardMode !== 'play' || !this.cardActive) {
      return;
    }
    if (this.card.photo.intervalSec <= 0) {
      return;
    }
    const intervalMs = Math.max(SCREEN_SAVER_PHOTO_MIN_INTERVAL_SEC, this.card.photo.intervalSec) * 1000;
    this.intervalTimer = setInterval((): void => {
      void this.advance();
    }, intervalMs);
  }

  private stopTimer(): void {
    if (this.intervalTimer >= 0) {
      clearInterval(this.intervalTimer);
      this.intervalTimer = -1;
    }
  }

  private stopRefitTimer(): void {
    if (this.refitTimer >= 0) {
      clearTimeout(this.refitTimer);
      this.refitTimer = -1;
    }
  }

  private releaseIncoming(): void {
    const map = this.incomingPixel;
    this.incomingPixel = undefined;
    this.pendingNextIndex = -1;
    this.releaseMapDeferred(map);
  }

  private releaseMap(map: image.PixelMap | undefined): void {
    if (map === undefined) {
      return;
    }
    try {
      map.release();
    } catch (err) {
      const error = err as Error;
      ScreenSaverLogger.warn(`pixelmap release failed: ${error.message}`);
    }
  }

  private releaseMapDeferred(map: image.PixelMap | undefined): void {
    if (map === undefined) {
      return;
    }
    setTimeout((): void => {
      this.releaseMap(map);
    }, SCREEN_SAVER_DEFERRED_RELEASE_MS);
  }

  private async openPermissionSetting(): Promise<void> {
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      return;
    }
    await screenSaverMediaAccess.openPermissionSetting(context);
  }

  build() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.placeholderColor)
      if (this.currentPixel !== undefined) {
        Image(this.currentPixel)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
      }
      if (this.incomingPixel !== undefined) {
        Image(this.incomingPixel)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .opacity(this.fadeOpacity)
      }
      if (this.placeholderVisible && !this.deniedVisible && !this.emptyVisible) {
        Text('加载中…')
          .fontSize(12)
          .fontColor('#8C8C8C')
      }
      if (this.emptyVisible) {
        Column({ space: 4 }) {
          Text('还没有照片')
            .fontSize(13)
            .fontColor('#B3B3B3')
          Text('在配置中选择相册来源')
            .fontSize(11)
            .fontColor('#6E6E73')
        }
      }
      if (this.deniedVisible) {
        Column({ space: 6 }) {
          Text('无相册访问权限')
            .fontSize(13)
            .fontColor('#B3B3B3')
          if (this.cardMode === 'edit') {
            Column() {
              Text('去开启')
                .fontSize(12)
                .fontColor('#4A9EFF')
            }
            .constraintSize({ minWidth: 40, minHeight: 40 })
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
            .borderRadius(6)
            .backgroundColor('#26262B')
            .onClick((): void => {
              void this.openPermissionSetting();
            })
          }
        }
      }
      if (this.infoText.length > 0) {
        Row() {
          Text(this.infoText)
            .fontSize(10)
            .fontColor('#D0D0D0')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')
        .padding({ left: 8, right: 8, top: 4, bottom: 4 })
        .backgroundColor('#66000000')
        .align(Alignment.BottomStart)
      }
    }
    .width('100%')
    .height('100%')
    .clip(true)
    .onAreaChange((oldArea: Area, newArea: Area): void => {
      const width = typeof newArea.width === 'number' ? newArea.width : 0;
      const height = typeof newArea.height === 'number' ? newArea.height : 0;
      if (width <= 0 || height <= 0) {
        return;
      }
      const sizeChanged = Math.abs(width - this.cardW) > 1 || Math.abs(height - this.cardH) > 1;
      this.cardW = width;
      this.cardH = height;
      if (!this.started) {
        this.started = true;
        if (this.playList.length > 0) {
          this.beginPlayback();
        }
      } else if (sizeChanged && this.playList.length > 0) {
        this.scheduleRefit();
      }
      this.syncEmptyStates();
    })
  }
}
