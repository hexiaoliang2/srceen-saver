import { SCREEN_SAVER_COLORS } from '../common/ScreenSaverStyle';
import { screenSaverAppModel } from '../model/AppModel';
import { ScreensaverClockCard } from '../cards/ClockCardView';
import { ScreensaverCardInstance } from '../model/ConfigModels';

function buildGuideClockCard(): ScreensaverCardInstance {
  const card = new ScreensaverCardInstance();
  card.id = 'guide_clock';
  card.cardType = 'clock';
  card.colSpan = 4;
  card.rowSpan = 2;
  card.clock.format = 'timeDate';
  return card;
}

@ComponentV2
export struct ScreenSaverGuidePage {
  @Param navStack: NavPathStack = new NavPathStack();
  @Local guideCard: ScreensaverCardInstance = buildGuideClockCard();

  private finishGuide(): void {
    screenSaverAppModel.markGuideDone();
    this.navStack.pop();
  }

  build() {
    NavDestination() {
      Column() {
        Column({ space: 14 }) {
          Column() {
            ScreensaverClockCard({ card: this.guideCard, cardMode: 'play' })
          }
          .width('80%')
          .height(120)
          .borderRadius(12)
          .backgroundColor(SCREEN_SAVER_COLORS.cardBg)
          .clip(true)

          Row({ space: 12 }) {
            Column() {
              Text('视频')
                .fontSize(13)
                .fontColor('#DDDDDD')
            }
            .width(72)
            .height(72)
            .borderRadius(14)
            .backgroundColor(SCREEN_SAVER_COLORS.bgElevated)
            .justifyContent(FlexAlign.Center)

            Column() {
              Text('照片')
                .fontSize(13)
                .fontColor('#DDDDDD')
            }
            .width(72)
            .height(72)
            .borderRadius(14)
            .backgroundColor(SCREEN_SAVER_COLORS.bgElevated)
            .justifyContent(FlexAlign.Center)
          }

          Text('应用内屏保')
            .fontSize(22)
            .fontWeight(FontWeight.Medium)
            .fontColor(SCREEN_SAVER_COLORS.textPrimary)
            .margin({ top: 6 })

          Column({ space: 6 }) {
            Text('全屏展示 · 保持亮屏')
              .fontSize(13)
              .fontColor(SCREEN_SAVER_COLORS.textSecondary)
            Text('卡片自由布局与高度自定义')
              .fontSize(13)
              .fontColor(SCREEN_SAVER_COLORS.textSecondary)
            Text('深色省电 · 静态优先设计')
              .fontSize(13)
              .fontColor(SCREEN_SAVER_COLORS.textSecondary)
            Text('单击呼出退出 · 长按进入编辑')
              .fontSize(13)
              .fontColor(SCREEN_SAVER_COLORS.textSecondary)
          }

          Text('开始使用')
            .fontSize(15)
            .fontColor(SCREEN_SAVER_COLORS.white)
            .width('70%')
            .textAlign(TextAlign.Center)
            .padding({ top: 12, bottom: 12 })
            .borderRadius(22)
            .backgroundColor(SCREEN_SAVER_COLORS.accentStrong)
            .margin({ top: 16 })
            .onClick((): void => {
              this.finishGuide();
            })

          Text('跳过')
            .fontSize(13)
            .fontColor(SCREEN_SAVER_COLORS.textTertiary)
            .padding({ top: 8, bottom: 8 })
            .onClick((): void => {
              this.finishGuide();
            })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      }
      .width('100%')
      .height('100%')
      .padding({ left: 24, right: 24 })
      .backgroundColor(SCREEN_SAVER_COLORS.bg)
    }
    .hideTitleBar(true)
    .backgroundColor(SCREEN_SAVER_COLORS.bg)
  }
}
