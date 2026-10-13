/**
 * =============================================================================
 * 新手引导页（GuidePage.ets）
 * =============================================================================
 *
 * 【这个文件是干什么的】
 * 首次启动应用时展示的一页式引导：预览效果（时钟卡片示例）+ 四条核心
 * 特性说明 + 「开始使用」按钮。用户点「开始使用」或「跳过」后记录
 * 「引导已完成」，之后不再出现。
 *
 * 【引导状态的判断】
 * AppModel.isGuideDone() 读取持久化标记；Index 页面据此决定先跳引导
 * 还是直接进主界面。本页只负责展示和落标记（markGuideDone）。
 *
 * 【示例卡片是「真组件」】
 * 预览里的时钟不是截图，而是直接实例化了一个 ScreensaverCardInstance
 * 传给真实的时钟卡片组件——引导页看到的效果和实际使用完全一致，
 * 也顺带演示了「卡片就是这样工作的」。
 * =============================================================================
 */

import { SCREEN_SAVER_COLORS } from '../common/ScreenSaverStyle';
import { screenSaverAppModel } from '../model/AppModel';
import { ScreensaverClockCard } from '../cards/ClockCardView';
import { ScreensaverCardInstance } from '../model/ConfigModels';

/**
 * 构造引导页用的示例时钟卡片：
 * id 用 'guide_clock' 与用户真实卡片区分（不进布局、不持久化）。
 */
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
  /** 导航栈（由路由表传入，用于返回/pop）。 */
  @Param navStack: NavPathStack = new NavPathStack();
  /** 引导用的示例时钟卡实例。 */
  @Local guideCard: ScreensaverCardInstance = buildGuideClockCard();

  /**
   * 完成引导：先落持久化标记（下次启动不再进引导页），再退出本页。
   * 「开始使用」和「跳过」走同一个方法——两者唯一区别就是按钮文案，
   * 都代表「用户看完了」。
   */
  private finishGuide(): void {
    screenSaverAppModel.markGuideDone();
    this.navStack.pop();
  }

  build() {
    NavDestination() {
      Column() {
        Column({ space: 14 }) {
          // ---------- 预览效果区 ----------
          // 真实的时钟卡片组件（深色卡片底 + 圆角 + 裁剪），展示实际观感。
          Column() {
            ScreensaverClockCard({ card: this.guideCard, cardMode: 'play' })
          }
          .width('80%')
          .height(120)
          .borderRadius(12)
          .backgroundColor(SCREEN_SAVER_COLORS.cardBg)
          .clip(true)

          // ---------- 卡片类型示意（视频 / 照片） ----------
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

          // ---------- 标题与特性说明 ----------
          Text('应用内屏保')
            .fontSize(22)
            .fontWeight(FontWeight.Medium)
            .fontColor(SCREEN_SAVER_COLORS.textPrimary)
            .margin({ top: 6 })

          Column({ space: 6 }) {
            // 四条核心特性：亮屏、自由布局、省电设计、交互方式。
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

          // ---------- 「开始使用」主按钮 ----------
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

          // ---------- 「跳过」次要入口 ----------
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
