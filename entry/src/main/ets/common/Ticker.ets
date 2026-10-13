/**
 * =============================================================================
 * 全局心跳定时器（Ticker.ets）
 * =============================================================================
 *
 * 【这个文件是干什么的】
 * 一个「单例」的统一时钟心跳服务：时钟卡片每分钟要刷新时间、开了「显示秒」
 * 要每秒刷新——这些定时刷新统统注册到这里，由它统一管理 setTimeout。
 *
 * 【为什么要集中管理，而不是每个组件自己 setInterval】
 * 1. 省电：屏保的场景是「长时间挂在屏幕上」，如果时钟、秒、其它组件各自
 *    起定时器，会唤醒 CPU 多次。集中后全场只有一个定时器在跑。
 * 2. 按需降频：只要没有任何监听者声明「我需要秒级刷新」，就自动按「分钟」
 *    跳动，并且把触发时刻对齐到整分钟边界（见 reschedule 的说明）。
 * 3. 前后台联动：应用退到后台时统一停表，回到前台统一恢复并立即补一次
 *    刷新，避免出现「回前台后时间停留在旧值」的问题。
 * =============================================================================
 */

import { ScreenSaverLogger } from './Logger';

/**
 * 心跳监听者需要实现的接口。
 * 为什么用「对象接口」而不是只传一个回调函数：
 * 除了每跳一次要回调（onTick），还需要在排定时器前询问「你要不要秒级刷新」
 * （needsSecondTick），两个方法打包成一个对象，注册/注销时也只传一个参数。
 */
export interface ScreenSaverTickListener {
  /** 每次心跳触发时回调（秒级或分钟级，取决于整体需求）。 */
  onTick: () => void;
  /** 声明自己是否需要每秒跳一次（如时钟开了「显示秒」）。 */
  needsSecondTick: () => boolean;
}

// 两种基础间隔：1 秒 / 1 分钟（毫秒）。
const SCREEN_SAVER_SECOND_INTERVAL_MS: number = 1000;
const SCREEN_SAVER_MINUTE_INTERVAL_MS: number = 60000;

/**
 * 心跳服务类。不直接导出类本身，而是导出下方唯一的实例（单例模式）——
 * 保证全应用共享同一份 listeners 和 timer，否则就会出现多个定时器各跳各的。
 */
class ScreenSaverTickerService {
  /** 已注册的监听者列表（时钟卡片、预览里的时钟等）。 */
  private listeners: ScreenSaverTickListener[] = [];
  /** 当前 setTimeout 的句柄，-1 表示没有排定的任务。 */
  private timerId: number = -1;
  /** 应用是否在前台。后台时挂起心跳，省电。 */
  private appActive: boolean = true;

  /** 注册监听者并立即重排定时器（可能因新成员需要秒级而升级为秒表）。 */
  addListener(listener: ScreenSaverTickListener): void {
    this.listeners.push(listener);
    this.reschedule();
  }

  /** 注销监听者（组件 aboutToDisappear 时必须调用，否则会内存泄漏）。 */
  removeListener(listener: ScreenSaverTickListener): void {
    const index = this.listeners.indexOf(listener);
    if (index >= 0) {
      this.listeners.splice(index, 1);
      this.reschedule();
    }
  }

  /**
   * 前后台切换时由 EntryAbility 调用。
   * 回前台时先手动 fire() 一次：因为后台期间心跳停了，
   * 不补一次的话页面会显示旧时间，要等到下一跳才纠正。
   */
  setAppActive(active: boolean): void {
    if (this.appActive === active) {
      return; // 状态没变就不做任何事，避免重复日志和多余刷新
    }
    this.appActive = active;
    ScreenSaverLogger.info(`ticker app active: ${active}`);
    if (active && this.listeners.length > 0) {
      this.fire();
    }
    this.reschedule();
  }

  /** 查询当前是否在前台心跳中。相册卡片用它判断「还该不该自动轮播」。 */
  isActive(): boolean {
    return this.appActive;
  }

  /**
   * 核心：重排下一次心跳。任何变化（增删监听者、前后台切换、秒级需求变化）
   * 之后都要调用。逻辑：
   * 1. 没人听 / 在后台 → 什么都不排，心跳彻底停掉（最省电）。
   * 2. 只要有一个人要秒级 → 每秒一跳。
   * 3. 否则 → 按分钟跳，且对齐整分钟边界：
   *    假设现在是 10:07:23，我们希望 10:08:00 整准时跳（时钟分针变化的那一刻），
   *    所以延迟 = 60000 - 已过的秒毫秒 + 30ms（留一点提前量，防止系统定时器
   *    偏慢导致刚好卡在 59.999s 又跳一次的错误）。
   */
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
        this.reschedule(); // 跳完再排下一次（自续期）
      }, SCREEN_SAVER_SECOND_INTERVAL_MS);
    } else {
      const now = new Date();
      // 当前这一分钟已经流走了多少毫秒：秒*1000 + 毫秒
      const elapsed = now.getSeconds() * 1000 + now.getMilliseconds();
      const delay = Math.max(50, SCREEN_SAVER_MINUTE_INTERVAL_MS - elapsed + 30);
      this.timerId = setTimeout((): void => {
        this.fire();
        this.reschedule();
      }, delay);
    }
  }

  /** 取消已排定的定时任务。 */
  private stopTimer(): void {
    if (this.timerId >= 0) {
      clearTimeout(this.timerId);
      this.timerId = -1;
    }
  }

  /** 触发一次心跳：通知所有监听者。 */
  private fire(): void {
    for (const listener of this.listeners) {
      listener.onTick();
    }
  }
}

// 导出全局唯一实例。整个应用 import 的是同一个对象（单例）。
export const screenSaverTicker: ScreenSaverTickerService = new ScreenSaverTickerService();
