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
import { ScreenSaverOrientation } from '../model/ConfigModels';

// 退出屏保时要恢复显示的系统栏：状态栏 + 导航栏。
const SCREEN_SAVER_SYSTEM_BARS: Array<'status' | 'navigation'> = ['status', 'navigation'];

/** 屏保内容需要避让的窗口区域（px；调用方换算成 vp 后作为内边距）。 */
export interface ScreenSaverWindowInsets {
  left: number;
  top: number;
  right: number;
  bottom: number;
}

/** 零内边距（拿不到窗口时兜底）。 */
export function screenSaverZeroInsets(): ScreenSaverWindowInsets {
  const zero: ScreenSaverWindowInsets = { left: 0, top: 0, right: 0, bottom: 0 };
  return zero;
}

class ScreenSaverWindowController {
  /** 缓存主窗口实例，避免每次都查询（查询是异步的，有开销）。 */
  private mainWindow: window.Window | undefined = undefined;

  /**
   * 进入屏保：接管窗口。
   * @param keepScreenOn 是否保持屏幕常亮（用户开了「常亮」设置才传 true）
   * @param mode 本次屏保方向（竖屏锁 PORTRAIT，横屏锁 LANDSCAPE）
   */
  async enter(context: common.Context, keepScreenOn: boolean,
    mode: ScreenSaverOrientation = ScreenSaverOrientation.Portrait): Promise<void> {
    const target = await this.getWindow(context);
    if (target === undefined) {
      return;
    }
    await this.safeCall((): Promise<void> => target.setWindowLayoutFullScreen(true), 'setWindowLayoutFullScreen(true)');
    await this.safeCall((): Promise<void> => target.setWindowSystemBarEnable([]), 'setWindowSystemBarEnable([])');
    // 先切方向：主页会在 push 屏保页之前调用 applyOrientation 预检，
    // 这里再设一次是为了保证「直接进屏保」的路径也一定是正确方向。
    const orientationOk = await this.applyOrientation(context, mode);
    if (!orientationOk) {
      ScreenSaverLogger.warn(`window enter: orientation apply failed (${mode})`);
    }
    if (keepScreenOn) {
      await this.safeCall((): Promise<void> => target.setWindowKeepScreenOn(true), 'setWindowKeepScreenOn(true)');
    }
    // -1 = 使用系统默认/自动亮度
    await this.safeCall((): Promise<void> => target.setWindowBrightness(-1), 'setWindowBrightness(-1)');
    ScreenSaverLogger.info(`window enter: immersive ${mode}, keepScreenOn=${keepScreenOn}, ` +
      `orientationOk=${orientationOk}`);
  }

  /**
   * 获取横屏/竖屏内容需要避让的安全区（刘海、底部导航条），单位 px。
   * 只取 CUTOUT 与底部导航指示条：状态栏/导航栏在屏保里已经隐藏，
   * 若把 TYPE_SYSTEM 也算进来会在隐藏后多出一块空白。
   */
  async getContentInsets(context: common.Context): Promise<ScreenSaverWindowInsets> {
    const zero = screenSaverZeroInsets();
    const target = await this.getWindow(context);
    if (target === undefined) {
      return zero;
    }
    try {
      const cutout = target.getWindowAvoidArea(window.AvoidAreaType.TYPE_CUTOUT);
      let bottom = 0;
      try {
        const navIndicator = target.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
        bottom = Math.max(0, navIndicator.bottomRect.height);
      } catch (navError) {
        bottom = 0;
      }
      // 横屏时顶部不内缩：卡片需要从屏幕最顶端开始铺满；
      // 刘海通常落在左右侧，用 left/right 避让即可。
      const insets: ScreenSaverWindowInsets = {
        left: Math.max(0, cutout.leftRect.width),
        top: 0,
        right: Math.max(0, cutout.rightRect.width),
        bottom: bottom
      };
      return insets;
    } catch (err) {
      const error = err as Error;
      ScreenSaverLogger.warn(`getWindowAvoidArea failed: ${error.message}`);
      return zero;
    }
  }

  /**
   * 只切换窗口方向（进入屏保前的前置步骤）。
   * 返回 false 时调用方必须留在首页并提示原因，不能继续 push 屏保页。
   */
  async applyOrientation(context: common.Context, mode: ScreenSaverOrientation): Promise<boolean> {
    const target = await this.getWindow(context);
    if (target === undefined) {
      return false;
    }
    const orientation = mode === ScreenSaverOrientation.Landscape ?
      window.Orientation.LANDSCAPE : window.Orientation.PORTRAIT;
    return await this.safeCall((): Promise<void> => target.setPreferredOrientation(orientation),
      `setPreferredOrientation(${mode})`);
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
