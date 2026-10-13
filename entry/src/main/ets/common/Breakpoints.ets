/**
 * =============================================================================
 * 断点（屏幕尺寸分级）工具（Breakpoints.ets）
 * =============================================================================
 *
 * 【这个文件是干什么的】
 * 根据屏幕宽度把设备分成三档（断点），并告诉屏保网格该用多少行/列：
 *   - 手机（< 600vp）        → 4 列 × 8 行（紧凑）
 *   - 折叠屏展开（≥ 600vp）   → 8 列 × 8 行（宽屏）
 *   - 平板（≥ 840vp）        → 12 列 × 7 行（宽屏）
 *
 * 【为什么要分档】
 * 屏保的卡片布局基于「网格」。手机竖屏窄，4 列刚好；平板很宽，还是 4 列的话
 * 每个格子会被拉得巨大、很难看。所以按宽度切换网格规格，同一份布局代码
 * 在不同设备上都能好看。
 *
 * 【实现方式：媒体查询（mediaquery）】
 * 鸿蒙提供 mediaquery 能力监听「窗口宽度条件」是否成立。这里同时注册两条：
 *   (width>=840vp)                        → 是否处于平板档
 *   (width>=600vp) and (width<840vp)      → 是否处于折叠屏档
 * 窗口尺寸变化（旋转、折叠屏开合）时系统会回调，我们再把最新断点通知给页面。
 *
 * 【为什么要传一个 factory（工厂函数）而不是直接调 mediaquery.matchMediaSync】
 * 方便单元测试：测试时可以传一个假的 factory，不用真开窗口。这是一种
 * 「依赖注入」的写法——被依赖的对象由调用方提供，而不是写死在内部。
 * =============================================================================
 */

import { mediaquery } from '@kit.ArkUI';
import { ScreenSaverLogger } from './Logger';
// 各档位的宽度阈值和网格规格常量统一放在 ConfigModels 里，方便和其它配置一起维护。
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

/** 一档断点：网格列数、行数，以及是否属于「宽屏」形态。 */
export interface ScreenSaverBreakpoint {
  columns: number;
  rows: number;
  isWide: boolean;
}

/** 断点变化时的回调类型：拿到最新的断点信息。 */
export type ScreenSaverBreakpointListener = (value: ScreenSaverBreakpoint) => void;

/** 媒体查询监听器的工厂类型：传入条件字符串，返回一个可监听的 MediaQueryListener。 */
export type ScreenSaverMediaQueryFactory = (condition: string) => mediaquery.MediaQueryListener;

/**
 * 纯计算函数：给定宽度（vp），算出对应的断点。
 * 「只看宽度」是刻意的——本应用竖屏锁定使用，高度不参与分档。
 * 从大到小依次判断，命中即返回。
 */
export function screenSaverBreakpointForWidth(widthVp: number): ScreenSaverBreakpoint {
  // 平板档：≥ 840vp，12 列 7 行
  if (widthVp >= SCREEN_SAVER_BREAKPOINT_TABLET_VP) {
    const tablet: ScreenSaverBreakpoint = {
      columns: SCREEN_SAVER_WIDE_COLS_TABLET,
      rows: SCREEN_SAVER_WIDE_ROWS_TABLET,
      isWide: true
    };
    return tablet;
  }
  // 折叠屏展开档：≥ 600vp，8 列 8 行
  if (widthVp >= SCREEN_SAVER_BREAKPOINT_FOLD_VP) {
    const fold: ScreenSaverBreakpoint = {
      columns: SCREEN_SAVER_WIDE_COLS_FOLD,
      rows: SCREEN_SAVER_WIDE_ROWS_FOLD,
      isWide: true
    };
    return fold;
  }
  // 默认手机档：4 列 8 行
  const phone: ScreenSaverBreakpoint = {
    columns: SCREEN_SAVER_GRID_COLS,
    rows: SCREEN_SAVER_GRID_ROWS,
    isWide: false
  };
  return phone;
}

/**
 * 断点观察者：真正去监听窗口宽度变化的类。
 * 用法（见 ScreensaverPage）：new 一个实例 → start(...) 开始监听 →
 * 组件销毁前 stop() 注销，防止内存泄漏。
 */
export class ScreenSaverBreakpointObserver {
  /** 平板档媒体查询监听器（undefined = 未注册）。 */
  private tabletListener: mediaquery.MediaQueryListener | undefined = undefined;
  /** 折叠屏档媒体查询监听器。 */
  private foldListener: mediaquery.MediaQueryListener | undefined = undefined;
  /** 当前是否处于平板档宽度。 */
  private onTablet: boolean = false;
  /** 当前是否处于折叠屏档宽度。 */
  private onFold: boolean = false;
  /** 断点变化时要通知的回调。 */
  private callback: ScreenSaverBreakpointListener | undefined = undefined;

  /**
   * 开始监听。
   * 先 stop() 是防御性写法：避免重复 start 时注册两套监听器造成重复回调。
   * 每条查询都通过 on('change') 订阅变化；注册完立即 emit() 一次，
   * 让调用方马上拿到当前断点（不用等第一次宽度变化）。
   * 任何异常（如系统不支持）都兜底降级到手机档，保证功能可用。
   */
  start(factory: ScreenSaverMediaQueryFactory, callback: ScreenSaverBreakpointListener): void {
    this.stop();
    this.callback = callback;
    try {
      this.tabletListener = factory(`(width>=${SCREEN_SAVER_BREAKPOINT_TABLET_VP}vp)`);
      this.foldListener = factory(
        `(width>=${SCREEN_SAVER_BREAKPOINT_FOLD_VP}vp) and (width<${SCREEN_SAVER_BREAKPOINT_TABLET_VP}vp)`);
      // matches 表示「当前时刻条件是否成立」，用来初始化两个档位标记。
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

  /** 停止监听并释放资源。off('change') 失败只记日志，不影响流程。 */
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

  /**
   * 根据两个档位标记算出当前断点并回调。
   * 注意这里没有直接拿「真实宽度」——媒体查询只告诉我们「属于哪一档」，
   * 所以用该档的代表宽度去调 screenSaverBreakpointForWidth 拿规格。
   */
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
      value = screenSaverBreakpointForWidth(0); // 0 必然落到手机档
    }
    this.callback(value);
  }

  /** 异常兜底：媒体查询不可用时，按手机档回调，界面照常可用。 */
  private emitFallback(): void {
    if (this.callback === undefined) {
      return;
    }
    this.callback(screenSaverBreakpointForWidth(0));
  }
}
