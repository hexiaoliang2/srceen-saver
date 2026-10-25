import { ScreenSaverLogger } from '../common/Logger';
import { SCREEN_SAVER_FONT } from '../common/CardTypography';
import {
  SCREEN_SAVER_TODO_CHECK,
  screenSaverCardPalette,
  screenSaverTextShadow,
  ScreensaverCardPalette,
  ScreensaverTodoCheckTokens
} from '../common/CardTheme';
import { screenSaverResolveDensity } from './CardCatalog';
import {
  SCREEN_SAVER_CARD_SCROLL_RESET_MS,
  ScreensaverCardDensity,
  ScreensaverCardInstance,
  ScreensaverCardMode,
  ScreensaverInkTone,
  ScreensaverTodoItem
} from '../model/ConfigModels';
import {
  screenSaverTodoDisplayItems,
  screenSaverTodoSetCompleted,
  screenSaverTodoSummary,
  ScreensaverTodoSummary
} from '../model/TodoViewModel';
import { screenSaverAppModel } from '../model/AppModel';
import { TodoCheckCircle } from './TodoCheckCircle';
import { FrameCallback } from '@kit.ArkUI';

/**
 * 下一帧恢复 List 滚动位置。
 *
 * 为什么不用 setTimeout：常驻/延时定时器在屏保态应尽量避免；FrameCallback
 * 只跟随一次 UI 帧，执行完即失效，不会留在后台。ForEach 差量更新后，
 * 在下一帧调用 scrollTo 才能覆盖框架自身的布局归位。
 */
class TodoScrollRestoreFrameCallback extends FrameCallback {
  private restore: () => void;
  private used: boolean = false;

  constructor(restore: () => void) {
    super();
    this.restore = restore;
  }

  onFrame(frameTimeInNano: number): void {
    this.runOnce();
  }

  onIdle(timeLeftInNano: number): void {
    this.runOnce();
  }

  private runOnce(): void {
    if (this.used) {
      return;
    }
    this.used = true;
    this.restore();
  }
}

@ComponentV2
export struct ScreensaverTodoCard {
  @Param card: ScreensaverCardInstance = new ScreensaverCardInstance();
  @Param cardMode: ScreensaverCardMode = 'play';
  @Param cardActive: boolean = true;
  @Param cardTone: ScreensaverInkTone = 'light';
  @Param cardHalo: boolean = false;
  @Event onRequestConfig: () => void = (): void => {};
  /** 仅屏保编辑态显示下箭头提示；首页预览/设置预览不显示。 */
  @Param showOverflowHint: boolean = false;

  /**
   * 展示顺序（未完成在前、已完成沉底）。
   * 用 ForEach + 稳定 id 差量更新，而不是 LazyForEach onDataReloaded：
   * 后者在本 SDK 上会把 List 滚动位置拉回顶部，违反「点击后不得重置滚动位置」。
   */
  @Local private displayItems: ScreensaverTodoItem[] = [];
  private scroller: Scroller = new Scroller();
  private resetTimer: number = -1;
  private lastResetMs: number = 0;
  /**
   * 整卡级连点合并窗口：勾选后条目会立即下沉，若允许 320ms 内再次点击，
   * 同一个屏幕位置会落到「补位上来的另一条」上，造成误勾。因此冷却窗口
   * 内忽略整张卡片的所有勾选点击（同一条自然也只接受一次翻转）。
   */
  @Local private lastToggleAtMs: number = 0;
  @Local private totalItems: number = 0;
  @Local private lastVisibleIndex: number = 0;

  private palette(): ScreensaverCardPalette {
    return screenSaverCardPalette(this.cardTone);
  }

  private textShadow(): ShadowOptions {
    return screenSaverTextShadow(this.cardHalo, this.palette().halo);
  }

  private checkTokens(): ScreensaverTodoCheckTokens {
    return SCREEN_SAVER_TODO_CHECK;
  }

