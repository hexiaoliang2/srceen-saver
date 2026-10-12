import { mediaquery } from '@kit.ArkUI';
import { ScreenSaverLogger } from './Logger';
import {
  SCREEN_SAVER_BREAKPOINT_FOLD_VP,
  SCREEN_SAVER_BREAKPOINT_TABLET_VP,
  SCREEN_SAVER_GRID_COLS,
  SCREEN_SAVER_GRID_ROWS,
  SCREEN_SAVER_WIDE_COLS_FOLD,
  SCREEN_SAVER_WIDE_COLS_TABLET,
  SCREEN_SAVER_WIDE_ROWS_FOLD,
  SCREEN_SAVER_WIDE_ROWS_TABLET
} from '../model/ConfigModels';

export interface ScreenSaverBreakpoint {
  columns: number;
  rows: number;
  isWide: boolean;
}

export type ScreenSaverBreakpointListener = (value: ScreenSaverBreakpoint) => void;

export type ScreenSaverMediaQueryFactory = (condition: string) => mediaquery.MediaQueryListener;

export function screenSaverBreakpointForWidth(widthVp: number): ScreenSaverBreakpoint {
  if (widthVp >= SCREEN_SAVER_BREAKPOINT_TABLET_VP) {
    const tablet: ScreenSaverBreakpoint = {
      columns: SCREEN_SAVER_WIDE_COLS_TABLET,
      rows: SCREEN_SAVER_WIDE_ROWS_TABLET,
      isWide: true
    };
    return tablet;
  }
  if (widthVp >= SCREEN_SAVER_BREAKPOINT_FOLD_VP) {
    const fold: ScreenSaverBreakpoint = {
      columns: SCREEN_SAVER_WIDE_COLS_FOLD,
      rows: SCREEN_SAVER_WIDE_ROWS_FOLD,
      isWide: true
    };
    return fold;
  }
  const phone: ScreenSaverBreakpoint = {
    columns: SCREEN_SAVER_GRID_COLS,
    rows: SCREEN_SAVER_GRID_ROWS,
    isWide: false
  };
  return phone;
}

export class ScreenSaverBreakpointObserver {
  private tabletListener: mediaquery.MediaQueryListener | undefined = undefined;
  private foldListener: mediaquery.MediaQueryListener | undefined = undefined;
  private onTablet: boolean = false;
  private onFold: boolean = false;
  private callback: ScreenSaverBreakpointListener | undefined = undefined;

  start(factory: ScreenSaverMediaQueryFactory, callback: ScreenSaverBreakpointListener): void {
    this.stop();
    this.callback = callback;
    try {
      this.tabletListener = factory(`(width>=${SCREEN_SAVER_BREAKPOINT_TABLET_VP}vp)`);
      this.foldListener = factory(
        `(width>=${SCREEN_SAVER_BREAKPOINT_FOLD_VP}vp) and (width<${SCREEN_SAVER_BREAKPOINT_TABLET_VP}vp)`);
      this.onTablet = this.tabletListener.matches;
      this.onFold = this.foldListener.matches;
      this.tabletListener.on('change', (result: mediaquery.MediaQueryResult): void => {
        this.onTablet = result.matches;
        this.emit();
      });
      this.foldListener.on('change', (result: mediaquery.MediaQueryResult): void => {
        this.onFold = result.matches;
        this.emit();
      });
      this.emit();
    } catch (err) {
      const error = err as Error;
      ScreenSaverLogger.warn(`media query failed: ${error.message}`);
      this.emitFallback();
    }
  }

  stop(): void {
    if (this.tabletListener !== undefined) {
      try {
        this.tabletListener.off('change');
      } catch (err) {
        ScreenSaverLogger.warn('media query off failed');
      }
      this.tabletListener = undefined;
    }
    if (this.foldListener !== undefined) {
      try {
        this.foldListener.off('change');
      } catch (err) {
        ScreenSaverLogger.warn('media query off failed');
      }
      this.foldListener = undefined;
    }
  }

  private emit(): void {
    if (this.callback === undefined) {
      return;
    }
    let value: ScreenSaverBreakpoint;
    if (this.onTablet) {
      value = screenSaverBreakpointForWidth(SCREEN_SAVER_BREAKPOINT_TABLET_VP);
    } else if (this.onFold) {
      value = screenSaverBreakpointForWidth(SCREEN_SAVER_BREAKPOINT_FOLD_VP);
    } else {
      value = screenSaverBreakpointForWidth(0);
    }
    this.callback(value);
  }

  private emitFallback(): void {
    if (this.callback === undefined) {
      return;
    }
    this.callback(screenSaverBreakpointForWidth(0));
  }
}
