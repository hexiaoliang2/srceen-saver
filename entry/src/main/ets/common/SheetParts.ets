import { SCREEN_SAVER_COLORS } from './ScreenSaverStyle';

@ComponentV2
export struct ScreenSaverSheetHeader {
  @Param title: string = '';
  @Event onDone: () => void = (): void => {};

  build() {
    Row() {
      Text(this.title)
        .fontSize(15)
        .fontColor(SCREEN_SAVER_COLORS.textPrimary)
      Blank()
      Text('完成')
        .fontSize(14)
        .fontColor(SCREEN_SAVER_COLORS.accent)
        .padding({ left: 12, right: 2, top: 4, bottom: 4 })
        .onClick((): void => {
          this.onDone();
        })
    }
    .width('100%')
  }
}

@ComponentV2
export struct ScreenSaverChip {
  @Param label: string = '';
  @Param selected: boolean = false;
  @Param chipEnabled: boolean = true;
  @Event onTap: () => void = (): void => {};

  build() {
    Text(this.label)
      .fontSize(12)
      .fontColor(this.selected ? SCREEN_SAVER_COLORS.white :
        (this.chipEnabled ? '#BBBBBB' : '#55555A'))
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .borderRadius(8)
      .backgroundColor(this.selected ? SCREEN_SAVER_COLORS.accentStrong : SCREEN_SAVER_COLORS.divider)
      .opacity(this.chipEnabled ? 1 : 0.5)
      .onClick((): void => {
        if (this.chipEnabled) {
          this.onTap();
        }
      })
  }
}

@ComponentV2
export struct ScreenSaverToggleRow {
  @Param label: string = '';
  @Param tip: string = '';
  @Param isOn: boolean = false;
  @Event onChange: (value: boolean) => void = (value: boolean): void => {};

  build() {
    Row() {
      Column() {
        Text(this.label)
          .fontSize(14)
          .fontColor('#CCCCCC')
        if (this.tip.length > 0) {
          Text(this.tip)
            .fontSize(11)
            .fontColor(SCREEN_SAVER_COLORS.textTertiary)
            .margin({ top: 2 })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: this.isOn })
        .selectedColor(SCREEN_SAVER_COLORS.accentStrong)
        .onChange((value: boolean): void => {
          this.onChange(value);
        })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }
}

@ComponentV2
export struct ScreenSaverDeleteCardRow {
  @Event onDelete: () => void = (): void => {};

  build() {
    Row() {
      Text('删除卡片')
        .fontSize(14)
        .fontColor(SCREEN_SAVER_COLORS.danger)
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .padding({ top: 10, bottom: 10 })
    .borderRadius(8)
    .backgroundColor('#1C1C20')
    .onClick((): void => {
      this.onDelete();
    })
  }
}
