import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { ScreenSaverLogger } from '../common/Logger';
import { SCREEN_SAVER_CARD_CATALOG, screenSaverFindCardMeta } from '../cards/CardCatalog';
import {
  SCREEN_SAVER_CARD_MAX_COLS,
  SCREEN_SAVER_CARD_MAX_ROWS,
  SCREEN_SAVER_GIT_WEEK_OPTIONS,
  SCREEN_SAVER_GRID_COLS,
  SCREEN_SAVER_GRID_ROWS,
  SCREEN_SAVER_PHOTO_MIN_INTERVAL_SEC,
  SCREEN_SAVER_SCHEMA_VERSION,
  ScreensaverCardInstance,
  ScreensaverCardMeta,
  ScreensaverCardType,
  ScreensaverGitData,
  ScreensaverGitDay,
  ScreensaverGridPos,
  ScreensaverGridSlot,
  ScreensaverLayout,
  ScreensaverRawCard,
  ScreensaverRawClock,
  ScreensaverRawGit,
  ScreensaverRawGitCache,
  ScreensaverRawGitDay,
  ScreensaverRawLayout,
  ScreensaverRawPage,
  ScreensaverRawPhoto,
  ScreensaverRawSettings,
  ScreensaverRawVideo,
  ScreensaverSettings
} from './ConfigModels';

const SCREEN_SAVER_STORE_NAME: string = 'screen_saver_store';
const SCREEN_SAVER_LAYOUT_KEY: string = 'screen_saver_layout_v2';
const SCREEN_SAVER_LEGACY_KEY: string = 'screen_saver_config';
const SCREEN_SAVER_GUIDE_KEY: string = 'screen_saver_guide_done';
const SCREEN_SAVER_GIT_TOKEN_KEY: string = 'screen_saver_git_token';
const SCREEN_SAVER_GIT_CACHE_KEY: string = 'screen_saver_git_cache';
const SCREEN_SAVER_SAVE_DEBOUNCE_MS: number = 200;

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

export class ScreensaverAppModel {
  readonly layout: ScreensaverLayout = new ScreensaverLayout();
  private abilityContext: common.UIAbilityContext | undefined = undefined;
  private store: preferences.Preferences | undefined = undefined;
  private saveTimer: number = -1;
  private loaded: boolean = false;
  private loadedCallbacks: Array<() => void> = [];
  private guideDone: boolean = false;
  private gitToken: string = '';
  private gitCache: ScreensaverGitData | undefined = undefined;

  attachContext(context: common.UIAbilityContext): void {
    this.abilityContext = context;
  }

  isLoaded(): boolean {
    return this.loaded;
  }

  whenLoaded(callback: () => void): void {
    if (this.loaded) {
      callback();
      return;
    }
    this.loadedCallbacks.push(callback);
  }

