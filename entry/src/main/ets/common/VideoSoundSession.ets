/**
 * =============================================================================
 * 视频卡声音会话（VideoSoundSession.ets）
 * =============================================================================
 *
 * 运行时唯一的“哪张视频卡有声”状态：
 *   · 只存在内存里，不写 Preferences、不跨会话记忆；
 *   · activeCardId 为空 = 全部静音；
 *   · 开启某卡时直接覆盖 activeCardId，另一张卡读到的 soundEnabled 立即变 false，
 *     图标与 Video.muted 同步更新；
 *   · reset() 是四种静音触发情形的唯一入口（页面/卡片只调用它，不各写一套）。
 *
 * @ObservedV2 + @Trace 让所有视频卡共享同一份可观察状态。
 * =============================================================================
 */

import { ScreenSaverLogger } from './Logger';

@ObservedV2
export class ScreenSaverVideoSoundSession {
  /** 当前允许出声的卡片 id；空串表示全部静音。 */
  @Trace activeCardId: string = '';
  /** 重置代数：即使 activeCardId 本来就是空，也能驱动依赖方重新同步图标。 */
  @Trace resetEpoch: number = 0;

  /** 请求某卡成为唯一出声卡；不持久化。 */
  request(cardId: string): void {
    if (cardId.length === 0) {
      return;
    }
    if (this.activeCardId !== cardId) {
      ScreenSaverLogger.info(`video sound exclusive: ${this.activeCardId} -> ${cardId}`);
      this.activeCardId = cardId;
    }
  }

  /** 用户关闭当前卡声音。 */
  disable(cardId: string): void {
    if (this.activeCardId === cardId) {
      this.reset('user-mute');
    }
  }

  /** 某卡是否处于唯一出声态。 */
  isActive(cardId: string): boolean {
    return this.activeCardId.length > 0 && this.activeCardId === cardId;
  }

  /**
   * 集中重置：清空唯一出声卡并递增代数。
   * 调用点只应包括：前后台、设置页往返、卡片重绘、遮盖切换。
   */
  reset(reason: string): void {
    if (this.activeCardId.length > 0) {
      ScreenSaverLogger.info(`video sound reset: reason=${reason} card=${this.activeCardId}`);
    }
    this.activeCardId = '';
    this.resetEpoch = this.resetEpoch + 1;
  }
}

export const screenSaverVideoSoundSession: ScreenSaverVideoSoundSession =
  new ScreenSaverVideoSoundSession();
