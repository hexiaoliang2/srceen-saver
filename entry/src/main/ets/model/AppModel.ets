import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { ScreenSaverLogger } from '../common/Logger';
import {
  SCREEN_SAVER_GRID_COLS,
  SCREEN_SAVER_GRID_ROWS,
  SCREEN_SAVER_MAX_PAGES,
  ScreenSaverAppConfig,
  ScreenSaverCardInstance,
  ScreenSaverCardType,
  ScreenSaverGridSlot,
  ScreenSaverPageConfig,
  ScreenSaverRawCard,
  ScreenSaverRawClock,
  ScreenSaverRawConfig,
  ScreenSaverRawPage,
  ScreenSaverRawPhoto,
  ScreenSaverRawSettings
} from './ConfigModels';

const SCREEN_SAVER_STORE_NAME: string = 'screen_saver_store';
const SCREEN_SAVER_STORE_KEY: string = 'screen_saver_config';
const SCREEN_SAVER_SAVE_DEBOUNCE_MS: number = 200;
const SCREEN_SAVER_DEFAULT_AMBIENT: string = '#000000';

function screenSaverGenerateId(prefix: string): string {
  const randomPart: number = Math.floor(Math.random() * 1000000);
  return `${prefix}_${Date.now().toString(36)}_${randomPart.toString(36)}`;
}

function screenSaverClampInt(value: number, min: number, max: number): number {
  const rounded: number = Math.round(value);
  if (rounded < min) {
    return min;
  }
  if (rounded > max) {
    return max;
  }
  return rounded;
}

function screenSaverClampNumber(value: number, min: number, max: number): number {
  if (value < min) {
    return min;
  }
  if (value > max) {
    return max;
  }
  return value;
}

export class ScreenSaverAppModel {
  readonly appConfig: ScreenSaverAppConfig = new ScreenSaverAppConfig();
  private abilityContext: common.UIAbilityContext | undefined = undefined;
  private store: preferences.Preferences | undefined = undefined;
  private saveTimer: number = -1;
  private loaded: boolean = false;

  attachContext(context: common.UIAbilityContext): void {
    this.abilityContext = context;
  }

  async load(): Promise<void> {
    const context = this.abilityContext;
    if (context === undefined) {
      ScreenSaverLogger.warn('load skipped: ability context is not attached');
      return;
    }
    try {
      const store = await this.ensureStore();
      if (store === undefined) {
        this.createFirstRunConfig();
        return;
      }
      const storedText = await store.get(SCREEN_SAVER_STORE_KEY, '');
      if (typeof storedText === 'string' && storedText.length > 0) {
        try {
          const raw = JSON.parse(storedText) as ScreenSaverRawConfig;
          this.applyRaw(raw);
        } catch (parseError) {
          const error = parseError as Error;
          ScreenSaverLogger.error(`config parse failed, fallback to first run: ${error.message}`);
          this.createFirstRunConfig();
        }
      } else {
        this.createFirstRunConfig();
      }
      this.loaded = true;
    } catch (err) {
      const error = err as Error;
      ScreenSaverLogger.error(`config load failed: ${error.message}`);
      this.createFirstRunConfig();
      this.loaded = true;
    }
  }

  save(): void {
    if (this.saveTimer >= 0) {
      clearTimeout(this.saveTimer);
    }
    this.saveTimer = setTimeout((): void => {
      this.saveTimer = -1;
      void this.persistNow();
    }, SCREEN_SAVER_SAVE_DEBOUNCE_MS);
  }

  pageSummary(page: ScreenSaverPageConfig): string {
    if (page.cards.length === 0) {
      return '空页面';
    }
    let clockCount: number = 0;
    let photoCount: number = 0;
    for (const card of page.cards) {
      if (card.cardType === 'clock') {
        clockCount++;
      } else {
        photoCount++;
      }
    }
    const parts: string[] = [];
    if (clockCount > 0) {
      parts.push(`时钟 ×${clockCount}`);
    }
    if (photoCount > 0) {
      parts.push(`相册 ×${photoCount}`);
    }
    return parts.join(' · ');
  }

