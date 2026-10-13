/**
 * =============================================================================
 * 振动反馈工具（VibrationHelper.ets）
 * =============================================================================
 *
 * 【这个文件是干什么的】
 * 在关键交互（长按卡片进入编辑模式）时给一个 30 毫秒的轻微振动，
 * 告诉用户「操作生效了」。这是手机上常见的触觉反馈。
 *
 * 【为什么有一个 failed 标记】
 * 振动失败通常意味着设备/模拟器不支持（比如模拟器没有马达）。
 * 每次都去试只会反复产生失败日志。所以失败一次就把 failed 置为 true，
 * 之后直接跳过——既不刷屏，也不再浪费调用。
 * =============================================================================
 */

import { vibrator } from '@kit.SensorServiceKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { ScreenSaverLogger } from './Logger';

class ScreenSaverVibrationService {
  /** 是否已确认设备不支持振动（失败一次后不再尝试）。 */
  private failed: boolean = false;

  /** 触发一次 30ms 的轻振动（'touch' 档位，强度适合 UI 反馈）。 */
  longPressFeedback(): void {
    if (this.failed) {
      return;
    }
    try {
      // 参数一：time 类型 + 30ms 时长；参数二：usage='touch' 表示触控级轻反馈。
      vibrator.startVibration({
        type: 'time',
        duration: 30
      }, {
        id: 0,
        usage: 'touch'
      }).catch((err: BusinessError): void => {
        // Promise 异步失败（能力不支持等）：标记并静默降级。
        this.failed = true;
        ScreenSaverLogger.warn(`vibration failed: code=${err.code}`);
      });
    } catch (err) {
      // 同步抛错（参数非法等）：同样标记降级。
      const error = err as BusinessError;
      this.failed = true;
      ScreenSaverLogger.warn(`vibration failed: code=${error.code}`);
    }
  }
}

// 导出全局唯一实例（单例），failed 标记因此全局共享。
export const screenSaverVibration: ScreenSaverVibrationService = new ScreenSaverVibrationService();