  private density(): ScreensaverCardDensity {
    return screenSaverResolveDensity(this.card.cardType, this.card.colSpan, this.card.rowSpan);
  }

  private summary(): ScreensaverTodoSummary {
    return screenSaverTodoSummary(this.card.todo);
  }

  /** 1×1 只显示未完成数量；其余尺寸显示列表。 */
  private showList(): boolean {
    return !(this.card.colSpan <= 1 && this.card.rowSpan <= 1);
  }

  /** 屏保展示态、非 1×1、卡片在前台时才允许勾选。 */
  private canToggle(): boolean {
    return this.cardMode === 'play' && this.showList() && this.cardActive && this.card.enabled;
  }

  /** 当前字号档的行距（= 热区高度，避免相邻行热区重叠）。 */
  private hitHeight(): number {
    return this.density() === 'minimal' ?
      this.checkTokens().hitHeightMinimal : this.checkTokens().hitHeightRegular;
  }

  aboutToAppear(): void {
    this.syncItems();
  }

  aboutToDisappear(): void {
    this.clearResetTimer();
  }

  /** 展示数组是否已与目标顺序/状态一致（勾选后的 @Monitor 用它跳过重复赋值）。 */
  private displayMatches(items: ScreensaverTodoItem[]): boolean {
    if (this.displayItems.length !== items.length) {
      return false;
    }
    for (let index = 0; index < items.length; index++) {
      const current = this.displayItems[index];
      const next = items[index];
      if (current.id !== next.id || current.text !== next.text ||
        current.completed !== next.completed || current.orderIndex !== next.orderIndex) {
        return false;
      }
    }
    return true;
  }

  /** 卡片数据/模式变化时同步展示数组。 */
  @Monitor('card.todo.items', 'cardMode')
  onItemsChanged(): void {
    const items = screenSaverTodoDisplayItems(this.card.todo);
    if (this.displayMatches(items)) {
      // 勾选/取消已经在 handleToggle 里更新过 displayItems，这里不能重复赋值。
      this.totalItems = items.length;
      this.clearResetTimer();
      return;
    }
    this.syncItems();
    this.clearResetTimer();
  }

  private syncItems(): void {
    const items = screenSaverTodoDisplayItems(this.card.todo);
    this.totalItems = items.length;
    this.lastVisibleIndex = 0;
    this.displayItems = items;
  }

  /**
   * 勾选/取消（屏保展示态唯一入口）。
   * 先改数据 → 立刻刷新列表 → 防抖落盘；不跳转、不展开、不退出屏保。
   */
  private handleToggle(itemId: string): void {
    if (!this.canToggle()) {
      return;
    }
    const now = Date.now();
    if (now - this.lastToggleAtMs < this.checkTokens().toggleDebounceMs) {
      ScreenSaverLogger.info(`todo toggle merged: delta=${now - this.lastToggleAtMs}ms`);
      return;
    }
    // 记录当前滚动位置：ForEach 差量更新通常能保留偏移，这里再做一次
    // 无动画 scrollTo 兜底（不新增定时器）。
    let savedOffsetY = 0;
    try {
      savedOffsetY = this.scroller.currentOffset().yOffset;
    } catch (err) {
      savedOffsetY = 0;
    }
    ScreenSaverLogger.info(`todo scroll before toggle: ${savedOffsetY}`);
    let completed = false;
    for (const item of this.card.todo.items) {
      if (item.id === itemId) {
        completed = item.completed;
        break;
      }
    }
    const changed = screenSaverTodoSetCompleted(this.card.todo, itemId, !completed);
    if (!changed) {
      return;
    }
    this.lastToggleAtMs = now;
    const after = screenSaverTodoDisplayItems(this.card.todo);
    this.totalItems = after.length;
    // ForEach 按稳定 id 差量更新，不重建 List，滚动位置得以保留。
    this.displayItems = after;
    // 整体替换数组，确保依赖 items 的统计/其它观察者能感知。
    // displayMatches() 会让随后的 @Monitor 跳过重复赋值。
    this.card.todo.items = this.card.todo.items.slice();
    if (savedOffsetY > 0) {
      const restoreOffset = savedOffsetY;
      try {
        this.getUIContext().postFrameCallback(new TodoScrollRestoreFrameCallback((): void => {
          try {
            this.scroller.scrollTo({ xOffset: 0, yOffset: restoreOffset, animation: false });
          } catch (err) {
            ScreenSaverLogger.warn('todo scroll restore skipped');
          }
        }));
      } catch (err) {
        ScreenSaverLogger.warn('todo scroll restore frame callback skipped');
      }
    }
    // 勾选必须持久化：先记待保存方向，再立即刷盘（不等 200ms 防抖）。
    screenSaverAppModel.save();
    void screenSaverAppModel.flush();
  }

