export type ScreensaverCardType = 'clock' | 'photo' | 'video' | 'git';
export type ScreensaverCardMode = 'edit' | 'play';
export type ClockFormat = 'timeDate' | 'timeOnly' | 'dateOnly' | 'lunar';
export type PhotoOrder = 'shuffle' | 'time';
export type GitLoadState = 'idle' | 'loading' | 'success' | 'offline' | 'error';
export type SheetKind = 'none' | 'clock' | 'photo' | 'video' | 'git' | 'albumSource';

export const SCREEN_SAVER_SCHEMA_VERSION: number = 2;
export const SCREEN_SAVER_GRID_COLS: number = 4;
export const SCREEN_SAVER_GRID_ROWS: number = 8;
export const SCREEN_SAVER_WIDE_COLS_FOLD: number = 8;
export const SCREEN_SAVER_WIDE_ROWS_FOLD: number = 8;
export const SCREEN_SAVER_WIDE_COLS_TABLET: number = 12;
export const SCREEN_SAVER_WIDE_ROWS_TABLET: number = 7;
export const SCREEN_SAVER_BREAKPOINT_FOLD_VP: number = 600;
export const SCREEN_SAVER_BREAKPOINT_TABLET_VP: number = 840;
export const SCREEN_SAVER_CARD_MIN_COLS: number = 1;
export const SCREEN_SAVER_CARD_MAX_COLS: number = 4;
export const SCREEN_SAVER_CARD_MIN_ROWS: number = 1;
export const SCREEN_SAVER_CARD_MAX_ROWS: number = 6;
export const SCREEN_SAVER_PHOTO_MIN_INTERVAL_SEC: number = 15;
export const SCREEN_SAVER_PHOTO_INTERVAL_OPTIONS: number[] = [15, 30, 60, 300];
export const SCREEN_SAVER_PHOTO_MOVE_FADE_MS: number = 120;
export const SCREEN_SAVER_GIT_WEEK_OPTIONS: number[] = [12, 20];
export const SCREEN_SAVER_GIT_THROTTLE_MS: number = 30 * 60 * 1000;
export const SCREEN_SAVER_GIT_FETCH_TIMEOUT_MS: number = 10000;
export const SCREEN_SAVER_PHOTO_MAX_RESIDENT: number = 3;
export const SCREEN_SAVER_PHOTO_RECENT_DEDUP: number = 50;
export const SCREEN_SAVER_PHOTO_PAGE_SIZE: number = 200;
export const SCREEN_SAVER_CLOCK_MIN_FONT: number = 12;
export const SCREEN_SAVER_CLOCK_MAX_FONT: number = 160;
export const SCREEN_SAVER_CLOCK_SMALL_FONT: number = 32;

export interface ScreensaverNumberOption {
  value: number;
  label: string;
}

export interface ScreensaverStringOption {
  value: string;
  label: string;
}

export interface ScreensaverCardMeta {
  cardType: ScreensaverCardType;
  displayName: string;
  description: string;
  defaultColSpan: number;
  defaultRowSpan: number;
  minColSpan: number;
  minRowSpan: number;
  maxColSpan: number;
  maxRowSpan: number;
  sizePresets: ScreensaverSizePreset[];
}

export interface ScreensaverSizePreset {
  colSpan: number;
  rowSpan: number;
  label: string;
}

export interface ScreensaverGridPos {
  colStart: number;
  rowStart: number;
  colSpan: number;
  rowSpan: number;
}

export interface ScreensaverGridSlot {
  colStart: number;
  rowStart: number;
}

export interface ScreensaverLaunchParam {
  from: string;
}

export interface ScreensaverGitDay {
  date: string;
  count: number;
}

export interface ScreensaverGitData {
  username: string;
  days: ScreensaverGitDay[];
  fetchedAt: number;
  total: number;
}

@ObservedV2
export class ScreensaverClockConfig {
  @Trace format: ClockFormat = 'timeDate';
  @Trace use24Hour: boolean = true;
  @Trace showSeconds: boolean = false;
  @Trace fontStep: number = 1;
}

