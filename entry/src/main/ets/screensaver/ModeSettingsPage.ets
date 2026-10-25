/**
 * =============================================================================
 * 方向屏保设置页（ModeSettingsPage.ets）
 * =============================================================================
 *
 * 【这个页面是干什么的】
 * 竖屏 / 横屏各自的设置入口：
 *   · 卡片开关；
 *   · 卡片内容设置（点箭头就地展开，再点/上拉收起）；
 *   · 「＋ 添加卡片」内联面板；
 *   · 删除卡片。
 *
 * 【入口】
 * 屏保页长按进入编辑模式 → 底栏「屏保设置」；
 * 首页开屏保前的空/越界预检失败时也会跳到这里。
 *
 * 【为什么不再做尺寸选择/上移下移】
 * 卡片位置和尺寸回到屏保页长按编辑模式里直接用手指拖动/缩放；
 * 设置页只保留“开关 + 内容设置”两件事，避免两套入口互相覆盖。
 * =============================================================================
 */

import { ScreenSaverLogger } from '../common/Logger';
import { SCREEN_SAVER_COLORS } from '../common/ScreenSaverStyle';
import { screenSaverAppModel } from '../model/AppModel';
import {
  SCREEN_SAVER_CARD_CATALOG,
  screenSaverSnapCardSize
} from '../cards/CardCatalog';
import {
  SCREEN_SAVER_LANDSCAPE_CARD_MAX_COLS,
  SCREEN_SAVER_LANDSCAPE_CARD_MAX_ROWS,
  ScreensaverCardInstance,
  ScreensaverCardMeta,
  ScreenSaverOrientation,
  screenSaverOrientationLabel
} from '../model/ConfigModels';
import { ScreenSaverClockSettingsPanel } from './sheets/ClockSettingsSheet';
import { ScreenSaverPhotoSettingsPanel } from './sheets/PhotoSettingsSheet';
import { ScreenSaverVideoSettingsPanel } from './sheets/VideoSettingsSheet';
import { ScreenSaverGitSettingsPanel } from './sheets/GitSettingsSheet';
import { ScreenSaverWeatherSettingsPanel } from './sheets/WeatherSettingsSheet';
import { ScreenSaverEntrySettingsPanel } from './sheets/EntrySettingsSheet';
import { ScreenSaverQuotesSettingsPanel } from './sheets/QuotesSettingsSheet';
import { ScreenSaverCountdownSettingsPanel } from './sheets/CountdownSettingsSheet';
import { ScreenSaverTodoSettingsPanel } from './sheets/TodoSettingsSheet';

@ComponentV2
export struct ScreenSaverModeSettingsPage {
  @Param navStack: NavPathStack = new NavPathStack();
  @Param mode: ScreenSaverOrientation = ScreenSaverOrientation.Portrait;

  /** 当前展开内容设置的卡片 id（空串 = 全部收起）。 */
  @Local expandedCardId: string = '';
  /** 「添加卡片」列表是否展开。 */
  @Local addPanelVisible: boolean = false;
  /** 删除后强制刷新列表（卡片数组 splice 的观察依赖）。 */
  @Local cardsRevisionTick: number = 0;

  aboutToAppear(): void {
    screenSaverAppModel.setActiveOrientation(this.mode);
    ScreenSaverLogger.info(`mode settings open: ${this.mode}`);
  }

  private modeLabel(): string {
    return screenSaverOrientationLabel(this.mode);
  }

  private cards(): ScreensaverCardInstance[] {
    const layout = screenSaverAppModel.layoutForMode(this.mode);
    const revision = layout.cardsRevision;
    if (revision < 0 || this.cardsRevisionTick < 0) {
      return [];
    }
    return layout.cards;
  }