  addPage(): boolean {
    if (this.appConfig.pages.length >= SCREEN_SAVER_MAX_PAGES) {
      return false;
    }
    const page = new ScreenSaverPageConfig();
    page.id = screenSaverGenerateId('page');
    page.name = this.nextPageName();
    this.appConfig.pages.push(page);
    this.save();
    return true;
  }

  private nextPageName(): string {
    const prefix = '屏保页 ';
    let maxNumber = 0;
    for (const page of this.appConfig.pages) {
      if (page.name.startsWith(prefix)) {
        const suffix = page.name.substring(prefix.length);
        const value = parseInt(suffix, 10);
        if (!Number.isNaN(value) && value > maxNumber) {
          maxNumber = value;
        }
      }
    }
    return `${prefix}${maxNumber + 1}`;
  }

  removePage(pageId: string): void {
    const index = this.appConfig.pages.findIndex((page: ScreenSaverPageConfig): boolean => page.id === pageId);
    if (index >= 0) {
      this.appConfig.pages.splice(index, 1);
      this.save();
    }
  }

  addCard(pageIndex: number, cardType: ScreenSaverCardType, colSpan: number, rowSpan: number): boolean {
    const page = this.appConfig.pages[pageIndex];
    if (page === undefined) {
      return false;
    }
    const spanCols = screenSaverClampInt(colSpan, 1, SCREEN_SAVER_GRID_COLS);
    const spanRows = screenSaverClampInt(rowSpan, 1, SCREEN_SAVER_GRID_ROWS);
    const slot = this.findFreeSlot(page.cards, spanCols, spanRows);
    if (slot === undefined) {
      return false;
    }
    const card = new ScreenSaverCardInstance();
    card.id = screenSaverGenerateId('card');
    card.cardType = cardType;
    card.colStart = slot.colStart;
    card.rowStart = slot.rowStart;
    card.colSpan = spanCols;
    card.rowSpan = spanRows;
    page.cards.push(card);
    this.save();
    return true;
  }

  removeCard(pageIndex: number, cardId: string): void {
    const page = this.appConfig.pages[pageIndex];
    if (page === undefined) {
      return;
    }
    const index = page.cards.findIndex((card: ScreenSaverCardInstance): boolean => card.id === cardId);
    if (index >= 0) {
      page.cards.splice(index, 1);
      this.resetAmbientColorIfNoDriver(pageIndex);
      this.save();
    }
  }

  moveCard(pageIndex: number, cardId: string, deltaCol: number, deltaRow: number): boolean {
    const page = this.appConfig.pages[pageIndex];
    if (page === undefined) {
      return false;
    }
    const card = page.cards.find((item: ScreenSaverCardInstance): boolean => item.id === cardId);
    if (card === undefined) {
      return false;
    }
    const nextCol = screenSaverClampInt(card.colStart + deltaCol, 0, SCREEN_SAVER_GRID_COLS - card.colSpan);
    const nextRow = screenSaverClampInt(card.rowStart + deltaRow, 0, SCREEN_SAVER_GRID_ROWS - card.rowSpan);
    if (nextCol === card.colStart && nextRow === card.rowStart) {
      return false;
    }
    const placeable = this.canPlaceInCards(page.cards, cardId, nextCol, nextRow, card.colSpan, card.rowSpan);
    if (!placeable) {
      return false;
    }
    card.colStart = nextCol;
    card.rowStart = nextRow;
    this.save();
    return true;
  }

  resizeCard(pageIndex: number, cardId: string, deltaColSpan: number, deltaRowSpan: number): boolean {
    const page = this.appConfig.pages[pageIndex];
    if (page === undefined) {
      return false;
    }
    const card = page.cards.find((item: ScreenSaverCardInstance): boolean => item.id === cardId);
    if (card === undefined) {
      return false;
    }
    return this.resizeCardTo(pageIndex, cardId, card.colSpan + deltaColSpan, card.rowSpan + deltaRowSpan);
  }

