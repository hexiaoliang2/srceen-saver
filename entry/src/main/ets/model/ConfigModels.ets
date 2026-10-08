export type ScreenSaverCardType = 'clock' | 'photo';
export type ScreenSaverCardMode = 'edit' | 'play';
export type ScreenSaverEditorPanelMode = 'none' | 'ops' | 'add' | 'clock' | 'photo';

export const SCREEN_SAVER_GRID_COLS: number = 4;
export const SCREEN_SAVER_GRID_ROWS: number = 6;
export const SCREEN_SAVER_MAX_PAGES: number = 6;
export const SCREEN_SAVER_AMBIENT_DARKEN_FACTOR: number = 0.45;
export const SCREEN_SAVER_CLOCK_MIN_FONT: number = 12;
export const SCREEN_SAVER_CLOCK_MAX_FONT: number = 160;

export interface ScreenSaverCardMeta {
  cardType: ScreenSaverCardType;
  displayName: string;
  description: string;
  defaultColSpan: number;
  defaultRowSpan: number;
}

export interface ScreenSaverEditorParam {
  pageIndex: number;
}

export interface ScreenSaverLaunchParam {
  from: string;
}

export interface ScreenSaverGridSlot {
  colStart: number;
  rowStart: number;
}

export interface ScreenSaverNumberOption {
  value: number;
  label: string;
}

@ObservedV2
export class ScreenSaverClockConfig {
  @Trace showSeconds: boolean = false;
  @Trace showDate: boolean = true;
  @Trace use24Hour: boolean = true;
  @Trace fontScale: number = 1.0;
}

@ObservedV2
export class ScreenSaverPhotoConfig {
  @Trace uris: string[] = [];
  @Trace intervalSec: number = 30;
  @Trace shuffle: boolean = false;
}

@ObservedV2
export class ScreenSaverCardInstance {
  @Trace id: string = '';
  @Trace cardType: ScreenSaverCardType = 'clock';
  @Trace colStart: number = 0;
  @Trace rowStart: number = 0;
  @Trace colSpan: number = 1;
  @Trace rowSpan: number = 1;
  @Trace clock: ScreenSaverClockConfig = new ScreenSaverClockConfig();
  @Trace photo: ScreenSaverPhotoConfig = new ScreenSaverPhotoConfig();
}

@ObservedV2
export class ScreenSaverPageConfig {
  @Trace id: string = '';
  @Trace name: string = '';
  @Trace cards: ScreenSaverCardInstance[] = [];
  @Trace ambientColor: string = '#000000';
}

@ObservedV2
export class ScreenSaverSettings {
  @Trace dimEnabled: boolean = true;
  @Trace dimDelaySec: number = 60;
  @Trace dimBrightness: number = 0.25;
  @Trace ambientColorEnabled: boolean = true;
}

@ObservedV2
export class ScreenSaverAppConfig {
  @Trace schemaVersion: number = 1;
  @Trace settings: ScreenSaverSettings = new ScreenSaverSettings();
  @Trace pages: ScreenSaverPageConfig[] = [];
}

export interface ScreenSaverRawClock {
  showSeconds?: boolean;
  showDate?: boolean;
  use24Hour?: boolean;
  fontScale?: number;
}

export interface ScreenSaverRawPhoto {
  uris?: string[];
  intervalSec?: number;
  shuffle?: boolean;
}

export interface ScreenSaverRawCard {
  id?: string;
  cardType?: string;
  colStart?: number;
  rowStart?: number;
  colSpan?: number;
  rowSpan?: number;
  clock?: ScreenSaverRawClock;
  photo?: ScreenSaverRawPhoto;
}

export interface ScreenSaverRawPage {
  id?: string;
  name?: string;
  cards?: ScreenSaverRawCard[];
  ambientColor?: string;
}

export interface ScreenSaverRawSettings {
  dimEnabled?: boolean;
  dimDelaySec?: number;
  dimBrightness?: number;
  ambientColorEnabled?: boolean;
}

export interface ScreenSaverRawConfig {
  schemaVersion?: number;
  settings?: ScreenSaverRawSettings;
  pages?: ScreenSaverRawPage[];
}
