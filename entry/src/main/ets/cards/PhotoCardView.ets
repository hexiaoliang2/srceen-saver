import { image } from '@kit.ImageKit';
import { ScreenSaverLogger } from '../common/Logger';
import { screenSaverDarkenHex, screenSaverImageLoader, screenSaverVpToPx } from '../common/ImageLoader';
import { screenSaverTicker } from '../common/Ticker';
import { screenSaverAppModel } from '../model/AppModel';
import {
  SCREEN_SAVER_AMBIENT_DARKEN_FACTOR,
  ScreenSaverCardInstance,
  ScreenSaverCardMode
} from '../model/ConfigModels';

const SCREEN_SAVER_FADE_DURATION_MS: number = 400;
const SCREEN_SAVER_REFIT_DEBOUNCE_MS: number = 300;
const SCREEN_SAVER_DEFERRED_RELEASE_MS: number = 100;

@ComponentV2
export struct ScreenSaverPhotoCard {
  @Param card: ScreenSaverCardInstance = new ScreenSaverCardInstance();
  @Param cardMode: ScreenSaverCardMode = 'play';
  @Param pageIndex: number = 0;
  @Param cardActive: boolean = true;

  @Local currentPixel: image.PixelMap | undefined = undefined;
  @Local incomingPixel: image.PixelMap | undefined = undefined;
  @Local fadeOpacity: number = 0;
  @Local placeholderVisible: boolean = true;

  private playList: string[] = [];
  private excludedUris: string[] = [];
  private currentIndex: number = 0;
  private nextIndex: number = -1;
  private generation: number = 0;
  private intervalTimer: number = -1;
  private refitTimer: number = -1;
  private retiringMap: image.PixelMap | undefined = undefined;
  private cardW: number = 0;
  private cardH: number = 0;
  private started: boolean = false;

  aboutToAppear(): void {
    this.buildPlayList();
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
    this.restartPipeline();
  }

  @Monitor('card.photo.shuffle')
  onShuffleChanged(): void {
    this.restartPipeline();
  }

  @Monitor('card.photo.intervalSec')
  onIntervalChanged(): void {
    this.restartTimer();
  }

  private buildPlayList(): void {
    const uris = this.card.photo.uris;
    const list: string[] = [];
    for (const uri of uris) {
      if (uri.length > 0) {
        list.push(uri);
      }
    }
    const useShuffle = this.card.photo.shuffle && this.cardMode === 'play';
    if (useShuffle) {
      for (let i = list.length - 1; i > 0; i--) {
        const j = Math.floor(Math.random() * (i + 1));
        const temp = list[i];
        list[i] = list[j];
        list[j] = temp;
      }
    }
    this.playList = list;
  }

  private restartPipeline(): void {
    this.generation++;
    this.stopTimer();
    this.stopRefitTimer();
    this.releaseIncoming();
    this.fadeOpacity = 0;
    this.buildPlayList();
    if (this.playList.length === 0) {
      this.nextIndex = -1;
      this.currentIndex = 0;
      const retire = this.currentPixel;
      this.currentPixel = undefined;
      this.releaseMapDeferred(retire);
      this.placeholderVisible = true;
      screenSaverAppModel.resetAmbientColorIfNoDriver(this.pageIndex);
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
    this.currentIndex = 0;
    this.nextIndex = -1;
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
      screenSaverAppModel.resetAmbientColorIfNoDriver(this.pageIndex);
      return;
    }
    const uri = this.playList[this.currentIndex];
    const map = await this.decodeUri(uri);
    if (gen !== this.generation) {
      this.releaseMap(map);
      return;
    }
    if (map === undefined) {
      this.noteBroken(uri);
      this.currentIndex = (this.currentIndex + 1) % this.playList.length;
      void this.loadCurrent(gen, attempt + 1);
      return;
    }
    const retire = this.currentPixel;
    this.currentPixel = map;
    this.releaseMapDeferred(retire);
    this.fadeOpacity = 0;
    this.placeholderVisible = false;
    this.publishAmbient(map);
    void this.preloadNext(0);
  }

  private async preloadNext(attempt: number): Promise<void> {
    if (this.playList.length <= 1 || attempt >= this.playList.length) {
      return;
    }
    const gen = this.generation;
    const idx = (this.currentIndex + 1 + attempt) % this.playList.length;
    if (idx === this.currentIndex) {
      return;
    }
    const uri = this.playList[idx];
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
    this.nextIndex = idx;
    this.releaseMapDeferred(retire);
  }

  private advance(): void {
    if (!this.cardActive || !screenSaverTicker.isActive()) {
      return;
    }
    if (this.playList.length <= 1) {
      return;
    }
    const targetPixel = this.incomingPixel;
    const targetIndex = this.nextIndex;
    if (targetPixel === undefined || targetIndex < 0) {
      void this.preloadNext(0);
      return;
    }
    this.retiringMap = this.currentPixel;
    this.nextIndex = -1;
    const gen = this.generation;
    this.getUIContext().animateTo({
      duration: SCREEN_SAVER_FADE_DURATION_MS,
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

  private completeFade(targetPixel: image.PixelMap, targetIndex: number): void {
    const retire = this.retiringMap;
    this.retiringMap = undefined;
    this.currentPixel = targetPixel;
    this.currentIndex = targetIndex;
    this.incomingPixel = undefined;
    this.fadeOpacity = 0;
    this.releaseMapDeferred(retire);
    this.publishAmbient(targetPixel);
    void this.preloadNext(0);
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
    const uri = this.playList[this.currentIndex];
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
    this.publishAmbient(map);
    void this.preloadNext(0);
  }

  private async decodeUri(uri: string): Promise<image.PixelMap | undefined> {
    if (this.excludedUris.indexOf(uri) >= 0) {
      return undefined;
    }
    return await screenSaverImageLoader.decodeForRegion(uri, this.targetWidthPx(), this.targetHeightPx());
  }

  private targetWidthPx(): number {
    const width = this.cardW > 0 ? this.cardW : 320;
    return screenSaverVpToPx(width);
  }

  private targetHeightPx(): number {
    const height = this.cardH > 0 ? this.cardH : 480;
    return screenSaverVpToPx(height);
  }

  private publishAmbient(map: image.PixelMap): void {
    const pageIndex = this.pageIndex;
    const cardId = this.card.id;
    void this.publishAmbientAsync(map, pageIndex, cardId);
  }

  private async publishAmbientAsync(map: image.PixelMap, pageIndex: number, cardId: string): Promise<void> {
    const hex = await screenSaverImageLoader.extractMainColor(map);
    if (hex === undefined) {
      return;
    }
    const darkened = screenSaverDarkenHex(hex, SCREEN_SAVER_AMBIENT_DARKEN_FACTOR);
    screenSaverAppModel.setAmbientColor(pageIndex, cardId, darkened);
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
    const intervalMs = Math.max(5, this.card.photo.intervalSec) * 1000;
    this.intervalTimer = setInterval((): void => {
      this.advance();
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
    this.nextIndex = -1;
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

  build() {
    Stack() {
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
      if (this.placeholderVisible) {
        Column() {
          Text(this.cardMode === 'edit' ? '未选择照片' : '相册待设置')
            .fontSize(13)
            .fontColor('#5A5A5A')
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#0A0A0A')
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
    })
  }
}
