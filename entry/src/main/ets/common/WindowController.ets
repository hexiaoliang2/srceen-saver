import { window } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { ScreenSaverLogger } from './Logger';

const SCREEN_SAVER_SYSTEM_BARS: Array<'status' | 'navigation'> = ['status', 'navigation'];

class ScreenSaverWindowController {
  private mainWindow: window.Window | undefined = undefined;

  async enter(context: common.Context): Promise<void> {
    const target = await this.getWindow(context);
    if (target === undefined) {
      return;
    }
    await this.safeCall((): Promise<void> => target.setWindowLayoutFullScreen(true), 'setWindowLayoutFullScreen(true)');
    await this.safeCall((): Promise<void> => target.setWindowSystemBarEnable([]), 'setWindowSystemBarEnable([])');
    await this.safeCall((): Promise<void> => target.setWindowKeepScreenOn(true), 'setWindowKeepScreenOn(true)');
    await this.safeCall((): Promise<void> => target.setWindowBrightness(-1), 'setWindowBrightness(-1)');
    ScreenSaverLogger.info('window enter: immersive + keep screen on');
  }

  async exit(context: common.Context): Promise<void> {
    const target = await this.getWindow(context);
    if (target === undefined) {
      return;
    }
    await this.safeCall((): Promise<void> => target.setWindowLayoutFullScreen(false), 'setWindowLayoutFullScreen(false)');
    await this.safeCall((): Promise<void> => target.setWindowKeepScreenOn(false), 'setWindowKeepScreenOn(false)');
    await this.safeCall((): Promise<void> => target.setWindowBrightness(-1), 'setWindowBrightness(-1)');
    await this.safeCall((): Promise<void> => target.setWindowSystemBarEnable(SCREEN_SAVER_SYSTEM_BARS),
      'setWindowSystemBarEnable(system bars)');
    ScreenSaverLogger.info('window exit: state restored');
  }

  async setBrightness(context: common.Context, value: number): Promise<void> {
    const target = await this.getWindow(context);
    if (target === undefined) {
      return;
    }
    await this.safeCall((): Promise<void> => target.setWindowBrightness(value), `setWindowBrightness(${value})`);
  }

  private async getWindow(context: common.Context): Promise<window.Window | undefined> {
    if (this.mainWindow !== undefined) {
      return this.mainWindow;
    }
    try {
      this.mainWindow = await window.getLastWindow(context);
    } catch (err) {
      const error = err as Error;
      ScreenSaverLogger.error(`getLastWindow failed: ${error.message}`);
      this.mainWindow = undefined;
    }
    return this.mainWindow;
  }

  private async safeCall(action: () => Promise<void>, label: string): Promise<boolean> {
    try {
      await action();
      return true;
    } catch (err) {
      const error = err as Error;
      ScreenSaverLogger.error(`window api failed: ${label}: ${error.message}`);
      return false;
    }
  }
}

export const screenSaverWindowController: ScreenSaverWindowController = new ScreenSaverWindowController();