  resizeCardTo(pageIndex: number, cardId: string, colSpan: number, rowSpan: number): boolean {
    const page = this.appConfig.pages[pageIndex];
    if (page === undefined) {
      return false;
    }
    const card = page.cards.find((item: ScreenSaverCardInstance): boolean => item.id === cardId);
    if (card === undefined) {
      return false;
    }
    const nextColSpan = screenSaverClampInt(colSpan, 1, SCREEN_SAVER_GRID_COLS);
    const nextRowSpan = screenSaverClampInt(rowSpan, 1, SCREEN_SAVER_GRID_ROWS);
    if (nextColSpan === card.colSpan && nextRowSpan === card.rowSpan) {
      return false;
    }
    const nextColStart = Math.min(card.colStart, SCREEN_SAVER_GRID_COLS - nextColSpan);
    const nextRowStart = Math.min(card.rowStart, SCREEN_SAVER_GRID_ROWS - nextRowSpan);
    const placeable = this.canPlaceInCards(page.cards, cardId, nextColStart, nextRowStart, nextColSpan, nextRowSpan);
    if (!placeable) {
      return false;
    }
    card.colStart = nextColStart;
    card.rowStart = nextRowStart;
    card.colSpan = nextColSpan;
    card.rowSpan = nextRowSpan;
    this.save();
    return true;
  }

  pinPageToTop(pageId: string): boolean {
    const pages = this.appConfig.pages;
    const index = pages.findIndex((page: ScreenSaverPageConfig): boolean => page.id === pageId);
    if (index <= 0) {
      return false;
    }
    const page = pages[index];
    pages.splice(index, 1);
    pages.unshift(page);
    this.save();
    return true;
  }

  canPlace(pageIndex: number, cardId: string, colStart: number, rowStart: number, colSpan: number,
    rowSpan: number): boolean {
    const page = this.appConfig.pages[pageIndex];
    if (page === undefined) {
      return false;
    }
    return this.canPlaceInCards(page.cards, cardId, colStart, rowStart, colSpan, rowSpan);
  }

  canPlaceInCards(cards: ScreenSaverCardInstance[], excludeCardId: string, colStart: number, rowStart: number,
    colSpan: number, rowSpan: number): boolean {
    if (colStart < 0 || rowStart < 0 || colSpan <= 0 || rowSpan <= 0) {
      return false;
    }
    if (colStart + colSpan > SCREEN_SAVER_GRID_COLS || rowStart + rowSpan > SCREEN_SAVER_GRID_ROWS) {
      return false;
    }
    for (const card of cards) {
      if (card.id === excludeCardId) {
        continue;
      }
      const overlaps = colStart < card.colStart + card.colSpan && colStart + colSpan > card.colStart &&
        rowStart < card.rowStart + card.rowSpan && rowStart + rowSpan > card.rowStart;
      if (overlaps) {
        return false;
      }
    }
    return true;
  }

  getAmbientDriver(pageIndex: number): ScreenSaverCardInstance | undefined {
    const page = this.appConfig.pages[pageIndex];
    if (page === undefined) {
      return undefined;
    }
    let best: ScreenSaverCardInstance | undefined = undefined;
    let bestArea: number = 0;
    for (const card of page.cards) {
      if (card.cardType !== 'photo') {
        continue;
      }
      if (card.photo.uris.length === 0) {
        continue;
      }
      const area = card.colSpan * card.rowSpan;
      if (area > bestArea) {
        bestArea = area;
        best = card;
      }
    }
    return best;
  }

  setAmbientColor(pageIndex: number, cardId: string, color: string): void {
    const page = this.appConfig.pages[pageIndex];
    if (page === undefined) {
      return;
    }
    const driver = this.getAmbientDriver(pageIndex);
    if (driver === undefined || driver.id !== cardId) {
      return;
    }
    if (page.ambientColor === color) {
      return;
    }
    page.ambientColor = color;
    this.save();
  }

  resetAmbientColorIfNoDriver(pageIndex: number): void {
    const page = this.appConfig.pages[pageIndex];
    if (page === undefined) {
      return;
    }
    if (this.getAmbientDriver(pageIndex) !== undefined) {
      return;
    }
    if (page.ambientColor === SCREEN_SAVER_DEFAULT_AMBIENT) {
      return;
    }
    page.ambientColor = SCREEN_SAVER_DEFAULT_AMBIENT;
  }

