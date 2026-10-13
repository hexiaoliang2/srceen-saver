/**
 * =============================================================================
 * 全局字号缩放控制（FontScale.ets）
 * =============================================================================
 *
 * 【这个文件是干什么的】
 * 控制整个应用的字号是否跟随系统设置的「字体大小」。
 * 用户可以在时钟卡片设置里选择「跟随系统」或锁定某个字号档。
 *
 * 【实现方式】
 * 鸿蒙的 ApplicationContext.setFontSizeScale(value) 可以给整个应用
 * 强制设置一个字号缩放系数（1 = 标准大小）。
 *   - followSystem = true：读取系统当前配置里的 fontSizeScale 并应用；
 *     拿不到或非法（<=0）时退回 1，保证永远有一个有效值。
 *   - followSystem = false：强制设为 1（标准大小），屏保布局不会被
 *     系统大字号撑乱。
 * =============================================================================
 */

import { common } from '@kit.AbilityKit';
import { ScreenSaverLogger } from './Logger';

/**
 * 应用字号缩放。
 * 注意要用 ApplicationContext（应用级）而不是 Activity 的 context——
 * 这样设置对整个应用生效，而不是只对单个页面。
 */
export function screenSaverApplyFontScale(context: common.UIAbilityContext, followSystem: boolean): void {
  try {
    const appContext = context.getApplicationContext();
    if (followSystem) {
      // fontSizeScale 的类型是 number | undefined：必须先判 undefined。
      const scale = context.config.fontSizeScale;
      const value = (scale !== undefined && scale > 0) ? scale : 1;
      appContext.setFontSizeScale(value);
      ScreenSaverLogger.info(`font scale apply follow system: ${value}`);
    } else {
      appContext.setFontSizeScale(1);
      ScreenSaverLogger.info('font scale apply locked at 1');
    }
  } catch (err) {
    const error = err as Error;
    // 字号设置失败不影响使用，只记日志。
    ScreenSaverLogger.warn(`font scale apply failed: ${error.message}`);
  }
}
