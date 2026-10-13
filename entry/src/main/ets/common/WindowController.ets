/**
 * =============================================================================
 * 窗口控制器（WindowController.ets）
 * =============================================================================
 *
 * 【这个文件是干什么的】
 * 统一管理屏保对「系统窗口」的所有改动：进入屏保时把窗口变成
 * 全屏沉浸 + 隐藏状态栏导航栏 + 竖屏锁定 + 保持常亮；
 * 退出屏保时把这些状态全部还原，把窗口还给系统。
 *
 * 【为什么必须「进入改、退出还原」】
 * 屏保是一种「临时接管整块屏幕」的形态。如果进入时改了窗口状态、
 * 退出时不还原，用户回到桌面/其它应用会发现状态栏不见了、屏幕永远常亮——
 * 这属于严重的体验事故，所以 exit() 里逐项恢复。
 *
 * 【为什么要 safeCall 包一层】
 * 每个窗口 API 都可能失败（比如模拟器不支持某些能力）。任何一项失败
 * 都不该中断后续步骤（亮度没设置成功不影响沉浸模式），所以逐项 try/catch、
 * 记日志、继续执行。
 *
 * 【关键 API 说明】
 * - setWindowLayoutFullScreen：内容延伸到状态栏/导航栏底下（沉浸式）。
 * - setWindowSystemBarEnable([])：隐藏状态栏和导航栏；传回数组即恢复。
 * - setPreferredOrientation：锁定屏幕方向。PORTRAIT 锁竖屏，UNSPECIFIED
 *   解锁（恢复跟随系统）。注意这个 API 挂在 window.Window 实例上。
 * - setWindowKeepScreenOn：保持屏幕常亮（屏保的核心能力之一）。
 * - setWindowBrightness(-1)：-1 表示亮度交还给「系统自动亮度」，
 *   进入和退出都设一次，避免残留手动亮度。
 * =============================================================================
 */

import { window } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { ScreenSaverLogger } from './Logger';

// 退出屏保时要恢复显示的系统栏：状态栏 + 导航栏。
const SCREEN_SAVER_SYSTEM_BARS: Array<'status' | 'navigation'> = ['status', 'navigation'];

class ScreenSaverWindowController {
  /** 缓存主窗口实例，避免每次都查询（查询是异步的，有开销）。 */
  private mainWindow: window.Window | undefined = undefined;

  /**
   * 进入屏保：接管窗口。
   * @param keepScreenOn 是否保持屏幕常亮（用户开了「常亮」设置才传 true）
   */
  async enter(context: common.Context, keepScreenOn: boolean): Promise<void> {
    const target = await this.getWindow(context);
    if (target === undefined) {
      return;
    }
    await this.safeCall((): Promise<void> => target.setWindowLayoutFullScreen(true), 'setWindowLayoutFullScreen(true)');
    await this.safeCall((): Promise<void> => target.setWindowSystemBarEnable([]), 'setWindowSystemBarEnable([])');
    // 竖屏锁定：屏保的网格布局是按竖屏设计的，横屏会错乱。
    await this.safeCall((): Promise<void> => target.setPreferredOrientation(window.Orientation.PORTRAIT),
      'setPreferredOrientation(PORTRAIT)');
    if (keepScreenOn) {
      await this.safeCall((): Promise<void> => target.setWindowKeepScreenOn(true), 'setWindowKeepScreenOn(true)');
    }
    // -1 = 使用系统默认/自动亮度
    await this.safeCall((): Promise<void> => target.setWindowBrightness(-1), 'setWindowBrightness(-1)');
    ScreenSaverLogger.info(`window enter: immersive portrait, keepScreenOn=${keepScreenOn}`);
  }

  /** 退出屏保：逐项还原窗口状态（沉浸、常亮、方向、亮度、系统栏）。 */
  async exit(context: common.Context): Promise<void> {
    const target = await this.getWindow(context);
    if (target === undefined) {
      return;
    }
    await this.safeCall((): Promise<void> => target.setWindowLayoutFullScreen(false), 'setWindowLayoutFullScreen(false)');
    await this.safeCall((): Promise<void> => target.setWindowKeepScreenOn(false), 'setWindowKeepScreenOn(false)');
    // 解除竖屏锁定，恢复跟随系统/传感器。
    await this.safeCall((): Promise<void> => target.setPreferredOrientation(window.Orientation.UNSPECIFIED),
      'setPreferredOrientation(UNSPECIFIED)');
    await this.safeCall((): Promise<void> => target.setWindowBrightness(-1), 'setWindowBrightness(-1)');
    await this.safeCall((): Promise<void> => target.setWindowSystemBarEnable(SCREEN_SAVER_SYSTEM_BARS),
      'setWindowSystemBarEnable(system bars)');
    ScreenSaverLogger.info('window exit: state restored');
  }

  /** 单独设置窗口亮度（深色模式下屏保可调暗屏幕进一步省电）。 */
  async setBrightness(context: common.Context, value: number): Promise<void> {
    const target = await this.getWindow(context);
    if (target === undefined) {
      return;
    }
    await this.safeCall((): Promise<void> => target.setWindowBrightness(value), `setWindowBrightness(${value})`);
  }

  /**
   * 获取主窗口实例（带缓存）。
   * getLastWindow 是异步 API 必须 await；失败时清空缓存并返回 undefined，
   * 调用方拿到 undefined 直接放弃本次窗口操作即可。
   */
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

  /**
   * 安全执行一个窗口操作：成功返回 true，失败记日志返回 false。
   * 把 try/catch 收口到这一个问题里，enter/exit 的代码保持整洁。
   */
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

// 导出全局唯一实例（单例），窗口缓存因此全局共享。
export const screenSaverWindowController: ScreenSaverWindowController = new ScreenSaverWindowController();
