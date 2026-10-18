/**
 * =============================================================================
 * 卡片通用滚动容器（CardScrollView.ets）
 * =============================================================================
 *
 * 统一定义“内容溢出即可滑动”的交互：
 *   - 纵向 Scroll；横向手势不消费（保留给页面/卡片切换）；
 *   - 滚动条隐藏、无边缘回弹；
 *   - nestedScroll = SELF_FIRST：卡片先滚，到边界再交给外层；
 *   - 屏保态可滚；编辑态 enableScrollInteraction(false)，不抢拖拽/长按；
 *   - 屏保态用户滑动后 10 秒无操作，用系统 Scroller 复位到顶部；
 *     定时器只在滑动后创建，复位/离开页面立即清除，进入屏保不启动常驻定时器；
 *   - 内容没超出时 Scroll 本身不会滚动（系统行为），不显示滚动条。
 *
 * 用法：把卡片原来的内容 Builder 作为尾随闭包传入，卡片根内容用
 * `.constraintSize({ minHeight: '100%' })` 而不是 `.height('100%')`，
 * 这样内容少时仍能居中，内容多时 Column 会自然长高。
 * =============================================================================
 */

import { SCREEN_SAVER_CARD_SCROLL_RESET_MS } from '../model/ConfigModels';

@ComponentV2
export struct CardScrollView {
  /** 屏保态 true；编辑态 false（禁用滚动，但保留子组件点击）。 */
  @Param scrollEnabled: boolean = true;
  /** 滑动后自动复位的延迟（毫秒）。 */
  @Param resetDelayMs: number = SCREEN_SAVER_CARD_SCROLL_RESET_MS;
  /** 复位键：卡片 id + 模式；切换卡片/模式时清掉旧定时器。 */
  @Param resetKey: string = '';
  /** 编辑态是否显示下箭头提示。 */
  @Param overflowHint: boolean = false;
  /** 下箭头颜色（跟随卡片文字墨色档，避免浅色背景上看不见）。 */
  @Param hintColor: string = '#F2F2F2';
  /** 数据层已知会溢出时的强制标记（测量在部分布局下只能拿到视口高度）。 */
  @Param forceOverflowHint: boolean = false;
  @BuilderParam content: () => void;

  private scroller: Scroller = new Scroller();
  private resetTimer: number = -1;
  private lastResetMs: number = 0;
  @Local private contentHeight: number = 0;
  @Local private viewportHeight: number = 0;
  @Local private overflow: boolean = false;

  aboutToDisappear(): void {
    this.clearResetTimer();
  }

  /** 模式/卡片切换：清掉定时器；回到屏保态时从顶部开始。 */
  @Monitor('resetKey', 'scrollEnabled')
  onContextChanged(): void {
    this.clearResetTimer();
    if (!this.scrollEnabled) {
      return;
    }
    try {
      this.scroller.scrollTo({ xOffset: 0, yOffset: 0, animation: false });
    } catch (err) {
      // 组件尚未挂载时 scrollTo 可能抛错：忽略，下一次滑动会重新计时。
    }
  }

  /** 清理复位定时器（离开页面/复位后调用）。 */
  private clearResetTimer(): void {
    if (this.resetTimer >= 0) {
      clearTimeout(this.resetTimer);
      this.resetTimer = -1;
    }
  }

  /** 用户滑动后重新计时；10 秒无操作 → 系统滚动回顶部。 */
  private scheduleReset(): void {
    if (!this.scrollEnabled) {
      return;
    }
    // 复位自身触发的 onDidScroll 不应再排一次定时器，否则会每 10 秒无限复位。
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
        // 已卸载场景忽略。
      }
    }, this.resetDelayMs);
  }

  /** 用“内容高度 > 视口高度”判断是否溢出；只用于编辑态提示。 */
  private updateOverflow(): void {
    const next = this.contentHeight > this.viewportHeight + 1;
    if (next !== this.overflow) {
      this.overflow = next;
    }
  }

  build() {
    Stack() {
      Scroll(this.scroller) {
        Column() {
          this.content()
        }
        .width('100%')
        // 内容少时至少撑满卡片（保持原有居中观感）；内容多时自然长高。
        .constraintSize({ minHeight: '100%' })
        .onAreaChange((oldArea: Area, newArea: Area): void => {
          this.contentHeight = typeof newArea.height === 'number' ? newArea.height : 0;
          this.updateOverflow();
        })
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.None)
      .enableScrollInteraction(this.scrollEnabled)
      .nestedScroll({
        scrollForward: NestedScrollMode.SELF_FIRST,
        scrollBackward: NestedScrollMode.SELF_FIRST
      })
      .onDidScroll((): void => {
        if (this.scrollEnabled) {
          this.scheduleReset();
        }
      })
      .onAreaChange((oldArea: Area, newArea: Area): void => {
        this.viewportHeight = typeof newArea.height === 'number' ? newArea.height : 0;
        this.updateOverflow();
      })

      // 编辑态下箭头提示：只在测量到内容超出（或数据层确认溢出）时出现。
      // 不要底板，只保留裸箭头；固定在卡片左下角。
      if (this.overflowHint && (this.overflow || this.forceOverflowHint)) {
        Text('↓')
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.hintColor)
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
