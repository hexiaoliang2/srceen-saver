/**
 * =============================================================================
 * 发光按钮（GlowButton.ets）
 * =============================================================================
 *
 * 【这个文件是干什么的】
 * 一个带「按压反馈」的按钮组件：按下时背景换成发光色、四周出现彩色光晕、
 * 整体缩小到 96%；松手后弹回原样。用于屏保页底部的「＋」胶囊、退出确认弹窗
 * 等需要醒目操作的地方。
 *
 * 【实现要点】
 * 1. 按压状态用 @Local pressed 管理（组件内部状态，外界不需要知道）。
 * 2. 状态变化包在 getUIContext().animateTo(...) 里：这样 pressed 改变时，
 *    背景色/阴影/缩放会以动画过渡（120ms 按下、220ms 回弹），而不是瞬间跳变。
 * 3. 光晕用 shadow（radius=14 的彩色阴影，offset 为 0 即四面向外发光）。
 *    颜色需要 8 位 ARGB（前两位是透明度），所以 glowShadowColor() 会给
 *    传入的 #RRGGBB 拼上 '80'（约 50% 透明度）的前缀。
 * 4. 全部参数（文字、颜色、字号、宽度权重…）都有默认值，方便各处快速使用。
 * =============================================================================
 */

@ComponentV2
export struct ScreenSaverGlowButton {
  // ---------- 可由父组件定制的参数 ----------
  @Param label: string = '';                          // 按钮文字
  @Param textColor: string = '#FFFFFF';               // 文字颜色
  @Param baseColor: string = '#26262B';               // 平时的背景色
  @Param glowColor: string = '#4A9EFF';               // 按下时的发光色
  @Param fontSize: number = 13;
  @Param btnHeight: number = 32;
  @Param hPadding: number = 14;                       // 水平内边距
  @Param weight: number = 0;                          // 布局权重（>0 时参与瓜分剩余空间）
  @Param marginLeft: number = 0;
  @Param fullWidth: boolean = false;                  // 是否占满整行宽
  @Event onTap: () => void = (): void => {};          // 点击回调
  // 按压状态：true 时呈现发光+缩小的「按下态」。
  @Local pressed: boolean = false;

  /**
   * 把 #RRGGBB 转成带透明度的 #80RRGGBB（约 50% 不透明）。
   * 只有标准 7 位格式才转换，非法格式退回默认蓝，保证永不崩溃。
   */
  private glowShadowColor(): string {
    if (this.glowColor.length === 7) {
      return '#80' + this.glowColor.substring(1);
    }
    return '#804A9EFF';
  }

  /** 按下：用 120ms 动画进入按压态（快速响应手指动作）。 */
  private applyPress(): void {
    this.getUIContext().animateTo({
      duration: 120,
      curve: Curve.EaseOut
    }, (): void => {
      this.pressed = true;
    });
  }

  /** 松开：用 220ms 动画回弹（比按下稍慢，回弹感更自然）。 */
  private clearPress(): void {
    this.getUIContext().animateTo({
      duration: 220,
      curve: Curve.EaseOut
    }, (): void => {
      this.pressed = false;
    });
  }

  build() {
    Button() {
      Text(this.label)
        .fontSize(this.fontSize)
        .fontColor(this.textColor)
    }
    .height(this.btnHeight)
    .width(this.fullWidth ? '100%' : 'auto')
    .padding({ left: this.hPadding, right: this.hPadding })
    .margin({ left: this.marginLeft })
    .layoutWeight(this.weight)
    // 按下时背景切到发光色
    .backgroundColor(this.pressed ? this.glowColor : this.baseColor)
    // 按下时显示 14px 半径的彩色光晕（offset 为 0 表示四面向外发光）
    .shadow(this.pressed
      ? { radius: 14, color: this.glowShadowColor(), offsetX: 0, offsetY: 0 }
      : { radius: 0, color: '#00000000', offsetX: 0, offsetY: 0 })
    // 按下时整体缩小到 96%，强化「被按下去」的手感
    .scale({ x: this.pressed ? 0.96 : 1, y: this.pressed ? 0.96 : 1 })
    // 用 onTouch 而不是 onClick 驱动按压态：onClick 只有「完整点击」才回调，
    // 而 onTouch 能捕捉按下/抬起/取消三种时机，按压反馈更跟手。
    .onTouch((event: TouchEvent): void => {
      if (event.type === TouchType.Down) {
        this.applyPress();
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.clearPress();
      }
    })
    .onClick((): void => {
      this.onTap();
    })
  }
}