  private toast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message, duration: 1500 });
    } catch (err) {
      const error = err as Error;
      ScreenSaverLogger.warn(`toast failed: ${error.message}`);
    }
  }

  private maxCols(): number {
    return this.mode === ScreenSaverOrientation.Landscape ?
      SCREEN_SAVER_LANDSCAPE_CARD_MAX_COLS : screenSaverAppModel.maxCardColSpan();
  }

  private maxRows(): number {
    return this.mode === ScreenSaverOrientation.Landscape ?
      SCREEN_SAVER_LANDSCAPE_CARD_MAX_ROWS : screenSaverAppModel.maxCardRowSpan();
  }

  private summaryOf(card: ScreensaverCardInstance): string {
    return screenSaverAppModel.cardInstanceSummary(card);
  }

  /** 展开/收起某张卡片的内容设置。 */
  private toggleExpanded(card: ScreensaverCardInstance): void {
    this.expandedCardId = this.expandedCardId === card.id ? '' : card.id;
  }

  private collapseExpanded(): void {
    this.expandedCardId = '';
  }

  /** 内容面板高度：竖屏给足空间；横屏窗口矮，面板可在外层滚动里查看。 */
  private expandedHeight(): number {
    return this.mode === ScreenSaverOrientation.Landscape ? 360 : 460;
  }

  /** 删除确认（危险操作二次确认）。 */
  private confirmRemove(card: ScreensaverCardInstance): void {
    this.getUIContext().showAlertDialog({
      title: '移除卡片',
      message: `确定要从${this.modeLabel()}屏保移除「${screenSaverAppModel.cardInstanceTitle(card)}」吗？`,
      primaryButton: {
        value: '取消',
        action: (): void => {}
      },
      secondaryButton: {
        value: '移除',
        fontColor: SCREEN_SAVER_COLORS.danger,
        action: (): void => {
          if (this.expandedCardId === card.id) {
            this.expandedCardId = '';
          }
          screenSaverAppModel.removeCard(card.id);
          this.cardsRevisionTick += 1;
          this.toast('已移除卡片');
        }
      }
    });
  }

  /** 内容面板里的删除入口：删除后收起面板。 */
  private removeInline(card: ScreensaverCardInstance): void {
    if (this.expandedCardId === card.id) {
      this.expandedCardId = '';
    }
    screenSaverAppModel.removeCard(card.id);
    this.cardsRevisionTick += 1;
  }

  /** 添加面板里每种卡片的默认尺寸（按当前方向上限吸附后展示）。 */
  private addSizeLabel(meta: ScreensaverCardMeta): string {
    const entry = screenSaverSnapCardSize(meta.cardType, meta.defaultColSpan, meta.defaultRowSpan,
      this.maxCols(), this.maxRows());
    return `${entry.colSpan}×${entry.rowSpan}`;
  }

  private addBlockedReason(meta: ScreensaverCardMeta): string {
    return screenSaverAppModel.cardAddBlockedReason(meta.cardType);
  }

  private addCard(meta: ScreensaverCardMeta): void {
    const reason = this.addBlockedReason(meta);
    if (reason.length > 0) {
      this.toast(reason);
      return;
    }
    if (!screenSaverAppModel.addCard(meta.cardType)) {
      this.toast('空间不足：请先移出或缩小卡片');
      return;
    }
    this.toast(`已添加${meta.displayName}卡片`);
  }

  // ==================== UI ====================

  @Builder
  topBar() {
    Row() {
      Text('返回')
        .fontSize(14)
        .fontColor('#CCCCCC')
        .padding({ left: 16, right: 12, top: 12, bottom: 12 })
        .onClick((): void => {
          this.navStack.pop();
        })
      Blank()
      Text(`${this.modeLabel()}屏保设置`)
        .fontSize(16)
        .fontColor(SCREEN_SAVER_COLORS.textPrimary)
      Blank()
      Text('完成')
        .fontSize(14)
        .fontColor(SCREEN_SAVER_COLORS.accent)
        .padding({ left: 12, right: 16, top: 12, bottom: 12 })
        .onClick((): void => {
          this.navStack.pop();
        })
    }
    .width('100%')
  }

  @Builder
  emptyGuide() {
    Column({ space: 8 }) {
      Text(`当前${this.modeLabel()}还没有卡片`)
        .fontSize(15)
        .fontColor(SCREEN_SAVER_COLORS.textPrimary)
      Text('从下方添加一张卡片后即可开启该方向屏保')
        .fontSize(12)
        .fontColor(SCREEN_SAVER_COLORS.textTertiary)
    }
    .width('100%')
    .padding({ top: 28, bottom: 28 })
    .borderRadius(12)
    .backgroundColor(SCREEN_SAVER_COLORS.bgElevated)
  }

  /**
   * 内容设置面板：复用原有 9 个设置面板，嵌在卡片下方就地展开。
   * 面板自己的「完成」也会收起；顶部另有一个「收起 ▴」行。
   */
  @Builder
  inlinePanel(card: ScreensaverCardInstance) {
    Column() {
      if (card.cardType === 'clock') {
        ScreenSaverClockSettingsPanel({
          card: card,
          onDone: (): void => {
            this.collapseExpanded();
          },
          onDelete: (): void => {
            this.removeInline(card);
          }
        })
      } else if (card.cardType === 'photo') {
        ScreenSaverPhotoSettingsPanel({
          card: card,
          onDone: (): void => {
            this.collapseExpanded();
          },
          onDelete: (): void => {
            this.removeInline(card);
          }
        })
      } else if (card.cardType === 'video') {
        ScreenSaverVideoSettingsPanel({
          card: card,
          onDone: (): void => {
            this.collapseExpanded();
          },
          onDelete: (): void => {
            this.removeInline(card);
          }
        })
      } else if (card.cardType === 'git') {
        ScreenSaverGitSettingsPanel({
          card: card,
          onDone: (): void => {
            this.collapseExpanded();
          },
          onDelete: (): void => {
            this.removeInline(card);
          }
        })
      } else if (card.cardType === 'weather') {
        ScreenSaverWeatherSettingsPanel({
          card: card,
          onDone: (): void => {
            this.collapseExpanded();
          },
          onDelete: (): void => {
            this.removeInline(card);
          }
        })
      } else if (card.cardType === 'entry') {
        ScreenSaverEntrySettingsPanel({
          card: card,
          onDone: (): void => {
            this.collapseExpanded();
          },
          onDelete: (): void => {
            this.removeInline(card);
          }
        })
      } else if (card.cardType === 'quotes') {
        ScreenSaverQuotesSettingsPanel({
          card: card,
          onDone: (): void => {
            this.collapseExpanded();
          },
          onDelete: (): void => {
            this.removeInline(card);
          }
        })
      } else if (card.cardType === 'countdown') {
        ScreenSaverCountdownSettingsPanel({
          card: card,
          onDone: (): void => {
            this.collapseExpanded();
          },
          onDelete: (): void => {
            this.removeInline(card);
          }
        })
      } else if (card.cardType === 'todo') {
        ScreenSaverTodoSettingsPanel({
          card: card,
          onDone: (): void => {
            this.collapseExpanded();
          },
          onDelete: (): void => {
            this.removeInline(card);
          }
        })
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  cardRow(card: ScreensaverCardInstance) {
    Column({ space: 8 }) {
      // ---------- 开关行：标题 + 摘要 + 启停 + 下拉箭头 + 删除图标 ----------
      Row({ space: 2 }) {
        Column({ space: 2 }) {
          Text(screenSaverAppModel.cardInstanceTitle(card))
            .fontSize(15)
            .fontColor(SCREEN_SAVER_COLORS.textPrimary)
          Text(this.summaryOf(card))
            .fontSize(11)
            .fontColor(SCREEN_SAVER_COLORS.textTertiary)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: card.enabled })
          .selectedColor(SCREEN_SAVER_COLORS.accentStrong)
          .onChange((value: boolean): void => {
            screenSaverAppModel.setCardEnabled(card.id, value);
          })
        // 下拉箭头：点一下展开内容设置；展开后变成上箭头，再点收起。
        Text(this.expandedCardId === card.id ? '▴' : '▾')
          .fontSize(18)
          .fontColor(SCREEN_SAVER_COLORS.textSecondary)
          .width(40)
          .height(40)
          .textAlign(TextAlign.Center)
          .onClick((): void => {
            this.toggleExpanded(card);
          })
        // 删除：原图 24×24 不拉伸；外层 44×44 保证触控热区。
        Column() {
          Image($r('app.media.xmark_circle_fill'))
            .width(24)
            .height(24)
            .objectFit(ImageFit.Contain)
            .draggable(false)
            .accessibilityLevel('no')
        }
        .width(44)
        .height(44)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .accessibilityText('删除卡片')
        .accessibilityRole(AccessibilityRoleType.BUTTON)
        .accessibilityLevel('yes')
        .onClick((): void => {
          this.confirmRemove(card);
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      // ---------- 展开的内容设置（上拉/点箭头/点收起都能恢复） ----------
      if (this.expandedCardId === card.id) {
        Column() {
          Row() {
            Text('内容设置')
              .fontSize(12)
              .fontColor(SCREEN_SAVER_COLORS.textTertiary)
            Blank()
            Text('收起 ▴')
              .fontSize(12)
              .fontColor(SCREEN_SAVER_COLORS.accent)
              .padding({ left: 10, right: 4, top: 6, bottom: 6 })
              .onClick((): void => {
                this.collapseExpanded();
              })
          }
          .width('100%')
          .padding({ left: 12, right: 8 })
          .backgroundColor('#141417')
          .borderRadius({ topLeft: 10, topRight: 10 })
          // 上拉标题行收起；面板内部 Scroll 的向上滑动不受影响。
          .gesture(
            SwipeGesture({ direction: SwipeDirection.Vertical, speed: 1200 })
              .onAction((): void => {
                this.collapseExpanded();
              })
          )

          Column() {
            this.inlinePanel(card)
          }
          .width('100%')
          .layoutWeight(1)
        }
        .width('100%')
        .height(this.expandedHeight())
        .borderRadius(10)
        .backgroundColor('#141417')
        .clip(true)
      }

    }
    .width('100%')
    .padding(14)
    .borderRadius(12)
    .backgroundColor(SCREEN_SAVER_COLORS.bgElevated)
  }

  @Builder
  addPanel() {
    Column({ space: 8 }) {
      ForEach(SCREEN_SAVER_CARD_CATALOG, (meta: ScreensaverCardMeta) => {
        Row() {
          Column({ space: 2 }) {
            Text(meta.displayName)
              .fontSize(14)
              .fontColor(SCREEN_SAVER_COLORS.textPrimary)
            Text(`${meta.description} · ${this.addSizeLabel(meta)}`)
              .fontSize(11)
              .fontColor(SCREEN_SAVER_COLORS.textTertiary)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          if (this.addBlockedReason(meta).length > 0) {
            Text(meta.unique && screenSaverAppModel.hasCardType(meta.cardType) ? '已添加' : '放不下')
              .fontSize(12)
              .fontColor(SCREEN_SAVER_COLORS.textTertiary)
              .padding({ left: 12, right: 12, top: 6, bottom: 6 })
              .borderRadius(8)
              .backgroundColor(SCREEN_SAVER_COLORS.divider)
          } else {
            Text('添加')
              .fontSize(12)
              .fontColor(SCREEN_SAVER_COLORS.white)
              .padding({ left: 12, right: 12, top: 6, bottom: 6 })
              .borderRadius(8)
              .backgroundColor(SCREEN_SAVER_COLORS.accentStrong)
              .onClick((): void => {
                this.addCard(meta);
              })
          }
        }
        .width('100%')
        .padding({ top: 8, bottom: 8 })
      }, (meta: ScreensaverCardMeta): string => `mode_add_${meta.cardType}`)
    }
    .width('100%')
    .padding(12)
    .borderRadius(12)
    .backgroundColor(SCREEN_SAVER_COLORS.bgElevated)
  }

  build() {
    NavDestination() {
      Column() {
        this.topBar()
        Scroll() {
          Column({ space: 12 }) {
            Text(`以下卡片开关与内容设置仅影响${this.modeLabel()}屏保；背景、文字颜色、常亮为全局设置。`)
              .fontSize(12)
              .fontColor(SCREEN_SAVER_COLORS.textTertiary)
              .width('100%')
            if (this.cards().length === 0) {
              this.emptyGuide()
            } else {
              ForEach(this.cards(), (card: ScreensaverCardInstance) => {
                this.cardRow(card)
              }, (card: ScreensaverCardInstance): string =>
              `mode_card_${card.id}_${card.enabled}_${this.expandedCardId === card.id ? 'open' : 'closed'}_` +
                `${this.summaryOf(card)}`)
            }

            Row() {
              Text('＋ 添加卡片')
                .fontSize(14)
                .fontColor(SCREEN_SAVER_COLORS.accent)
            }
            .width('100%')
            .justifyContent(FlexAlign.Center)
            .padding({ top: 13, bottom: 13 })
            .borderRadius(10)
            .backgroundColor(SCREEN_SAVER_COLORS.bgElevated)
            .onClick((): void => {
              this.addPanelVisible = !this.addPanelVisible;
            })

            if (this.addPanelVisible) {
              this.addPanel()
            }

            Text(`当前${this.modeLabel()}布局：${this.cards().length} 张卡片 · 长按屏保页可拖动/缩放卡片`)
              .fontSize(11)
              .fontColor(SCREEN_SAVER_COLORS.textTertiary)
              .width('100%')
              .margin({ bottom: 24 })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 4 })
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .align(Alignment.Top)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(SCREEN_SAVER_COLORS.bg)
    }
    .hideTitleBar(true)
    .backgroundColor(SCREEN_SAVER_COLORS.bg)
    .onBackPressed((): boolean => {
      this.navStack.pop();
      return true;
    })
  }
}
