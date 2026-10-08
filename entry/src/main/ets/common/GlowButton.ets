@ComponentV2
export struct ScreenSaverGlowButton {
  @Param label: string = '';
  @Param textColor: string = '#FFFFFF';
  @Param baseColor: string = '#26262B';
  @Param glowColor: string = '#4A9EFF';
  @Param fontSize: number = 13;
  @Param btnHeight: number = 32;
  @Param hPadding: number = 14;
  @Param weight: number = 0;
  @Param marginLeft: number = 0;
  @Param fullWidth: boolean = false;
  @Event onTap: () => void = (): void => {};
  @Local pressed: boolean = false;

  private glowShadowColor(): string {
    if (this.glowColor.length === 7) {
      return '#80' + this.glowColor.substring(1);
    }
    return '#804A9EFF';
  }

  private applyPress(): void {
    this.getUIContext().animateTo({
      duration: 120,
      curve: Curve.EaseOut
    }, (): void => {
      this.pressed = true;
    });
  }

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
    .backgroundColor(this.pressed ? this.glowColor : this.baseColor)
    .shadow(this.pressed
      ? { radius: 14, color: this.glowShadowColor(), offsetX: 0, offsetY: 0 }
      : { radius: 0, color: '#00000000', offsetX: 0, offsetY: 0 })
    .scale({ x: this.pressed ? 0.96 : 1, y: this.pressed ? 0.96 : 1 })
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
