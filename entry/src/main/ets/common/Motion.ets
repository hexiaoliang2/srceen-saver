/**
 * =============================================================================
 * 动效工具（Motion.ets）
 * =============================================================================
 *
 * 【这个文件是干什么的】
 * 集中定义全应用所有动画的时长（毫秒），并提供一组「动效开关」函数：
 * 用户在设置里关掉「动效」（motionDisabled）之后，所有动画会自动缩短或消失。
 *
 * 【为什么要集中定义时长常量】
 * 1. 风格统一：同类交互（如各种面板的进出）共用同一个时长，视觉上更协调。
 * 2. 一处调整全局生效：想整体调快/调慢节奏，只改这里即可。
 *
 * 【为什么关动效后不直接返回 0，而是「压缩到 ≤100ms」】
 * 完全去掉动画会让状态变化显得「跳变生硬」，对位置类动画（如卡片吸附 snap）
 * 还可能让用户看不清结果。所以策略分三档：
 * - 时长类（duration）：压缩到最多 100ms —— 保留一点点过渡感；
 * - 淡入淡出类（fade）：直接归零 —— 淡入淡出本来就只是装饰；
 * - 特定动画（snap / bounce）：直接归零。
 * =============================================================================
 */

// 全局唯一的数据模型（里面存着用户是否关闭了动效）。
import { screenSaverAppModel } from '../model/AppModel';

// ---------- 以下是全应用统一的动画时长（毫秒） ----------
export const SCREEN_SAVER_MOTION_PAGE_TRANSITION_MS: number = 300; // 页面路由切换
export const SCREEN_SAVER_MOTION_ENTER_MS: number = 300;          // 屏保进入动画
export const SCREEN_SAVER_MOTION_EXIT_MS: number = 250;           // 屏保退出动画
export const SCREEN_SAVER_MOTION_EDIT_ENTER_MS: number = 250;     // 编辑模式进入
export const SCREEN_SAVER_MOTION_CAPSULE_MS: number = 200;        // 胶囊按钮显隐
export const SCREEN_SAVER_MOTION_SHEET_MS: number = 300;          // 半模态面板弹出
export const SCREEN_SAVER_MOTION_SNAP_MS: number = 150;           // 卡片拖拽后吸附归位
export const SCREEN_SAVER_MOTION_BOUNCE_MS: number = 200;         // 非法操作时的弹回动画
export const SCREEN_SAVER_MOTION_PHOTO_FADE_MS: number = 250;     // 照片轮播淡入淡出
export const SCREEN_SAVER_MOTION_PREVIEW_MS: number = 150;        // 预览小窗动画
export const SCREEN_SAVER_MOTION_TOAST_MS: number = 200;          // 提示条进出
export const SCREEN_SAVER_MOTION_GIT_SPIN_MS: number = 600;       // Git 卡片刷新旋转
export const SCREEN_SAVER_MOTION_AMBIENT_MS: number = 800;        // 环境光晕过渡
// 关闭动效后，任何动画允许保留的最大时长（见 screenSaverMotionDuration）。
export const SCREEN_SAVER_REDUCED_MOTION_MAX_MS: number = 100;

/** 读取用户是否关闭了动效（设置项存在 AppModel 里）。 */
export function screenSaverMotionOff(): boolean {
  return screenSaverAppModel.layout.settings.motionDisabled;
}

/**
 * 计算某个「时长类」动画的实际时长：
 * - 开着动效 → 原样返回；
 * - 关掉动效 → 压缩到最多 100ms（保留一丝过渡感，避免画面生硬跳变）。
 */
export function screenSaverMotionDuration(baseMs: number): number {
  if (!screenSaverMotionOff()) {
    return baseMs;
  }
  if (baseMs <= 0) {
    return 0;
  }
  return Math.min(baseMs, SCREEN_SAVER_REDUCED_MOTION_MAX_MS);
}

/**
 * 计算某个「淡入淡出类」动画的实际时长：关动效时直接归零。
 * 淡入淡出纯属装饰，去掉不影响信息传达，所以比时长类更激进。
 */
export function screenSaverFadeDuration(baseMs: number): number {
  if (!screenSaverMotionOff()) {
    return baseMs;
  }
  return 0;
}

/** 卡片吸附动画时长：关动效时瞬间归位（拖拽结果必须立刻可见）。 */
export function screenSaverSnapDuration(): number {
  if (screenSaverMotionOff()) {
    return 0;
  }
  return SCREEN_SAVER_MOTION_SNAP_MS;
}

/** 弹回动画时长：关动效时不弹。 */
export function screenSaverBounceDuration(): number {
  if (screenSaverMotionOff()) {
    return 0;
  }
  return SCREEN_SAVER_MOTION_BOUNCE_MS;
}