  private findFreeSlot(cards: ScreenSaverCardInstance[], colSpan: number,
    rowSpan: number): ScreenSaverGridSlot | undefined {
    for (let row = 0; row <= SCREEN_SAVER_GRID_ROWS - rowSpan; row++) {
      for (let col = 0; col <= SCREEN_SAVER_GRID_COLS - colSpan; col++) {
        if (this.canPlaceInCards(cards, '', col, row, colSpan, rowSpan)) {
          const slot: ScreenSaverGridSlot = { colStart: col, rowStart: row };
          return slot;
        }
      }
    }
    return undefined;
  }

  private async ensureStore(): Promise<preferences.Preferences | undefined> {
    if (this.store !== undefined) {
      return this.store;
    }
    const context = this.abilityContext;
    if (context === undefined) {
      return undefined;
    }
    try {
      const options: preferences.Options = { name: SCREEN_SAVER_STORE_NAME };
      this.store = await preferences.getPreferences(context, options);
    } catch (err) {
      const error = err as Error;
      ScreenSaverLogger.error(`preferences open failed: ${error.message}`);
      this.store = undefined;
    }
    return this.store;
  }

  private async persistNow(): Promise<void> {
    const store = await this.ensureStore();
    if (store === undefined) {
      return;
    }
    try {
      const text = JSON.stringify(this.toRaw());
      await store.put(SCREEN_SAVER_STORE_KEY, text);
      await store.flush();
    } catch (err) {
      const error = err as Error;
      ScreenSaverLogger.error(`config save failed: ${error.message}`);
    }
  }

  private toRaw(): ScreenSaverRawConfig {
    const rawSettings: ScreenSaverRawSettings = {
      dimEnabled: this.appConfig.settings.dimEnabled,
      dimDelaySec: this.appConfig.settings.dimDelaySec,
      dimBrightness: this.appConfig.settings.dimBrightness,
      ambientColorEnabled: this.appConfig.settings.ambientColorEnabled
    };
    const rawPages: ScreenSaverRawPage[] = [];
    for (const page of this.appConfig.pages) {
      const rawCards: ScreenSaverRawCard[] = [];
      for (const card of page.cards) {
        const rawClock: ScreenSaverRawClock = {
          showSeconds: card.clock.showSeconds,
          showDate: card.clock.showDate,
          use24Hour: card.clock.use24Hour,
          fontScale: card.clock.fontScale
        };
        const rawPhoto: ScreenSaverRawPhoto = {
          uris: card.photo.uris,
          intervalSec: card.photo.intervalSec,
          shuffle: card.photo.shuffle
        };
        const rawCard: ScreenSaverRawCard = {
          id: card.id,
          cardType: card.cardType,
          colStart: card.colStart,
          rowStart: card.rowStart,
          colSpan: card.colSpan,
          rowSpan: card.rowSpan,
          clock: rawClock,
          photo: rawPhoto
        };
        rawCards.push(rawCard);
      }
      const rawPage: ScreenSaverRawPage = {
        id: page.id,
        name: page.name,
        cards: rawCards,
        ambientColor: page.ambientColor
      };
      rawPages.push(rawPage);
    }
    const rawConfig: ScreenSaverRawConfig = {
      schemaVersion: this.appConfig.schemaVersion,
      settings: rawSettings,
      pages: rawPages
    };
    return rawConfig;
  }

  private applyRaw(raw: ScreenSaverRawConfig): void {
    const rawSettings = raw.settings;
    if (rawSettings !== undefined) {
      this.appConfig.settings.dimEnabled = rawSettings.dimEnabled ?? true;
      this.appConfig.settings.dimDelaySec =
        screenSaverClampInt(rawSettings.dimDelaySec ?? 60, 5, 3600);
      this.appConfig.settings.dimBrightness =
        screenSaverClampNumber(rawSettings.dimBrightness ?? 0.25, 0.05, 1);
      this.appConfig.settings.ambientColorEnabled = rawSettings.ambientColorEnabled ?? true;
    }
    const rawPages = raw.pages ?? [];
    const pages: ScreenSaverPageConfig[] = [];
    const pageLimit = Math.min(rawPages.length, SCREEN_SAVER_MAX_PAGES);
    for (let index = 0; index < pageLimit; index++) {
      pages.push(this.buildPageFromRaw(rawPages[index], index));
    }
    this.appConfig.pages = pages;
  }

