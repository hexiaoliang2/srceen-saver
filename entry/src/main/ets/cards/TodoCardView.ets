import { ScreenSaverLogger } from '../common/Logger';
import {
  screenSaverCardPalette,
  screenSaverTextShadow,
  ScreensaverCardPalette
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
  screenSaverTodoOpenItems,
  screenSaverTodoSummary,
  ScreensaverTodoSummary
} from '../model/TodoViewModel';

/** 待办列表的懒加载数据源：只提供未完成项。 */
class ScreensaverTodoDataSource implements IDataSource {
  private listeners: DataChangeListener[] = [];
  private items: ScreensaverTodoItem[] = [];

  totalCount(): number {
    return this.items.length;
  }

  getData(index: number): ScreensaverTodoItem {
    return this.items[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const index = this.listeners.indexOf(listener);
    if (index >= 0) {
      this.listeners.splice(index, 1);
    }
  }

  /** 替换数据并通知 LazyForEach 全量刷新。 */
  setItems(items: ScreensaverTodoItem[]): void {
    this.items = items;
    for (const listener of this.listeners) {
      listener.onDataReloaded();
    }
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

  private dataSource: ScreensaverTodoDataSource = new ScreensaverTodoDataSource();
  private scroller: Scroller = new Scroller();
  private resetTimer: number = -1;
  private lastResetMs: number = 0;
  @Local private totalOpen: number = 0;
  @Local private lastVisibleIndex: number = 0;

  private palette(): ScreensaverCardPalette {
    return screenSaverCardPalette(this.cardTone);
  }

  private textShadow(): ShadowOptions {
    return screenSaverTextShadow(this.cardHalo, this.palette().halo);
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

  aboutToAppear(): void {
    this.syncItems();
  }

  aboutToDisappear(): void {
    this.clearResetTimer();
  }

  /** 卡片数据/模式变化时同步 LazyForEach 数据源。 */
  @Monitor('card.todo.items', 'cardMode')
  onItemsChanged(): void {
    this.syncItems();
    this.clearResetTimer();
  }

  private syncItems(): void {
    const items = screenSaverTodoOpenItems(this.card.todo);
    this.totalOpen = items.length;
    this.lastVisibleIndex = 0;
    this.dataSource.setItems(items);
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
    return this.showOverflowHint && this.showList() && this.totalOpen > 1 &&
      this.lastVisibleIndex < this.totalOpen - 1;
  }

  /** 1×1：未完成数量。 */
  @Builder
  countView() {
    Column({ space: 0 }) {
      Text(`${this.summary().open}`)
        .fontSize(30)
        .fontColor(this.palette().textPrimary)
        .fontWeight(FontWeight.Medium)
        .maxLines(1)
        .textShadow(this.textShadow())
      Text('未完成')
        .fontSize(9)
        .fontColor(this.palette().textSecondary)
        .maxLines(1)
        .textShadow(this.textShadow())
      if (this.summary().total > 0) {
        Text(`共 ${this.summary().total} 条`)
          .fontSize(8)
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
        .fontSize(10)
        .fontColor(this.palette().textSecondary)
        .maxLines(1)
        .textShadow(this.textShadow())
      Text(`${this.summary().open} 未完成`)
        .fontSize(9)
        .fontColor(this.palette().textTertiary)
        .maxLines(1)
        .textShadow(this.textShadow())
      Blank()
      if (this.density() === 'full') {
        Text(`${this.summary().done}/${this.summary().total}`)
          .fontSize(8)
          .fontColor(this.palette().textTertiary)
          .maxLines(1)
          .textShadow(this.textShadow())
      }
    }
    .width('100%')
    .padding({ left: 2, right: 2, bottom: 2 })
  }

  /** 单条待办：屏保态只读，不显示勾选框。 */
  @Builder
  todoRow(item: ScreensaverTodoItem) {
    Row({ space: 4 }) {
      Text('·')
        .fontSize(this.density() === 'minimal' ? 12 : 13)
        .fontColor(this.palette().textTertiary)
        .maxLines(1)
        .textShadow(this.textShadow())
      Text(item.text)
        .fontSize(this.density() === 'minimal' ? 10 : 11)
        .fontColor(this.palette().textPrimary)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
        .textShadow(this.textShadow())
    }
    .width('100%')
    .padding({ top: 2, bottom: 2 })
    .alignItems(VerticalAlign.Top)
  }

  /** 空态：无待办。 */
  @Builder
  emptyView() {
    Column({ space: 3 }) {
      Text('暂无待办')
        .fontSize(this.density() === 'minimal' ? 10 : 12)
        .fontColor(this.palette().textSecondary)
        .maxLines(1)
        .textShadow(this.textShadow())
      Text(this.cardMode === 'edit' ? '点此添加' : '')
        .fontSize(9)
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
          if (this.totalOpen === 0) {
            this.emptyView()
          } else {
            List({ space: 0, scroller: this.scroller }) {
              LazyForEach(this.dataSource, (item: ScreensaverTodoItem) => {
                ListItem() {
                  this.todoRow(item)
                }
              }, (item: ScreensaverTodoItem): string => item.id)
            }
            .width('100%')
            .layoutWeight(1)
            .cachedCount(3)
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
        .padding({ left: 7, right: 7, top: 5, bottom: 5 })
      }
      if (this.shouldShowOverflowHint()) {
        Text('↓')
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.palette().textSecondary)
          .position({ x: 0, y: '100%' })
          .markAnchor({ x: 0, y: '100%' })
          .offset({ x: 6, y: -6 })
          .hitTestBehavior(HitTestMode.None)
      }
    }
    .width('100%')
    .height('100%')
    .clip(true)
  }
}
