/**
 * =============================================================================
 * 倒计时卡片视图（CountdownCardView.ets）
 * =============================================================================
 *
 * 屏保页排版（本次重做）：
 *   第一行（固定）：还剩 X 天 / 就是今天，数字水平居中，是卡片主视觉；
 *   滚动区：事件名称（最多 2 行，超出省略号）+ 事件日期（中文写法，跨年带年份）；
 *   同日多条事件时，天数行只出现一次，其余条目标题在滚动区内查看。
 *
 * 不显示任何数据来源标签（在线/自定义/来源 A/B/C）；离线时只保留一行缓存时间。
 * 编辑态不滚动，显示下箭头提示；屏保态滑动后 10 秒回顶部。
 * =============================================================================
 */

import { ScreenSaverLogger } from '../common/Logger';
import { SCREEN_SAVER_FONT } from '../common/CardTypography';
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
  ScreensaverInkTone
} from '../model/ConfigModels';
import {
  screenSaverBuildCountdownView,
  screenSaverCountdownDaysText,
  screenSaverCountdownPrefix,
  screenSaverCountdownSuffix,
  screenSaverEmptyCountdownView,
  screenSaverHolidayStore,
  ScreensaverCountdownEntry,
  ScreensaverCountdownView,
  ScreensaverHolidayStore
} from '../model/CountdownViewModel';
import { screenSaverFormatStamp } from '../common/DateFormats';

/** 倒计时条目的懒加载数据源。 */
class ScreensaverCountdownDataSource implements IDataSource {
  private listeners: DataChangeListener[] = [];
  private items: ScreensaverCountdownEntry[] = [];

  totalCount(): number {
    return this.items.length;
  }

  getData(index: number): ScreensaverCountdownEntry {
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

  setItems(items: ScreensaverCountdownEntry[]): void {
    this.items = items;
    for (const listener of this.listeners) {
      listener.onDataReloaded();
    }
  }
}

@ComponentV2
export struct ScreensaverCountdownCard {
  @Param card: ScreensaverCardInstance = new ScreensaverCardInstance();
  @Param cardMode: ScreensaverCardMode = 'play';
  @Param cardActive: boolean = true;
  @Param cardTone: ScreensaverInkTone = 'light';
  @Param cardHalo: boolean = false;
  @Event onRequestConfig: () => void = (): void => {};
  /** 仅屏保编辑态显示下箭头提示；首页预览/设置预览不显示。 */
  @Param showOverflowHint: boolean = false;
  /** 设置面板内每次保存/删除后递增，强制重算预览（V2 嵌套数组观察的兜底）。 */
  @Param previewToken: number = 0;

  /** 本地引用全局 Store：让 V2 观察 @Trace 的 state/years/fetchedAt。 */
  @Local private holidayStore: ScreensaverHolidayStore = screenSaverHolidayStore;
  @Local private viewData: ScreensaverCountdownView = screenSaverEmptyCountdownView();
  @Local private totalEntries: number = 0;
  @Local private lastVisibleIndex: number = 0;

  private dataSource: ScreensaverCountdownDataSource = new ScreensaverCountdownDataSource();
  private scroller: Scroller = new Scroller();
  private resetTimer: number = -1;
  private lastResetMs: number = 0;

  private palette(): ScreensaverCardPalette {
    return screenSaverCardPalette(this.cardTone);
  }

  private textShadow(): ShadowOptions {
    return screenSaverTextShadow(this.cardHalo, this.palette().halo);
  }

  private density(): ScreensaverCardDensity {
    return screenSaverResolveDensity(this.card.cardType, this.card.colSpan, this.card.rowSpan);
  }

  /** 1×1 只给天数 + 第一条名称；日期/离线时间让位。 */
  private isOneByOne(): boolean {
    return this.card.colSpan <= 1 && this.card.rowSpan <= 1;
  }

  private includesOnline(): boolean {
    return this.card.countdown.source === 'auto' || this.card.countdown.source === 'online';
  }

  private refreshView(): void {
    this.viewData = screenSaverBuildCountdownView(this.card.countdown, this.holidayStore);
    this.dataSource.setItems(this.viewData.entries);
    this.totalEntries = this.viewData.entries.length;
    this.lastVisibleIndex = 0;
  }

  aboutToAppear(): void {
    this.holidayStore.hydrate();
    this.refreshView();
    this.tryRefresh(false);
  }

  aboutToDisappear(): void {
    this.clearResetTimer();
  }

  private tryRefresh(force: boolean): void {
    if (!this.cardActive || !this.includesOnline()) {
      return;
    }
    void this.holidayStore.ensureCoverage(force).then((): void => {
      this.refreshView();
    });
  }

