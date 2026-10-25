/**
 * =============================================================================
 * 半模态设置面板的通用小部件（SheetParts.ets）
 * =============================================================================
 *
 * 【这个文件是干什么的】
 * 四个设置面板（时钟 / 相册 / 视频 / Git）都会用到的界面积木：
 *   - ScreenSaverSheetHeader    面板顶栏（标题 + 「完成」按钮）
 *   - ScreenSaverChip           选项小胶囊（时间格式、刷新频率等单选项）
 *   - ScreenSaverToggleRow      「标签 + 说明 + 开关」整行
 *   - ScreenSaverDeleteCardRow  底部的「删除卡片」按钮
 *
 * 【为什么要抽出来】
 * 四个面板如果各自写一遍这些样式，改一次样式要改四处，还容易改得不一致。
 * 抽成公共组件后，「一处定义、四处复用」，风格天然统一。
 * =============================================================================
 */

import { SCREEN_SAVER_COLORS } from './ScreenSaverStyle';


/**
 * 面板顶栏：左边标题、右边「完成」。
 * 所有参数都给默认值（包括 onDone 空函数），这样父组件漏传也不会报错。
 */
@ComponentV2
export struct ScreenSaverSheetHeader {
  @Param title: string = '';
  @Event onDone: () => void = (): void => {};

  build() {
    Row() {
      Text(this.title)
        .fontSize(15)
        .fontColor(SCREEN_SAVER_COLORS.textPrimary)
      // Blank 占据中间所有空隙，把「完成」推到最右侧。
      Blank()
      Text('完成')
        .fontSize(14)
        .fontColor(SCREEN_SAVER_COLORS.accent)
        // 给文字周围留出较大的点击热区，手指好按。
        .padding({ left: 12, right: 4, top: 11, bottom: 11 })
        .onClick((): void => {
          this.onDone();
        })
    }
    .width('100%')
  }
}

/**
 * 选项小胶囊：选中态高亮、未选中灰底、禁用态半透明。
 * chipEnabled=false 时点击直接拦截（只改透明度还不够，必须不回调），
 * 避免「看起来不能点、点下去却有反应」的困惑。
 */
@ComponentV2
export struct ScreenSaverChip {
  @Param label: string = '';
  @Param selected: boolean = false;
  @Param chipEnabled: boolean = true;
  @Event onTap: () => void = (): void => {};

  build() {
    Column() {
      Text(this.label)
        .fontSize(12)
        // 三态颜色：选中白字 / 可用灰字 / 禁用深灰字
        .fontColor(this.selected ? SCREEN_SAVER_COLORS.white :
          (this.chipEnabled ? '#BBBBBB' : '#55555A'))
        .padding({ left: 12, right: 12, top: 6, bottom: 6 })
        .borderRadius(8)
        // 选中时用强调色实底，未选中用分隔线灰底
        .backgroundColor(this.selected ? SCREEN_SAVER_COLORS.accentStrong : SCREEN_SAVER_COLORS.divider)
    }
    // 最小 40vp：既保证可点击区域足够大，又统一了行内所有胶囊的高度节奏。
    .constraintSize({ minWidth: 40, minHeight: 40 })
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .opacity(this.chipEnabled ? 1 : 0.5) // 禁用态整体半透明提示「不可用」
    .onClick((): void => {
      if (this.chipEnabled) {
        this.onTap();
      }
    })
  }
}

/**
 * 「标签 + 小字说明 + 开关」整行。
 * tip 为空字符串时不渲染说明行，面板传参可以按需省略。
 */
@ComponentV2
export struct ScreenSaverToggleRow {
  @Param label: string = '';
  @Param tip: string = '';
  @Param isOn: boolean = false;
  /** 整行是否可用；不可用时开关置灰且不回调（用于传感器不支持等场景）。 */
  @Param rowEnabled: boolean = true;
  @Event onChange: (value: boolean) => void = (value: boolean): void => {};

  build() {
    Row() {
      Column() {
        Text(this.label)
          .fontSize(14)
          .fontColor('#CCCCCC')
        // 说明文字（可选）：比如「开启后持续解码渲染」这种给用户看的提醒。
        if (this.tip.length > 0) {
          Text(this.tip)
            .fontSize(11)
            .fontColor(SCREEN_SAVER_COLORS.textTertiary)
            .margin({ top: 2 })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1) // 文字区占满剩余宽度，开关始终靠右
      Toggle({ type: ToggleType.Switch, isOn: this.isOn })
        .selectedColor(SCREEN_SAVER_COLORS.accentStrong)
        .enabled(this.rowEnabled)
        .opacity(this.rowEnabled ? 1 : 0.45)
        .onChange((value: boolean): void => {
          if (this.rowEnabled) {
            this.onChange(value);
          }
        })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }
}

/**
 * 「删除卡片」按钮：红字、整行居中、深色底。
 * 独立成组件是因为删除是危险操作，视觉上要和普通开关行明显区分。
 */
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
    .padding({ top: 12, bottom: 12 })
    .borderRadius(8)
    .backgroundColor('#1C1C20')
    .onClick((): void => {
      this.onDelete();
    })
  }
}
