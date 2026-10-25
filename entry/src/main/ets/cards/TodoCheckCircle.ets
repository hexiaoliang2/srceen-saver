/**
 * =============================================================================
 * 待办勾选圆（TodoCheckCircle.ets）
 * =============================================================================
 *
 * 屏保展示态唯一可点的元素：未完成空心圆 / 已完成填充圆 + 实心内点。
 *
 * 布局约束（必须与改造前一致）：
 *   - 外层占位 17×17vp；行左内边距缩到 1.2vp + 行距 1.5vp，
 *     把宽度让给圆，同时保持文字起始缩进不变；
 *   - 圆可视直径 = 当前待办文字字号 × 2/3（16fp→约 10.7vp），
 *     在 17vp 占位内居中，不挤压变形；热区不随视觉缩小；
 *   - 占位高 17vp 低于文字行高（L4 约 19.4vp），不抬高行高/行距；
 *   - 热区限制在「卡片左边缘 → 圆右缘」（19vp 宽）× 整行高，
 *     不覆盖同行文字、不与相邻行重叠（44×44 的规格冲突见交付报告）。
 *
 * 只有 interactive=true（屏保展示态且非 1×1）才绑定点击；
 * 1×1 档根本不渲染本组件，编辑态不响应勾选（点击会冒泡给卡片设置）。
 * =============================================================================
 */

import {
  SCREEN_SAVER_TODO_CHECK,
  ScreensaverTodoCheckTokens,
  screenSaverCardPalette,
  ScreensaverCardPalette
} from '../common/CardTheme';
import { ScreensaverInkTone } from '../model/ConfigModels';

@ComponentV2
export struct TodoCheckCircle {
  @Param completed: boolean = false;
  @Param interactive: boolean = false;
  @Param cardTone: ScreensaverInkTone = 'light';
  /** 热区高度 = 当前字号档的既有行距（常规 23vp / minimal 21vp）。 */
  @Param hitHeight: number = SCREEN_SAVER_TODO_CHECK.hitHeightRegular;
  /** 当前待办文字字号（fp）；可视圆按其 2/3 计算。 */
  @Param fontSize: number = 16;
  @Event onToggle: () => void = (): void => {};

  private tokens(): ScreensaverTodoCheckTokens {
    return SCREEN_SAVER_TODO_CHECK;
  }

  private palette(): ScreensaverCardPalette {
    return screenSaverCardPalette(this.cardTone);
  }

  private visualSize(): number {
    return this.fontSize * this.tokens().visualScale;
  }

  private innerDotSize(): number {
    return this.visualSize() * this.tokens().innerDotRatio;
  }

  private ringColor(): string {
    return this.completed ? this.palette().textPrimary : this.palette().textSecondary;
  }

  private accessibilityLabel(): string {
    if (!this.interactive) {
      return this.completed ? '已完成' : '未完成';
    }
    return this.completed ? '已完成，点击取消完成' : '未完成，点击标记完成';
  }

  /** 热区向左扩到卡片内边距：不覆盖文字，也不越出卡片左边界。 */
  private hitOffsetX(): number {
    return this.tokens().hitOffsetX;
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Stack() {
        Circle()
          .width(this.visualSize())
          .height(this.visualSize())
          .fill(Color.Transparent)
          .stroke(this.ringColor())
          .strokeWidth(this.tokens().strokeWidth)
        if (this.completed) {
          Circle()
            .width(this.innerDotSize())
            .height(this.innerDotSize())
            .fill(this.palette().textPrimary)
        }
      }
      .width(this.visualSize())
      .height(this.visualSize())
      .opacity(this.completed ? this.tokens().completedOpacity : 1)
    }
    .width(this.tokens().containerWidth)
    .height(this.tokens().containerHeight)
    .responseRegion({
      x: this.hitOffsetX(),
      y: (this.tokens().containerHeight - this.hitHeight) / 2,
      width: this.tokens().hitWidth,
      height: this.hitHeight
    })
    .accessibilityText(this.accessibilityLabel())
    .accessibilityChecked(this.completed)
    .accessibilityRole(this.interactive ? AccessibilityRoleType.CHECKBOX : AccessibilityRoleType.CIRCLE)
    .accessibilityLevel(this.interactive ? 'yes' : 'no')
    // 非展示态不参与命中测试：点击穿透给卡片，编辑态仍可选中/打开设置。
    .hitTestBehavior(this.interactive ? HitTestMode.Default : HitTestMode.None)
    .onClick((): void => {
      if (!this.interactive) {
        return;
      }
      // 只做勾选这一件事。点击继续冒泡到卡片后由 ScreensaverPage 的
      // todo 分支吞掉（cardActionAtMs），不会唤出退出胶囊或跳转。
      this.onToggle();
    })
  }
}
