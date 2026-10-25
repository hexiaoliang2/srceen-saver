/**
 * =============================================================================
 * 待办卡数据层（TodoViewModel.ets）
 * =============================================================================
 *
 * 零权限、只做自带编辑：
 *   - 新增（最多 60 字）、勾选/取消、删除、手动上移/下移；
 *   - 不做重复规则、不做提醒、不读日历；
 *   - 数据挂在卡片实例的 todo 配置上，随布局持久化，重启不丢；
 *   - todo.version 独立于布局 schemaVersion，便于以后迁移。
 *
 * 【v2 排序状态机】
 *   config.items 永远保持「原始列表顺序」（用户手动排序后的顺序），
 *   每条 item 自身带 orderIndex。屏保展示顺序由
 *   screenSaverTodoDisplayItems() 计算：
 *     · 未完成区：orderIndex 升序；
 *     · 已完成区：completedAt 升序（先完成的在前，新完成的沉底）；
 *     · 全部显示，不限制条数、不折叠。
 *   取消完成只清 completedAt，不改 orderIndex，因此会回到未完成区原位。
 *
 * 所有修改都返回“新的 items 数组”再赋回 config.items：
 * V2 的 @Trace 对数组整体替换的观察最可靠，避免 push/splice 不刷新。
 * =============================================================================
 */

import {
  SCREEN_SAVER_TODO_DATA_VERSION,
  SCREEN_SAVER_TODO_MAX_ITEMS,
  SCREEN_SAVER_TODO_MAX_LEN,
  ScreensaverTodoConfig,
  ScreensaverTodoItem
} from './ConfigModels';
import { screenSaverGenerateId } from './AppModel';

/** 待办统计。 */
export interface ScreensaverTodoSummary {
  total: number;
  done: number;
  open: number;
}

/** 统计未完成/完成/总数。 */
export function screenSaverTodoSummary(config: ScreensaverTodoConfig): ScreensaverTodoSummary {
  let done = 0;
  for (const item of config.items) {
    if (item.completed) {
      done++;
    }
  }
  const summary: ScreensaverTodoSummary = {
    total: config.items.length,
    done: done,
    open: config.items.length - done
  };
  return summary;
}

/** 文本规范化：去首尾空白，按字符数截到 60；空串不新增。 */
export function screenSaverTodoNormalizeText(text: string): string {
  const trimmed = text.trim();
  if (trimmed.length <= SCREEN_SAVER_TODO_MAX_LEN) {
    return trimmed;
  }
  return trimmed.substring(0, SCREEN_SAVER_TODO_MAX_LEN);
}

/** 取当前最大 orderIndex + 1（空列表从 0 开始）。 */
function screenSaverTodoNextOrderIndex(items: ScreensaverTodoItem[]): number {
  let maxIndex = -1;
  for (const item of items) {
    if (item.orderIndex > maxIndex) {
      maxIndex = item.orderIndex;
    }
  }
  return maxIndex + 1;
}

/** 按数组顺序重新编号 orderIndex（0..n-1），保证键稳定且连续。 */
export function screenSaverTodoReindex(config: ScreensaverTodoConfig): void {
  let index = 0;
  for (const item of config.items) {
    item.orderIndex = index;
    index++;
  }
}

/** 新增一条；成功返回空串，失败返回给用户看的原因。 */
export function screenSaverTodoAdd(config: ScreensaverTodoConfig, text: string): string {
  const normalized = screenSaverTodoNormalizeText(text);
  if (normalized.length === 0) {
    return '请输入待办内容';
  }
  if (config.items.length >= SCREEN_SAVER_TODO_MAX_ITEMS) {
    return `最多 ${SCREEN_SAVER_TODO_MAX_ITEMS} 条待办`;
  }
  const item = new ScreensaverTodoItem();
  item.id = screenSaverGenerateId('todo');
  item.text = normalized;
  item.orderIndex = screenSaverTodoNextOrderIndex(config.items);
  item.completed = false;
  item.completedAt = null;
  config.version = SCREEN_SAVER_TODO_DATA_VERSION;
  config.items = config.items.concat([item]);
  return '';
}

/** 删除一条。 */
export function screenSaverTodoRemove(config: ScreensaverTodoConfig, itemId: string): void {
  const next: ScreensaverTodoItem[] = [];
  for (const item of config.items) {
    if (item.id !== itemId) {
      next.push(item);
    }
  }
  config.items = next;
  screenSaverTodoReindex(config);
}

/** 找到一条（找不到返回 undefined）。 */
export function screenSaverTodoFind(config: ScreensaverTodoConfig,
  itemId: string): ScreensaverTodoItem | undefined {
  return config.items.find((item: ScreensaverTodoItem): boolean => item.id === itemId);
}