@ObservedV2
export class ScreensaverPhotoConfig {
  @Trace uris: string[] = [];
  @Trace sourceAlbum: string = 'all';
  @Trace intervalSec: number = 30;
  @Trace order: PhotoOrder = 'time';
  @Trace showInfo: boolean = false;
  @Trace wifiOnlyPrefetch: boolean = false;
}

@ObservedV2
export class ScreensaverVideoConfig {
  @Trace uri: string = '';
  @Trace playing: boolean = false;
  @Trace loop: boolean = false;
  @Trace muted: boolean = true;
}

@ObservedV2
export class ScreensaverGitConfig {
  @Trace provider: string = 'github';
  @Trace username: string = 'octocat';
  @Trace weeks: number = 20;
  @Trace palette: string = 'green';
  @Trace offlineCache: boolean = true;
}

@ObservedV2
export class ScreensaverCardInstance {
  @Trace id: string = '';
  @Trace cardType: ScreensaverCardType = 'clock';
  @Trace colStart: number = 0;
  @Trace rowStart: number = 0;
  @Trace colSpan: number = 2;
  @Trace rowSpan: number = 2;
  @Trace clock: ScreensaverClockConfig = new ScreensaverClockConfig();
  @Trace photo: ScreensaverPhotoConfig = new ScreensaverPhotoConfig();
  @Trace video: ScreensaverVideoConfig = new ScreensaverVideoConfig();
  @Trace git: ScreensaverGitConfig = new ScreensaverGitConfig();
}

@ObservedV2
export class ScreensaverSettings {
  @Trace defaultIntervalSec: number = 30;
  @Trace fontFollowSystem: boolean = false;
  @Trace singleCardCentered: boolean = false;
  @Trace albumSource: string = 'all';
  @Trace videoDefaultAutoplay: boolean = false;
  @Trace keepScreenOn: boolean = true;
  @Trace motionDisabled: boolean = false;
}

@ObservedV2
export class ScreensaverLayout {
  @Trace schemaVersion: number = SCREEN_SAVER_SCHEMA_VERSION;
  @Trace settings: ScreensaverSettings = new ScreensaverSettings();
  @Trace cards: ScreensaverCardInstance[] = [];
}

export interface ScreensaverRawClock {
  format?: string;
  use24Hour?: boolean;
  showSeconds?: boolean;
  fontStep?: number;
  showDate?: boolean;
  fontScale?: number;
}

export interface ScreensaverRawPhoto {
  uris?: string[];
  sourceAlbum?: string;
  intervalSec?: number;
  order?: string;
  showInfo?: boolean;
  wifiOnlyPrefetch?: boolean;
  shuffle?: boolean;
}

export interface ScreensaverRawVideo {
  uri?: string;
  playing?: boolean;
  loop?: boolean;
  muted?: boolean;
}

export interface ScreensaverRawGit {
  provider?: string;
  username?: string;
  weeks?: number;
  palette?: string;
  offlineCache?: boolean;
}

export interface ScreensaverRawCard {
  id?: string;
  cardType?: string;
  colStart?: number;
  rowStart?: number;
  colSpan?: number;
  rowSpan?: number;
  clock?: ScreensaverRawClock;
  photo?: ScreensaverRawPhoto;
  video?: ScreensaverRawVideo;
  git?: ScreensaverRawGit;
}

export interface ScreensaverRawSettings {
  defaultIntervalSec?: number;
  fontFollowSystem?: boolean;
  singleCardCentered?: boolean;
  albumSource?: string;
  videoDefaultAutoplay?: boolean;
  keepScreenOn?: boolean;
  motionDisabled?: boolean;
  dimEnabled?: boolean;
  dimDelaySec?: number;
  dimBrightness?: number;
  ambientColorEnabled?: boolean;
}

export interface ScreensaverRawPage {
  id?: string;
  name?: string;
  cards?: ScreensaverRawCard[];
  ambientColor?: string;
}

export interface ScreensaverRawLayout {
  schemaVersion?: number;
  settings?: ScreensaverRawSettings;
  cards?: ScreensaverRawCard[];
  pages?: ScreensaverRawPage[];
}

export interface ScreensaverRawGitDay {
  date?: string;
  count?: number;
}

export interface ScreensaverRawGitCache {
  username?: string;
  days?: ScreensaverRawGitDay[];
  fetchedAt?: number;
  total?: number;
}