  private clearResetTimer(): void {
    if (this.resetTimer >= 0) {
      clearTimeout(this.resetTimer);
      this.resetTimer = -1;
    }
  }

  /** 屏保态滑动后 10 秒无操作 → 系统滚动回顶部。 */
  private scheduleReset(): void {
    if (this.cardMode !== 'play') {
      return;
    }
    if (Date.now() - this.lastResetMs < 300) {
      return;
    }
    this.clearResetTimer();
    this.resetTimer = setTimeout((): void => {
      this.resetTimer = -1;
      this.lastResetMs = Date.now();
      try {
        this.scroller.scrollTo({ xOffset: 0, yOffset: 0, animation: false });
      } catch (err) {
        ScreenSaverLogger.warn('todo scroll reset skipped');
      }
    }, SCREEN_SAVER_CARD_SCROLL_RESET_MS);
  }

  /** 编辑态下箭头提示：列表未显示到最后一项时出现。 */
  private shouldShowOverflowHint(): boolean {
    return this.showOverflowHint && this.showList() && this.totalItems > 1 &&
      this.lastVisibleIndex < this.totalItems - 1;
  }

  /** 1×1：未完成数量（保持既有外观，不渲染勾选圆、不响应点击）。 */
  @Builder
  countView() {
    Column({ space: 0 }) {
      Text(`${this.summary().open}`)
        .fontSize(this.density() === 'minimal' && this.summary().open >= 100 ?
        SCREEN_SAVER_FONT.L2 : SCREEN_SAVER_FONT.L0)
        .fontColor(this.palette().textPrimary)
        .fontWeight(FontWeight.Medium)
        .maxLines(1)
        .textShadow(this.textShadow())
      Text('未完成')
        .fontSize(SCREEN_SAVER_FONT.L6)
        .fontColor(this.palette().textSecondary)
        .maxLines(1)
        .textShadow(this.textShadow())
      if (this.summary().total > 0) {
        Text(`共 ${this.summary().total} 条`)
          .fontSize(SCREEN_SAVER_FONT.L7)
          .fontColor(this.palette().textTertiary)
          .maxLines(1)
          .margin({ top: 1 })
          .textShadow(this.textShadow())
      }
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .onClick((): void => {
      if (this.cardMode === 'edit') {
        this.onRequestConfig();
      }
    })
  }

  /** 列表头部：未完成数 + 完成/总数（full 档）。 */
  @Builder
  headerView() {
    Row({ space: 4 }) {
      Text('待办')
        .fontSize(SCREEN_SAVER_FONT.L6)
        .fontColor(this.palette().textSecondary)
        .maxLines(1)
        .textShadow(this.textShadow())
      Text(`${this.summary().open} 未完成`)
        .fontSize(SCREEN_SAVER_FONT.L7)
        .fontColor(this.palette().textTertiary)
        .maxLines(1)
        .textShadow(this.textShadow())
      Blank()
      if (this.density() === 'full') {
        Text(`${this.summary().done}/${this.summary().total}`)
          .fontSize(SCREEN_SAVER_FONT.L7)
          .fontColor(this.palette().textTertiary)
          .maxLines(1)
          .textShadow(this.textShadow())
      }
    }
    .width('100%')
    .padding({ left: 9, right: 9, bottom: 2 })
  }

  /**
   * 单条待办：仅圆可交互（play 态、非 1×1）；文字与空白不绑定任何点击，
   * 点击会冒泡到卡片后被 ScreensaverPage 的待办分支吞掉。
   */
  @Builder
  todoRow(item: ScreensaverTodoItem) {
    Row({ space: this.checkTokens().rowSpace }) {
      TodoCheckCircle({
        completed: item.completed,
        interactive: this.canToggle(),
        cardTone: this.cardTone,
        hitHeight: this.hitHeight(),
        fontSize: this.density() === 'minimal' ? SCREEN_SAVER_FONT.L5 : SCREEN_SAVER_FONT.L4,
        onToggle: (): void => {
          this.handleToggle(item.id);
        }
      })
      Text(item.text)
        .fontSize(this.density() === 'minimal' ? SCREEN_SAVER_FONT.L5 : SCREEN_SAVER_FONT.L4)
        .fontColor(this.palette().textPrimary)
        .opacity(item.completed ? this.checkTokens().completedTextOpacity : 1)
        .decoration({
          type: item.completed ? TextDecorationType.LineThrough : TextDecorationType.None,
          color: this.palette().textPrimary
        })
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
        .textShadow(this.textShadow())
    }
    .width('100%')
    .padding({ left: this.checkTokens().rowLeftPadding, right: 2, top: 2, bottom: 2 })
    .alignItems(VerticalAlign.Center)
  }

  /** 空态：无待办。 */
  @Builder
  emptyView() {
    Column({ space: 3 }) {
      Text('暂无待办')
        .fontSize(this.density() === 'minimal' ? SCREEN_SAVER_FONT.L5 : SCREEN_SAVER_FONT.L4)
        .fontColor(this.palette().textSecondary)
        .maxLines(1)
        .textShadow(this.textShadow())
      Text(this.cardMode === 'edit' ? '点此添加' : '')
        .fontSize(SCREEN_SAVER_FONT.L7)
        .fontColor('#4A9EFF')
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .onClick((): void => {
      if (this.cardMode === 'edit') {
        this.onRequestConfig();
      }
    })
  }

  build() {
    Stack() {
      if (!this.showList()) {
        this.countView()
      } else {
        Column() {
          this.headerView()
          if (this.totalItems === 0) {
            this.emptyView()
          } else {
            List({ space: 0, scroller: this.scroller }) {
              ForEach(this.displayItems, (item: ScreensaverTodoItem) => {
                ListItem() {
                  this.todoRow(item)
                }
              }, (item: ScreensaverTodoItem): string => item.id)
            }
            .width('100%')
            .layoutWeight(1)
            .padding({ right: 7 })
            .scrollBar(BarState.Off)
            .edgeEffect(EdgeEffect.None)
            .enableScrollInteraction(this.cardMode === 'play')
            .nestedScroll({
              scrollForward: NestedScrollMode.SELF_FIRST,
              scrollBackward: NestedScrollMode.SELF_FIRST
            })
            .onScrollIndex((start: number, end: number): void => {
              this.lastVisibleIndex = end;
            })
            .onDidScroll((): void => {
              if (this.cardMode === 'play') {
                this.scheduleReset();
              }
            })
          }
        }
        .width('100%')
        .height('100%')
        // 左右内边距下放到 header / 列表：让行首圆能贴到卡片左边缘，
        // 同时保持文字起始缩进与改造前完全一致。
        .padding({ left: 0, right: 0, top: 5, bottom: 5 })
      }
      if (this.shouldShowOverflowHint()) {
        Text('↓')
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.palette().textSecondary)
          .position({ x: 0, y: '100%' })
          .markAnchor({ x: 0, y: '100%' })
          .offset({ x: 13, y: -6 })
          .hitTestBehavior(HitTestMode.None)
      }
    }
    .width('100%')
    .height('100%')
    .clip(true)
  }
}