  private notifyLoaded(): void {
    this.loaded = true;
    const callbacks = this.loadedCallbacks;
    this.loadedCallbacks = [];
    for (const callback of callbacks) {
      callback();
    }
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
        this.ensureDefaultLayout();
        return;
      }
      const guideValue = await store.get(SCREEN_SAVER_GUIDE_KEY, false);
      this.guideDone = typeof guideValue === 'boolean' ? guideValue : false;
      const tokenValue = await store.get(SCREEN_SAVER_GIT_TOKEN_KEY, '');
      this.gitToken = typeof tokenValue === 'string' ? tokenValue : '';
      const cacheValue = await store.get(SCREEN_SAVER_GIT_CACHE_KEY, '');
      if (typeof cacheValue === 'string' && cacheValue.length > 0) {
        this.gitCache = this.parseGitCache(cacheValue);
      }
      const layoutText = await store.get(SCREEN_SAVER_LAYOUT_KEY, '');
      if (typeof layoutText === 'string' && layoutText.length > 0) {
        this.applyLayoutText(layoutText);
      } else {
        const legacyText = await store.get(SCREEN_SAVER_LEGACY_KEY, '');
        if (typeof legacyText === 'string' && legacyText.length > 0) {
          this.applyLayoutText(legacyText);
        } else {
          this.ensureDefaultLayout();
        }
      }
      this.notifyLoaded();
      ScreenSaverLogger.info(`layout loaded: cards=${this.layout.cards.length}`);
    } catch (err) {
      const error = err as Error;
      ScreenSaverLogger.error(`layout load failed: ${error.message}`);
      this.ensureDefaultLayout();
      this.notifyLoaded();
    }
  }

  save(): void {
    if (this.saveTimer >= 0) {
      clearTimeout(this.saveTimer);
    }
    this.saveTimer = setTimeout((): void => {
      this.saveTimer = -1;
      void this.persistLayout();
    }, SCREEN_SAVER_SAVE_DEBOUNCE_MS);
  }

  async flush(): Promise<void> {
    if (this.saveTimer >= 0) {
      clearTimeout(this.saveTimer);
      this.saveTimer = -1;
    }
    await this.persistLayout();
  }

  isGuideDone(): boolean {
    return this.guideDone;
  }

  markGuideDone(): void {
    if (this.guideDone) {
      return;
    }
    this.guideDone = true;
    void this.persistFlag(SCREEN_SAVER_GUIDE_KEY, true);
  }

  getGitToken(): string {
    return this.gitToken;
  }

  hasGitToken(): boolean {
    return this.gitToken.length > 0;
  }

  setGitToken(token: string): void {
    this.gitToken = token.trim();
    void this.persistFlag(SCREEN_SAVER_GIT_TOKEN_KEY, this.gitToken);
  }

  getGitCache(): ScreensaverGitData | undefined {
    return this.gitCache;
  }

  setGitCache(data: ScreensaverGitData): void {
    this.gitCache = data;
    const raw: ScreensaverRawGitCache = {
      username: data.username,
      days: this.gitDaysToRaw(data.days),
      fetchedAt: data.fetchedAt,
      total: data.total
    };
    void this.persistFlag(SCREEN_SAVER_GIT_CACHE_KEY, JSON.stringify(raw));
  }

  cardById(cardId: string): ScreensaverCardInstance | undefined {
    return this.layout.cards.find((card: ScreensaverCardInstance): boolean => card.id === cardId);
  }

  hasCardType(cardType: ScreensaverCardType): boolean {
    return this.layout.cards.some((card: ScreensaverCardInstance): boolean => card.cardType === cardType);
  }

  cardsOfType(cardType: ScreensaverCardType): ScreensaverCardInstance[] {
    return this.layout.cards.filter((card: ScreensaverCardInstance): boolean => card.cardType === cardType);
  }

  cardAddBlockedReason(cardType: ScreensaverCardType): string {
    const meta = screenSaverFindCardMeta(cardType);
    if (meta === undefined) {
      return '未知卡片类型';
    }
    if (meta.unique && this.hasCardType(cardType)) {
      return `${meta.displayName}卡片最多添加一张`;
    }
    if (this.findFreeSlot(meta.defaultColSpan, meta.defaultRowSpan) === undefined) {
      return '空间不足：请先移出或缩小卡片';
    }
    return '';
  }

  addCard(cardType: ScreensaverCardType): boolean {
    if (this.cardAddBlockedReason(cardType).length > 0) {
      return false;
    }
    const meta = screenSaverFindCardMeta(cardType);
    if (meta === undefined) {
      return false;
    }
    const slot = this.findFreeSlot(meta.defaultColSpan, meta.defaultRowSpan);
    if (slot === undefined) {
      return false;
    }
    const card = this.buildCard(cardType, slot.colStart, slot.rowStart, meta.defaultColSpan, meta.defaultRowSpan);
    this.layout.cards.push(card);
    this.save();
    return true;
  }

  setCardEnabled(cardId: string, enabled: boolean): void {
    const card = this.cardById(cardId);
    if (card === undefined || card.enabled === enabled) {
      return;
    }
    card.enabled = enabled;
    this.save();
  }

  snapshotCards(): string {
    return JSON.stringify(this.toRawCards());
  }

  restoreCardsFromSnapshot(text: string): void {
    if (text.length === 0) {
      return;
    }
    let rawCards: ScreensaverRawCard[] = [];
    try {
      rawCards = JSON.parse(text) as ScreensaverRawCard[];
    } catch (parseError) {
      const error = parseError as Error;
      ScreenSaverLogger.warn(`edit snapshot restore failed: ${error.message}`);
      return;
    }
    this.applyCards(rawCards);
    this.save();
  }

  removeCard(cardId: string): void {
    const index = this.layout.cards.findIndex((card: ScreensaverCardInstance): boolean => card.id === cardId);
    if (index >= 0) {
      this.layout.cards.splice(index, 1);
      this.save();
    }
  }

  removeCardsOfType(cardType: ScreensaverCardType): void {
    const kept: ScreensaverCardInstance[] = [];
    for (const card of this.layout.cards) {
      if (card.cardType !== cardType) {
        kept.push(card);
      }
    }
    if (kept.length !== this.layout.cards.length) {
      this.layout.cards = kept;
      this.save();
    }
  }

  moveCard(cardId: string, deltaCol: number, deltaRow: number): boolean {
    const card = this.cardById(cardId);
    if (card === undefined) {
      return false;
    }
    const nextCol = screenSaverClampInt(card.colStart + deltaCol, 0, SCREEN_SAVER_GRID_COLS - card.colSpan);
    const nextRow = screenSaverClampInt(card.rowStart + deltaRow, 0, SCREEN_SAVER_GRID_ROWS - card.rowSpan);
    if (nextCol === card.colStart && nextRow === card.rowStart) {
      return false;
    }
    return this.placeCard(cardId, nextCol, nextRow, card.colSpan, card.rowSpan);
  }

  resizeCardTo(cardId: string, colSpan: number, rowSpan: number): boolean {
    const card = this.cardById(cardId);
    if (card === undefined) {
      return false;
    }
    const meta = screenSaverFindCardMeta(card.cardType);
    const minCols = meta !== undefined ? meta.minColSpan : SCREEN_SAVER_CARD_MAX_COLS;
    const minRows = meta !== undefined ? meta.minRowSpan : 1;
    const maxCols = meta !== undefined ? meta.maxColSpan : SCREEN_SAVER_CARD_MAX_COLS;
    const maxRows = meta !== undefined ? meta.maxRowSpan : SCREEN_SAVER_CARD_MAX_ROWS;
    const nextColSpan = screenSaverClampInt(colSpan, minCols, maxCols);
    const nextRowSpan = screenSaverClampInt(rowSpan, minRows, maxRows);
    if (nextColSpan === card.colSpan && nextRowSpan === card.rowSpan) {
      return false;
    }
    const nextColStart = Math.min(card.colStart, SCREEN_SAVER_GRID_COLS - nextColSpan);
    const nextRowStart = Math.min(card.rowStart, SCREEN_SAVER_GRID_ROWS - nextRowSpan);
    return this.placeCard(cardId, nextColStart, nextRowStart, nextColSpan, nextRowSpan);
  }

  placeCard(cardId: string, colStart: number, rowStart: number, colSpan: number, rowSpan: number): boolean {
    const card = this.cardById(cardId);
    if (card === undefined) {
      return false;
    }
    if (!this.canPlace(cardId, colStart, rowStart, colSpan, rowSpan)) {
      return false;
    }
    card.colStart = colStart;
    card.rowStart = rowStart;
    card.colSpan = colSpan;
    card.rowSpan = rowSpan;
    this.applyClockSizeConstraint(card);
    this.save();
    return true;
  }

  bringToFront(cardId: string): boolean {
    const index = this.layout.cards.findIndex((card: ScreensaverCardInstance): boolean => card.id === cardId);
    if (index < 0 || index === this.layout.cards.length - 1) {
      return false;
    }
    const card = this.layout.cards[index];
    this.layout.cards.splice(index, 1);
    this.layout.cards.push(card);
    this.save();
    return true;
  }

  canPlace(cardId: string, colStart: number, rowStart: number, colSpan: number, rowSpan: number): boolean {
    if (colStart < 0 || rowStart < 0 || colSpan <= 0 || rowSpan <= 0) {
      return false;
    }
    if (colStart + colSpan > SCREEN_SAVER_GRID_COLS || rowStart + rowSpan > SCREEN_SAVER_GRID_ROWS) {
      return false;
    }
    for (const card of this.layout.cards) {
      if (card.id === cardId) {
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

  reflowForColumns(columns: number, rows: number): ScreensaverGridPos[] {
    const result: ScreensaverGridPos[] = [];
    const occupied: boolean[] = [];
    const cellCount = columns * rows;
    for (let i = 0; i < cellCount; i++) {
      occupied.push(false);
    }
    const colFactor = columns / SCREEN_SAVER_GRID_COLS;
    const rowFactor = rows / SCREEN_SAVER_GRID_ROWS;
    for (const card of this.layout.cards) {
      let spanCols = Math.max(1, Math.min(columns, Math.round(card.colSpan * colFactor)));
      let spanRows = Math.max(1, Math.min(rows, Math.round(card.rowSpan * rowFactor)));
      let placed = false;
      while (!placed) {
        const slot = this.findRegionInOccupied(occupied, columns, rows, spanCols, spanRows);
        if (slot !== undefined) {
          this.markRegion(occupied, columns, slot.colStart, slot.rowStart, spanCols, spanRows, true);
          const pos: ScreensaverGridPos = {
            colStart: slot.colStart,
            rowStart: slot.rowStart,
            colSpan: spanCols,
            rowSpan: spanRows
          };
          result.push(pos);
          placed = true;
          break;
        }
        if (spanRows > 1) {
          spanRows--;
          continue;
        }
        if (spanCols > 1) {
          spanCols--;
          continue;
        }
        break;
      }
      if (!placed) {
        const pos: ScreensaverGridPos = { colStart: 0, rowStart: 0, colSpan: spanCols, rowSpan: spanRows };
        result.push(pos);
      }
    }
    return result;
  }

  private findRegionInOccupied(occupied: boolean[], columns: number, rows: number, colSpan: number,
    rowSpan: number): ScreensaverGridSlot | undefined {
    for (let row = 0; row <= rows - rowSpan; row++) {
      for (let col = 0; col <= columns - colSpan; col++) {
        if (this.regionFree(occupied, columns, col, row, colSpan, rowSpan)) {
          const slot: ScreensaverGridSlot = { colStart: col, rowStart: row };
          return slot;
        }
      }
    }
    return undefined;
  }

  private regionFree(occupied: boolean[], columns: number, col: number, row: number, colSpan: number,
    rowSpan: number): boolean {
    for (let r = row; r < row + rowSpan; r++) {
      for (let c = col; c < col + colSpan; c++) {
        if (occupied[r * columns + c]) {
          return false;
        }
      }
    }
    return true;
  }

  private markRegion(occupied: boolean[], columns: number, col: number, row: number, colSpan: number,
    rowSpan: number, value: boolean): void {
    for (let r = row; r < row + rowSpan; r++) {
      for (let c = col; c < col + colSpan; c++) {
        occupied[r * columns + c] = value;
      }
    }
  }

  private findFreeSlot(colSpan: number, rowSpan: number): ScreensaverGridSlot | undefined {
    for (let row = 0; row <= SCREEN_SAVER_GRID_ROWS - rowSpan; row++) {
      for (let col = 0; col <= SCREEN_SAVER_GRID_COLS - colSpan; col++) {
        let free = true;
        for (const card of this.layout.cards) {
          const overlaps = col < card.colStart + card.colSpan && col + colSpan > card.colStart &&
            row < card.rowStart + card.rowSpan && row + rowSpan > card.rowStart;
          if (overlaps) {
            free = false;
            break;
          }
        }
        if (free) {
          const slot: ScreensaverGridSlot = { colStart: col, rowStart: row };
          return slot;
        }
      }
    }
    return undefined;
  }

  private buildCard(cardType: ScreensaverCardType, colStart: number, rowStart: number, colSpan: number,
    rowSpan: number): ScreensaverCardInstance {
    const card = new ScreensaverCardInstance();
    card.id = screenSaverGenerateId('card');
    card.cardType = cardType;
    card.colStart = colStart;
    card.rowStart = rowStart;
    card.colSpan = colSpan;
    card.rowSpan = rowSpan;
    if (cardType === 'photo') {
      card.photo.intervalSec = this.layout.settings.defaultIntervalSec;
    }
    if (cardType === 'video') {
      card.video.playing = this.layout.settings.videoDefaultAutoplay;
    }
    return card;
  }

  ensureDefaultLayout(): void {
    this.layout.settings = new ScreensaverSettings();
    this.layout.cards = [];
    const clockCard = this.buildCard('clock', 0, 0, 4, 2);
    clockCard.clock.format = 'timeDate';
    const gitCard = this.buildCard('git', 0, 2, 4, 2);
    const photoCard = this.buildCard('photo', 0, 4, 4, 4);
    this.layout.cards.push(clockCard);
    this.layout.cards.push(gitCard);
    this.layout.cards.push(photoCard);
    this.save();
  }

  private applyClockSizeConstraint(card: ScreensaverCardInstance): void {
    if (card.cardType !== 'clock') {
      return;
    }
    if (card.colSpan * card.rowSpan < 4) {
      card.clock.format = 'timeOnly';
    }
  }

  private applyLayoutText(text: string): void {
    let raw: ScreensaverRawLayout | undefined = undefined;
    try {
      raw = JSON.parse(text) as ScreensaverRawLayout;
    } catch (parseError) {
      const error = parseError as Error;
      ScreenSaverLogger.error(`layout parse failed: ${error.message}`);
      this.ensureDefaultLayout();
      return;
    }
    if (raw === undefined) {
      this.ensureDefaultLayout();
      return;
    }
    this.applySettings(raw.settings);
    const legacyPages = raw.pages;
    if (raw.cards === undefined && legacyPages !== undefined && legacyPages.length > 0) {
      ScreenSaverLogger.info('migrating legacy multi-page layout');
      const firstPage: ScreensaverRawPage = legacyPages[0];
      this.applyCards(firstPage.cards ?? []);
    } else {
      this.applyCards(raw.cards ?? []);
    }
    if (this.layout.cards.length === 0 && raw.schemaVersion !== undefined) {
      ScreenSaverLogger.info('empty layout from storage, no auto default');
    }
    this.layout.schemaVersion = SCREEN_SAVER_SCHEMA_VERSION;
  }

  private applySettings(rawSettings: ScreensaverRawSettings | undefined): void {
    const settings = this.layout.settings;
    if (rawSettings === undefined) {
      return;
    }
    settings.defaultIntervalSec = screenSaverClampInt(rawSettings.defaultIntervalSec ?? 30,
      SCREEN_SAVER_PHOTO_MIN_INTERVAL_SEC, 3600);
    settings.fontFollowSystem = rawSettings.fontFollowSystem ?? false;
    settings.singleCardCentered = rawSettings.singleCardCentered ?? false;
    settings.albumSource = rawSettings.albumSource ?? 'all';
    settings.videoDefaultAutoplay = rawSettings.videoDefaultAutoplay ?? false;
    settings.keepScreenOn = rawSettings.keepScreenOn ?? true;
    settings.motionDisabled = rawSettings.motionDisabled ?? false;
    settings.lowBatteryAutoExit = rawSettings.lowBatteryAutoExit ?? true;
  }

  private applyCards(rawCards: ScreensaverRawCard[]): void {
    const accepted: ScreensaverCardInstance[] = [];
    for (const rawCard of rawCards) {
      const card = this.buildCardFromRaw(rawCard);
      if (card === undefined) {
        continue;
      }
      if (!this.canPlaceInList(accepted, card)) {
        ScreenSaverLogger.warn(`drop overlapping card on load: ${card.id}`);
        continue;
      }
      accepted.push(card);
    }
    this.layout.cards = accepted;
  }

  private canPlaceInList(cards: ScreensaverCardInstance[], candidate: ScreensaverCardInstance): boolean {
    if (candidate.colStart + candidate.colSpan > SCREEN_SAVER_GRID_COLS ||
      candidate.rowStart + candidate.rowSpan > SCREEN_SAVER_GRID_ROWS) {
      return false;
    }
    for (const card of cards) {
      const overlaps = candidate.colStart < card.colStart + card.colSpan &&
        candidate.colStart + candidate.colSpan > card.colStart &&
        candidate.rowStart < card.rowStart + card.rowSpan &&
        candidate.rowStart + candidate.rowSpan > card.rowStart;
      if (overlaps) {
        return false;
      }
    }
    return true;
  }

  private buildCardFromRaw(rawCard: ScreensaverRawCard): ScreensaverCardInstance | undefined {
    const cardType = this.parseCardType(rawCard.cardType);
    if (cardType === undefined) {
      return undefined;
    }
    const meta = screenSaverFindCardMeta(cardType);
    const maxCols = meta !== undefined ? meta.maxColSpan : SCREEN_SAVER_CARD_MAX_COLS;
    const maxRows = meta !== undefined ? meta.maxRowSpan : SCREEN_SAVER_CARD_MAX_ROWS;
    const card = new ScreensaverCardInstance();
    card.id = (rawCard.id !== undefined && rawCard.id.length > 0) ? rawCard.id : screenSaverGenerateId('card');
    card.cardType = cardType;
    card.enabled = rawCard.enabled ?? true;
    card.colSpan = screenSaverClampInt(rawCard.colSpan ?? 2, 1, maxCols);
    card.rowSpan = screenSaverClampInt(rawCard.rowSpan ?? 2, 1, maxRows);
    card.colStart = screenSaverClampInt(rawCard.colStart ?? 0, 0, SCREEN_SAVER_GRID_COLS - card.colSpan);
    card.rowStart = screenSaverClampInt(rawCard.rowStart ?? 0, 0, SCREEN_SAVER_GRID_ROWS - card.rowSpan);
    this.applyRawClock(card, rawCard.clock);
    this.applyRawPhoto(card, rawCard.photo);
    this.applyRawVideo(card, rawCard.video);
    this.applyRawGit(card, rawCard.git);
    return card;
  }

  private parseCardType(value: string | undefined): ScreensaverCardType | undefined {
    if (value === 'clock') {
      return 'clock';
    }
    if (value === 'photo') {
      return 'photo';
    }
    if (value === 'video') {
      return 'video';
    }
    if (value === 'git') {
      return 'git';
    }
    return undefined;
  }

  private applyRawClock(card: ScreensaverCardInstance, rawClock: ScreensaverRawClock | undefined): void {
    if (rawClock === undefined) {
      return;
    }
    const format = rawClock.format;
    if (format === 'timeDate' || format === 'timeOnly' || format === 'dateOnly' || format === 'lunar') {
      card.clock.format = format;
    } else if (rawClock.showDate === false) {
      card.clock.format = 'timeOnly';
    } else if (rawClock.showDate === true) {
      card.clock.format = 'timeDate';
    }
    card.clock.use24Hour = rawClock.use24Hour ?? true;
    card.clock.showSeconds = rawClock.showSeconds ?? false;
    const fontStep = rawClock.fontStep;
    if (fontStep !== undefined) {
      card.clock.fontStep = screenSaverClampInt(fontStep, -1, 2);
    } else if (rawClock.fontScale !== undefined) {
      if (rawClock.fontScale >= 1.2) {
        card.clock.fontStep = 2;
      } else if (rawClock.fontScale <= 0.9) {
        card.clock.fontStep = 0;
      } else {
        card.clock.fontStep = 1;
      }
    }
  }

  private applyRawPhoto(card: ScreensaverCardInstance, rawPhoto: ScreensaverRawPhoto | undefined): void {
    if (rawPhoto === undefined) {
      return;
    }
    const uris: string[] = [];
    for (const uri of rawPhoto.uris ?? []) {
      if (uri.length > 0) {
        uris.push(uri);
      }
    }
    card.photo.uris = uris;
    const rawDates = rawPhoto.uriDates;
    if (rawDates !== undefined) {
      card.photo.uriDates = rawDates;
    }
    card.photo.sourceAlbum = rawPhoto.sourceAlbum ?? 'all';
    card.photo.intervalSec = screenSaverClampInt(rawPhoto.intervalSec ?? 30, SCREEN_SAVER_PHOTO_MIN_INTERVAL_SEC, 3600);
    if (rawPhoto.order === 'shuffle' || rawPhoto.order === 'time') {
      card.photo.order = rawPhoto.order;
    } else if (rawPhoto.shuffle === true) {
      card.photo.order = 'shuffle';
    }
    card.photo.showInfo = rawPhoto.showInfo ?? false;
    card.photo.wifiOnlyPrefetch = rawPhoto.wifiOnlyPrefetch ?? false;
  }

  private applyRawVideo(card: ScreensaverCardInstance, rawVideo: ScreensaverRawVideo | undefined): void {
    if (rawVideo === undefined) {
      return;
    }
    card.video.uri = rawVideo.uri ?? '';
    card.video.playing = rawVideo.playing ?? false;
    card.video.loop = rawVideo.loop ?? false;
    card.video.muted = rawVideo.muted ?? true;
  }

  private applyRawGit(card: ScreensaverCardInstance, rawGit: ScreensaverRawGit | undefined): void {
    if (rawGit === undefined) {
      return;
    }
    card.git.provider = rawGit.provider ?? 'github';
    const username = rawGit.username;
    if (username !== undefined && username.length > 0) {
      card.git.username = username;
    }
    const rawWeeks = rawGit.weeks;
    if (rawWeeks !== undefined && SCREEN_SAVER_GIT_WEEK_OPTIONS.indexOf(rawWeeks) >= 0) {
      card.git.weeks = rawWeeks;
    } else {
      card.git.weeks = 20;
    }
    card.git.palette = rawGit.palette ?? 'green';
    card.git.offlineCache = rawGit.offlineCache ?? true;
  }

  private toRawLayout(): ScreensaverRawLayout {
    const settings = this.layout.settings;
    const rawSettings: ScreensaverRawSettings = {
      defaultIntervalSec: settings.defaultIntervalSec,
      fontFollowSystem: settings.fontFollowSystem,
      singleCardCentered: settings.singleCardCentered,
      albumSource: settings.albumSource,
      videoDefaultAutoplay: settings.videoDefaultAutoplay,
      keepScreenOn: settings.keepScreenOn,
      motionDisabled: settings.motionDisabled,
      lowBatteryAutoExit: settings.lowBatteryAutoExit
    };
    const rawLayout: ScreensaverRawLayout = {
      schemaVersion: SCREEN_SAVER_SCHEMA_VERSION,
      settings: rawSettings,
      cards: this.toRawCards()
    };
    return rawLayout;
  }

  private toRawCards(): ScreensaverRawCard[] {
    const rawCards: ScreensaverRawCard[] = [];
    for (const card of this.layout.cards) {
      const rawClock: ScreensaverRawClock = {
        format: card.clock.format,
        use24Hour: card.clock.use24Hour,
        showSeconds: card.clock.showSeconds,
        fontStep: card.clock.fontStep
      };
      const rawPhoto: ScreensaverRawPhoto = {
        uris: card.photo.uris,
        uriDates: card.photo.uriDates,
        sourceAlbum: card.photo.sourceAlbum,
        intervalSec: card.photo.intervalSec,
        order: card.photo.order,
        showInfo: card.photo.showInfo,
        wifiOnlyPrefetch: card.photo.wifiOnlyPrefetch
      };
      const rawVideo: ScreensaverRawVideo = {
        uri: card.video.uri,
        playing: card.video.playing,
        loop: card.video.loop,
        muted: card.video.muted
      };
      const rawGit: ScreensaverRawGit = {
        provider: card.git.provider,
        username: card.git.username,
        weeks: card.git.weeks,
        palette: card.git.palette,
        offlineCache: card.git.offlineCache
      };
      const rawCard: ScreensaverRawCard = {
        id: card.id,
        cardType: card.cardType,
        enabled: card.enabled,
        colStart: card.colStart,
        rowStart: card.rowStart,
        colSpan: card.colSpan,
        rowSpan: card.rowSpan,
        clock: rawClock,
        photo: rawPhoto,
        video: rawVideo,
        git: rawGit
      };
      rawCards.push(rawCard);
    }
    return rawCards;
  }

  private gitDaysToRaw(days: ScreensaverGitDay[]): ScreensaverRawGitDay[] {
    const rawDays: ScreensaverRawGitDay[] = [];
    for (const day of days) {
      const rawDay: ScreensaverRawGitDay = { date: day.date, count: day.count };
      rawDays.push(rawDay);
    }
    return rawDays;
  }

  private parseGitCache(text: string): ScreensaverGitData | undefined {
    try {
      const raw = JSON.parse(text) as ScreensaverRawGitCache;
      const days: ScreensaverGitDay[] = [];
      for (const rawDay of raw.days ?? []) {
        if (rawDay.date === undefined || rawDay.date.length === 0) {
          continue;
        }
        const day: ScreensaverGitDay = { date: rawDay.date, count: rawDay.count ?? 0 };
        days.push(day);
      }
      const data: ScreensaverGitData = {
        username: raw.username ?? '',
        days: days,
        fetchedAt: raw.fetchedAt ?? 0,
        total: raw.total ?? 0
      };
      return data;
    } catch (err) {
      const error = err as Error;
      ScreenSaverLogger.warn(`git cache parse failed: ${error.message}`);
      return undefined;
    }
  }

  cardSummary(cardType: ScreensaverCardType): string {
    const cards = this.cardsOfType(cardType);
    if (cards.length === 0) {
      return '未添加';
    }
    const meta = screenSaverFindCardMeta(cardType);
    const defaultCols = meta !== undefined ? meta.defaultColSpan : 4;
    const defaultRows = meta !== undefined ? meta.defaultRowSpan : 2;
    if (cards.length > 1) {
      return `已添加 ×${cards.length}`;
    }
    return `${defaultCols}×${defaultRows} · 已添加`;
  }

  cardInstanceSummary(card: ScreensaverCardInstance): string {
    if (card.cardType === 'clock') {
      if (card.clock.format === 'timeOnly') {
        return '纯时间';
      }
      if (card.clock.format === 'dateOnly') {
        return '纯日期';
      }
      if (card.clock.format === 'lunar') {
        return '农历';
      }
      return '时间 + 日期';
    }
    if (card.cardType === 'photo') {
      const count = card.photo.uris.length;
      const interval = card.photo.intervalSec > 0 ? `${card.photo.intervalSec}s 切换` : '手动切换';
      return count > 0 ? `${count} 张照片 · ${interval}` : '未选择照片';
    }
    if (card.cardType === 'video') {
      if (card.video.uri.length === 0) {
        return '未选择视频';
      }
      return card.video.playing ? '播放中' : '显示封面帧';
    }
    return `@${card.git.username} · ${card.git.weeks} 周`;
  }

  catalogMetas(): ScreensaverCardMeta[] {
    return SCREEN_SAVER_CARD_CATALOG;
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

  private async persistLayout(): Promise<void> {
    const store = await this.ensureStore();
    if (store === undefined) {
      return;
    }
    try {
      const text = JSON.stringify(this.toRawLayout());
      await store.put(SCREEN_SAVER_LAYOUT_KEY, text);
      await store.flush();
    } catch (err) {
      const error = err as Error;
      ScreenSaverLogger.error(`layout save failed: ${error.message}`);
    }
  }

  private async persistFlag(key: string, value: preferences.ValueType): Promise<void> {
    const store = await this.ensureStore();
    if (store === undefined) {
      return;
    }
    try {
      await store.put(key, value);
      await store.flush();
    } catch (err) {
      const error = err as Error;
      ScreenSaverLogger.error(`flag save failed: ${key}: ${error.message}`);
    }
  }
}

export const screenSaverAppModel: ScreensaverAppModel = new ScreensaverAppModel();
