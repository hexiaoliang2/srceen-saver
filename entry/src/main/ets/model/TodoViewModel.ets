/**
 * =============================================================================
 * 待办卡数据层（TodoViewModel.ets）
 * =============================================================================
 *
 * 零权限、只做自带编辑：
 *   - 新增（最多 60 字）、勾选完成、删除、手动上移/下移；
 *   - 不做重复规则、不做提醒、不读日历；
 *   - 数据挂在卡片实例的 todo 配置上，随布局持久化，重启不丢；
 *   - todo.version 独立于布局 schemaVersion，便于以后迁移。
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
    if (item.done) {
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
  item.done = false;
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
}

/** 勾选/取消勾选。 */
export function screenSaverTodoToggle(config: ScreensaverTodoConfig, itemId: string): void {
  for (const item of config.items) {
    if (item.id === itemId) {
      item.done = !item.done;
      return;
    }
  }
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
  return true;
}

/** 屏保态只展示未完成项；编辑态面板可展示全部。 */
export function screenSaverTodoOpenItems(config: ScreensaverTodoConfig): ScreensaverTodoItem[] {
  const items: ScreensaverTodoItem[] = [];
  for (const item of config.items) {
    if (!item.done) {
      items.push(item);
    }
  }
  return items;
}

/** 清空已完成（设置面板提供）。 */
export function screenSaverTodoClearDone(config: ScreensaverTodoConfig): void {
  const next: ScreensaverTodoItem[] = [];
  for (const item of config.items) {
    if (!item.done) {
      next.push(item);
    }
  }
  config.items = next;
}