  private buildPageFromRaw(rawPage: ScreenSaverRawPage, index: number): ScreenSaverPageConfig {
    const page = new ScreenSaverPageConfig();
    page.id = (rawPage.id !== undefined && rawPage.id.length > 0) ? rawPage.id : screenSaverGenerateId('page');
    page.name = (rawPage.name !== undefined && rawPage.name.length > 0) ? rawPage.name : `屏保页 ${index + 1}`;
    const ambientColor = rawPage.ambientColor;
    page.ambientColor = (ambientColor !== undefined && ambientColor.length === 7) ?
      ambientColor : SCREEN_SAVER_DEFAULT_AMBIENT;
    const rawCards = rawPage.cards ?? [];
    const accepted: ScreenSaverCardInstance[] = [];
    for (const rawCard of rawCards) {
      const card = this.buildCardFromRaw(rawCard);
      if (card === undefined) {
        continue;
      }
      if (!this.canPlaceInCards(accepted, '', card.colStart, card.rowStart, card.colSpan, card.rowSpan)) {
        ScreenSaverLogger.warn(`drop overlapping card: ${card.id}`);
        continue;
      }
      accepted.push(card);
    }
    page.cards = accepted;
    return page;
  }

  private buildCardFromRaw(rawCard: ScreenSaverRawCard): ScreenSaverCardInstance | undefined {
    let cardType: ScreenSaverCardType | undefined = undefined;
    if (rawCard.cardType === 'clock') {
      cardType = 'clock';
    } else if (rawCard.cardType === 'photo') {
      cardType = 'photo';
    }
    if (cardType === undefined) {
      return undefined;
    }
    const card = new ScreenSaverCardInstance();
    card.id = (rawCard.id !== undefined && rawCard.id.length > 0) ? rawCard.id : screenSaverGenerateId('card');
    card.cardType = cardType;
    card.colSpan = screenSaverClampInt(rawCard.colSpan ?? 1, 1, SCREEN_SAVER_GRID_COLS);
    card.rowSpan = screenSaverClampInt(rawCard.rowSpan ?? 1, 1, SCREEN_SAVER_GRID_ROWS);
    card.colStart = screenSaverClampInt(rawCard.colStart ?? 0, 0, SCREEN_SAVER_GRID_COLS - card.colSpan);
    card.rowStart = screenSaverClampInt(rawCard.rowStart ?? 0, 0, SCREEN_SAVER_GRID_ROWS - card.rowSpan);
    const rawClock = rawCard.clock;
    if (rawClock !== undefined) {
      card.clock.showSeconds = rawClock.showSeconds ?? false;
      card.clock.showDate = rawClock.showDate ?? true;
      card.clock.use24Hour = rawClock.use24Hour ?? true;
      card.clock.fontScale = screenSaverClampNumber(rawClock.fontScale ?? 1.0, 0.5, 2.0);
    }
    const rawPhoto = rawCard.photo;
    if (rawPhoto !== undefined) {
      card.photo.uris = rawPhoto.uris ?? [];
      card.photo.intervalSec = screenSaverClampInt(rawPhoto.intervalSec ?? 30, 5, 3600);
      card.photo.shuffle = rawPhoto.shuffle ?? false;
    }
    return card;
  }

  private createFirstRunConfig(): void {
    const page = new ScreenSaverPageConfig();
    page.id = screenSaverGenerateId('page');
    page.name = '屏保页 1';
    const clockCard = new ScreenSaverCardInstance();
    clockCard.id = screenSaverGenerateId('card');
    clockCard.cardType = 'clock';
    clockCard.colStart = 0;
    clockCard.rowStart = 0;
    clockCard.colSpan = 1;
    clockCard.rowSpan = 1;
    page.cards.push(clockCard);
    this.appConfig.pages = [page];
    this.save();
  }
}

export const screenSaverAppModel: ScreenSaverAppModel = new ScreenSaverAppModel();