  @Monitor('cardActive')
  onActiveChanged(): void {
    if (this.cardActive) {
      this.holidayStore.hydrate();
      this.refreshView();
      this.tryRefresh(false);
    }
  }

  @Monitor('card.countdown.source', 'card.countdown.customItems')
  onConfigChanged(): void {
    this.refreshView();
    this.tryRefresh(false);
  }

  @Monitor('holidayStore.state', 'holidayStore.years', 'holidayStore.fetchedAt')
  onStoreChanged(): void {
    this.refreshView();
  }

  @Monitor('previewToken')
  onPreviewTokenChanged(): void {
    this.refreshView();
  }

  @Monitor('cardMode')
  onModeChanged(): void {
    this.clearResetTimer();
    if (this.cardMode === 'play') {
      try {
        this.scroller.scrollTo({ xOffset: 0, yOffset: 0, animation: false });
      } catch (err) {
        ScreenSaverLogger.warn('countdown scroll reset skipped');
      }
    }
  }

  private clearResetTimer(): void {
    if (this.resetTimer >= 0) {
      clearTimeout(this.resetTimer);
      this.resetTimer = -1;
    }
  }

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
        ScreenSaverLogger.warn('countdown scroll reset skipped');
      }
    }, SCREEN_SAVER_CARD_SCROLL_RESET_MS);
  }

  private shouldShowOverflowHint(): boolean {
    if (!this.showOverflowHint || this.cardMode !== 'edit') {
      return false;
    }
    if (this.totalEntries <= 1) {
      return false;
    }
    return this.lastVisibleIndex < this.totalEntries - 1;
  }

  private tagColor(entry: ScreensaverCountdownEntry): string {
    if (entry.tag === '休') {
      return this.palette().restTag;
    }
    if (entry.tag === '班') {
      return this.palette().workTag;
    }
    return this.palette().textTertiary;
  }

  /**
   * 1×1 天数主字号：1~2 位用 L2=24；3 位（如 100）降到 L5=14，
   * 保证「还剩 + 3 位数字 + 天」在 90vp 窄卡内不溢出（§1.3 先不溢出）。
   */
  private countdownNumberFont(view: ScreensaverCountdownView): number {
    if (!this.isOneByOne()) {
      return SCREEN_SAVER_FONT.L0;
    }
    const daysText = screenSaverCountdownDaysText(view);
    return daysText.length >= 3 ? SCREEN_SAVER_FONT.L5 : SCREEN_SAVER_FONT.L2;
  }

  /** 固定天数主视觉：只出现一次，水平居中。 */
  @Builder
  countdownHeader(view: ScreensaverCountdownView) {
    Column({ space: 1 }) {
      if (view.isToday) {
        Text(screenSaverCountdownDaysText(view))
          .fontSize(SCREEN_SAVER_FONT.L0)
          .fontColor(this.palette().textPrimary)
          .fontWeight(FontWeight.Medium)
          .maxLines(1)
          .textAlign(TextAlign.Center)
          .textShadow(this.textShadow())
      } else {
        Row({ space: 2 }) {
          Text(screenSaverCountdownPrefix(view))
            .fontSize(this.isOneByOne() ? SCREEN_SAVER_FONT.L7 : SCREEN_SAVER_FONT.L5)
            .fontColor(this.palette().textSecondary)
            .maxLines(1)
            .textShadow(this.textShadow())
          Text(screenSaverCountdownDaysText(view))
            .fontSize(this.countdownNumberFont(view))
            .fontColor(this.palette().textPrimary)
            .fontWeight(FontWeight.Medium)
            .maxLines(1)
            .textShadow(this.textShadow())
          Text(screenSaverCountdownSuffix(view))
            .fontSize(this.isOneByOne() ? SCREEN_SAVER_FONT.L7 : SCREEN_SAVER_FONT.L5)
            .fontColor(this.palette().textSecondary)
            .maxLines(1)
            .textShadow(this.textShadow())
          if (view.isStatutory) {
            Text('!')
              .fontSize(this.isOneByOne() ? SCREEN_SAVER_FONT.L7 : SCREEN_SAVER_FONT.L5)
              .fontColor(this.palette().restTag)
              .fontWeight(FontWeight.Bold)
              .maxLines(1)
              .textShadow(this.textShadow())
          }
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Bottom)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .padding({ left: 4, right: 4, top: this.isOneByOne() ? 3 : 5, bottom: 1 })
  }

  /** 单条：名称（最多 2 行）+ 中文日期（+ 休/班）。 */
  @Builder
  entryRow(entry: ScreensaverCountdownEntry) {
    Column({ space: 1 }) {
      Text(entry.title)
        .fontSize(this.isOneByOne() ? SCREEN_SAVER_FONT.L6 : SCREEN_SAVER_FONT.L4)
        .fontColor(this.palette().textPrimary)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .textShadow(this.textShadow())
      if (!this.isOneByOne()) {
        Row({ space: 4 }) {
          Text(entry.dateLabel)
            .fontSize(SCREEN_SAVER_FONT.L6)
            .fontColor(this.palette().textSecondary)
            .maxLines(1)
            .textShadow(this.textShadow())
          if (entry.tag.length > 0) {
            Text(entry.tag)
              .fontSize(SCREEN_SAVER_FONT.L7)
              .fontColor(this.tagColor(entry))
              .padding({ left: 3, right: 3, top: 0, bottom: 0 })
              .borderRadius(3)
              .backgroundColor(this.palette().tagBackground)
          }
        }
        .width('100%')
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 4, right: 4, top: 2, bottom: 2 })
  }

  private emptyTitle(view: ScreensaverCountdownView): string {
    if (view.state === 'loading') {
      return '假期数据加载中…';
    }
    if (view.state === 'error') {
      return '假期数据暂不可用';
    }
    if (this.card.countdown.source === 'custom') {
      return '暂无自定义倒数日';
    }
    return '暂无未来假期';
  }

  private emptyDetail(view: ScreensaverCountdownView): string {
    if (view.emptyDetail.length > 0) {
      return view.emptyDetail;
    }
    if (view.state === 'loading') {
      return '进入屏保时只请求一次，不阻塞首帧';
    }
    if (view.state === 'error') {
      return view.errorText.length > 0 ? view.errorText : '请检查网络后重试';
    }
    if (this.card.countdown.source === 'custom') {
      return '在设置中添加名称与日期';
    }
    return '在线数据已加载，暂无未来标记日期';
  }

  private emptyAction(view: ScreensaverCountdownView): string {
    if (view.state === 'error') {
      return '点此重试';
    }
    if (view.state === 'loading') {
      return '';
    }
    return this.cardMode === 'edit' ? '点此设置' : '';
  }

  @Builder
  emptyHint(view: ScreensaverCountdownView) {
    Column({ space: 4 }) {
      Text(this.emptyTitle(view))
        .fontSize(this.isOneByOne() ? SCREEN_SAVER_FONT.L4 : SCREEN_SAVER_FONT.L5)
        .fontColor(this.palette().textPrimary)
        .fontWeight(FontWeight.Medium)
        .maxLines(2)
        .textAlign(TextAlign.Center)
        .textShadow(this.textShadow())
      Text(this.emptyDetail(view))
        .fontSize(this.isOneByOne() ? SCREEN_SAVER_FONT.L7 : SCREEN_SAVER_FONT.L6)
        .fontColor(this.palette().textSecondary)
        .maxLines(3)
        .textAlign(TextAlign.Center)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textShadow(this.textShadow())
      Text(this.emptyAction(view))
        .fontSize(SCREEN_SAVER_FONT.L7)
        .fontColor('#4A9EFF')
        .maxLines(1)
        .onClick((): void => {
          if (view.state === 'error') {
            void this.holidayStore.ensureCoverage(true).then((): void => {
              this.refreshView();
            });
          } else if (this.cardMode === 'edit') {
            this.onRequestConfig();
          }
        })
    }
    .width('100%')
    .constraintSize({ minHeight: '100%' })
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .padding({ left: 6, right: 6 })
    .onClick((): void => {
      if (this.cardMode === 'edit') {
        this.onRequestConfig();
      }
    })
  }

  build() {
    Stack() {
      if (this.viewData.entries.length === 0) {
        this.emptyHint(this.viewData)
      } else {
        Column() {
          this.countdownHeader(this.viewData)
          List({ space: 0, scroller: this.scroller }) {
            LazyForEach(this.dataSource, (entry: ScreensaverCountdownEntry) => {
              ListItem() {
                this.entryRow(entry)
              }
            }, (entry: ScreensaverCountdownEntry, index: number): string =>
            `${entry.targetDateKey}-${entry.title}-${entry.tag}-${index}`)
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
          if (this.viewData.state === 'offline' && !this.isOneByOne()) {
            Text(`离线 · 缓存 ${screenSaverFormatStamp(this.viewData.fetchedAt)}`)
              .fontSize(SCREEN_SAVER_FONT.L7)
              .fontColor(this.palette().textTertiary)
              .maxLines(1)
              .textAlign(TextAlign.Center)
              .width('100%')
              .padding({ bottom: 2 })
              .textShadow(this.textShadow())
          }
        }
        .width('100%')
        .height('100%')
        .padding({ left: 3, right: 3, top: 2, bottom: 2 })
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
