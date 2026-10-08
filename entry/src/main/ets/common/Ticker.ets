import { ScreenSaverLogger } from './Logger';

export interface ScreenSaverTickListener {
  onTick: () => void;
  needsSecondTick: () => boolean;
}

const SCREEN_SAVER_SECOND_INTERVAL_MS: number = 1000;
const SCREEN_SAVER_MINUTE_INTERVAL_MS: number = 60000;

class ScreenSaverTickerService {
  private listeners: ScreenSaverTickListener[] = [];
  private timerId: number = -1;
  private appActive: boolean = true;

  addListener(listener: ScreenSaverTickListener): void {
    this.listeners.push(listener);
    this.reschedule();
  }

  removeListener(listener: ScreenSaverTickListener): void {
    const index = this.listeners.indexOf(listener);
    if (index >= 0) {
      this.listeners.splice(index, 1);
      this.reschedule();
    }
  }

  setAppActive(active: boolean): void {
    if (this.appActive === active) {
      return;
    }
    this.appActive = active;
    ScreenSaverLogger.info(`ticker app active: ${active}`);
    if (active && this.listeners.length > 0) {
      this.fire();
    }
    this.reschedule();
  }

  isActive(): boolean {
    return this.appActive;
  }

  reschedule(): void {
    this.stopTimer();
    if (!this.appActive || this.listeners.length === 0) {
      return;
    }
    let needsSecond = false;
    for (const listener of this.listeners) {
      if (listener.needsSecondTick()) {
        needsSecond = true;
        break;
      }
    }
    if (needsSecond) {
      this.timerId = setTimeout((): void => {
        this.fire();
        this.reschedule();
      }, SCREEN_SAVER_SECOND_INTERVAL_MS);
    } else {
      const now = new Date();
      const elapsed = now.getSeconds() * 1000 + now.getMilliseconds();
      const delay = Math.max(50, SCREEN_SAVER_MINUTE_INTERVAL_MS - elapsed + 30);
      this.timerId = setTimeout((): void => {
        this.fire();
        this.reschedule();
      }, delay);
    }
  }

  private stopTimer(): void {
    if (this.timerId >= 0) {
      clearTimeout(this.timerId);
      this.timerId = -1;
    }
  }

  private fire(): void {
    for (const listener of this.listeners) {
      listener.onTick();
    }
  }
}

export const screenSaverTicker: ScreenSaverTickerService = new ScreenSaverTickerService();