/**
 * 生成完成时间戳：Date.now()，并保证严格大于当前已完成项的最大值。
 * 这样连续快速完成两条时不会出现相同 completedAt 导致的顺序抖动。
 */
function screenSaverTodoNextCompletedAt(config: ScreensaverTodoConfig): number {
  let maxCompletedAt = 0;
  for (const item of config.items) {
    const value = item.completedAt;
    if (value !== null && value > maxCompletedAt) {
      maxCompletedAt = value;
    }
  }
  const now = Date.now();
  return now > maxCompletedAt ? now : maxCompletedAt + 1;
}

/**
 * 设置完成状态（唯一写入口）。
 * 完成：写 completedAt，条目在展示层沉到已完成区末位；
 * 取消：completedAt 清空，orderIndex 不变，展示层回到未完成区原位。
 */
export function screenSaverTodoSetCompleted(config: ScreensaverTodoConfig, itemId: string,
  completed: boolean): boolean {
  const item = screenSaverTodoFind(config, itemId);
  if (item === undefined || item.completed === completed) {
    return false;
  }
  item.completed = completed;
  item.completedAt = completed ? screenSaverTodoNextCompletedAt(config) : null;
  config.version = SCREEN_SAVER_TODO_DATA_VERSION;
  return true;
}

/** 勾选/取消勾选（兼容旧调用方）。 */
export function screenSaverTodoToggle(config: ScreensaverTodoConfig, itemId: string): void {
  const item = screenSaverTodoFind(config, itemId);
  if (item === undefined) {
    return;
  }
  screenSaverTodoSetCompleted(config, itemId, !item.completed);
  config.items = config.items.slice();
}

/**
 * 手动排序：delta=-1 上移，delta=1 下移。
 * 到边界返回 false（UI 可 toast）；成功返回 true。
 */
export function screenSaverTodoMove(config: ScreensaverTodoConfig, itemId: string, delta: number): boolean {
  const index = config.items.findIndex((item: ScreensaverTodoItem): boolean => item.id === itemId);
  if (index < 0) {
    return false;
  }
  const target = index + delta;
  if (target < 0 || target >= config.items.length) {
    return false;
  }
  const next = config.items.slice();
  const moved = next[index];
  next[index] = next[target];
  next[target] = moved;
  config.items = next;
  screenSaverTodoReindex(config);
  return true;
}

/** 稳定比较：orderIndex → id（id 只作为脏数据兜底，不参与正常排序）。 */
function screenSaverTodoCompareOpen(a: ScreensaverTodoItem, b: ScreensaverTodoItem): number {
  if (a.orderIndex !== b.orderIndex) {
    return a.orderIndex - b.orderIndex;
  }
  if (a.id === b.id) {
    return 0;
  }
  return a.id < b.id ? -1 : 1;
}

/** 已完成区：completedAt 升序（null 视为最旧），再按 orderIndex 兜底。 */
function screenSaverTodoCompareDone(a: ScreensaverTodoItem, b: ScreensaverTodoItem): number {
  const aAt = a.completedAt === null ? 0 : a.completedAt;
  const bAt = b.completedAt === null ? 0 : b.completedAt;
  if (aAt !== bAt) {
    return aAt - bAt;
  }
  return screenSaverTodoCompareOpen(a, b);
}

/**
 * 屏保展示顺序：未完成区（orderIndex 升序）+ 已完成区（completedAt 升序）。
 * 每次渲染都按持久化键计算，不读取 Date.now()，因此不会抖动。
 */
export function screenSaverTodoDisplayItems(config: ScreensaverTodoConfig): ScreensaverTodoItem[] {
  const open: ScreensaverTodoItem[] = [];
  const done: ScreensaverTodoItem[] = [];
  for (const item of config.items) {
    if (item.completed) {
      done.push(item);
    } else {
      open.push(item);
    }
  }
  open.sort(screenSaverTodoCompareOpen);
  done.sort(screenSaverTodoCompareDone);
  return open.concat(done);
}

/** 兼容旧命名：屏保态现在展示全部条目（未完成在前，已完成沉底）。 */
export function screenSaverTodoOpenItems(config: ScreensaverTodoConfig): ScreensaverTodoItem[] {
  return screenSaverTodoDisplayItems(config);
}

/** 清空已完成（设置面板提供）。 */
export function screenSaverTodoClearDone(config: ScreensaverTodoConfig): void {
  const next: ScreensaverTodoItem[] = [];
  for (const item of config.items) {
    if (!item.completed) {
      next.push(item);
    }
  }
  config.items = next;
  screenSaverTodoReindex(config);
}
