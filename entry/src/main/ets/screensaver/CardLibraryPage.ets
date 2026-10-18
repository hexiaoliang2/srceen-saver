/**
 * =============================================================================
 * 卡片库页面（CardLibraryPage.ets）
 * =============================================================================
 *
 * 【这个文件是干什么的】
 * 「添加卡片」页面：列出四种可添加的卡片（时钟/相册/视频/Git），
 * 每种显示名称、描述和当前添加状态，点「添加」把它加进屏保布局。
 *
 * 【添加的三道防线】
 *   1. 添加前：addCard() 先问 cardAddBlockedReason()——
 *      唯一卡片（时钟/Git）重复添加、空间不足都会被拦截并 toast 原因，
 *      用户明确知道为什么加不了；
 *   2. 界面上：uniqueAdded() 让已添加的唯一卡片直接显示「已添加」
 *      置灰按钮（点不了），从源头减少无效操作；
 *   3. 添加后：addCard 返回 false（兜底）也给出提示。
 *
 * 【页脚提示】
 * 「时钟 / Git 最多添加一张，相册 / 视频可添加多张」——
 * 把业务规则明明白白写出来，用户不用猜。
 * =============================================================================
 */

import { ScreenSaverLogger } from '../common/Logger';
import { SCREEN_SAVER_COLORS } from '../common/ScreenSaverStyle';
import { screenSaverAppModel } from '../model/AppModel';
import { SCREEN_SAVER_CARD_CATALOG } from '../cards/CardCatalog';
import { ScreensaverCardMeta } from '../model/ConfigModels';

@ComponentV2
export struct ScreenSaverCardLibraryPage {
  @Param navStack: NavPathStack = new NavPathStack();

  /**
   * 添加一张卡片：
   * 先查拦截原因（唯一重复/空间不足）→ 拦截就 toast 原因；
   * 通过则真正添加，失败兜底提示；成功 toast 确认。
   */
  private addCard(meta: ScreensaverCardMeta): void {
    const reason = screenSaverAppModel.cardAddBlockedReason(meta.cardType);
    if (reason.length > 0) {
      this.toast(reason);
      return;
    }
    const added = screenSaverAppModel.addCard(meta.cardType);
    ScreenSaverLogger.info(`library add ${meta.cardType}: ${added}`);
    if (!added) {
      this.toast('空间不足：请先移出或缩小卡片');
      return;
    }
    this.toast(`已添加${meta.displayName}卡片`);
  }

  /** 唯一卡片是否已添加（已添加则显示置灰的「已添加」按钮）。 */
  private uniqueAdded(meta: ScreensaverCardMeta): boolean {
    return meta.unique && screenSaverAppModel.cardsOfType(meta.cardType).length > 0;
  }

  /** 卡片下方的状态文案：未添加时带默认尺寸说明。 */
  private countOf(meta: ScreensaverCardMeta): string {
    const count = screenSaverAppModel.cardsOfType(meta.cardType).length;
    if (count === 0) {
      return `${meta.defaultColSpan}×${meta.defaultRowSpan} · 未添加`;
    }
    if (meta.unique) {
      return '已添加';
    }
    return `已添加 ×${count}`;
  }

  /** 弹 toast 提示。 */
  private toast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message, duration: 1500 });
    } catch (err) {
      const error = err as Error;
      ScreenSaverLogger.warn(`toast failed: ${error.message}`);
    }
  }

  /**
   * 界面结构（Column 纵向）：
   *   自绘顶栏（返回 + 标题）→ 说明文字 → 卡片列表 → 页脚规则说明。
   * 顶栏用 Row 手绘而不是系统标题栏：样式更自由，返回热区也更大。
   */
  build() {
    NavDestination() {
      Column() {
        // ---------- 自绘顶栏 ----------
        Row() {
          Text('返回')
            .fontSize(14)
            .fontColor('#CCCCCC')
            .padding({ left: 16, right: 12, top: 12, bottom: 12 })
            .onClick((): void => {
              this.navStack.pop();
            })
          Blank()
          Text('添加卡片')
            .fontSize(16)
            .fontColor(SCREEN_SAVER_COLORS.textPrimary)
          Blank()
          // 右侧占位：让标题真正居中（左边「返回」有宽度，右边要补齐）
          Text('')
            .width(40)
        }
        .width('100%')

        // ---------- 说明文字 ----------
        Text('选择要加入屏保的卡片')
          .fontSize(12)
          .fontColor(SCREEN_SAVER_COLORS.textTertiary)
          .width('100%')
          .padding({ left: 16, right: 16, bottom: 8 })

        // ---------- 卡片列表 ----------
        // 遍历卡片目录渲染；右侧按钮按「唯一已添加」状态切换置灰/可点。
        List({ space: 10 }) {
          ForEach(SCREEN_SAVER_CARD_CATALOG, (meta: ScreensaverCardMeta) => {
            ListItem() {
              Row() {
                Column() {
                  Text(meta.displayName)
                    .fontSize(15)
                    .fontColor(SCREEN_SAVER_COLORS.textPrimary)
                  Text(meta.description)
                    .fontSize(11)
                    .fontColor(SCREEN_SAVER_COLORS.textTertiary)
                    .margin({ top: 3 })
                  Text(this.countOf(meta))
                    .fontSize(11)
                    .fontColor('#8AB4F8')
                    .margin({ top: 3 })
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
                if (this.uniqueAdded(meta)) {
                  // 唯一卡片已添加：置灰不可点
                  Text('已添加')
                    .fontSize(13)
                    .fontColor(SCREEN_SAVER_COLORS.textTertiary)
                    .padding({ left: 14, right: 14, top: 8, bottom: 8 })
                    .borderRadius(8)
                    .backgroundColor(SCREEN_SAVER_COLORS.divider)
                } else {
                  // 可添加：蓝色实底按钮
                  Text('添加')
                    .fontSize(13)
                    .fontColor(SCREEN_SAVER_COLORS.white)
                    .padding({ left: 14, right: 14, top: 8, bottom: 8 })
                    .borderRadius(8)
                    .backgroundColor(SCREEN_SAVER_COLORS.accentStrong)
                    .onClick((): void => {
                      this.addCard(meta);
                    })
                }
              }
              .width('100%')
              .padding(14)
              .borderRadius(10)
              .backgroundColor(SCREEN_SAVER_COLORS.bgElevated)
            }
          }, (meta: ScreensaverCardMeta): string => meta.cardType)
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 16, right: 16 })

        // ---------- 页脚规则说明 ----------
        Text('时钟 / Git 最多添加一张；相册 / 视频 / 天气 / 入口 / 行情 / 倒计时 / 待办可添加多张 · 添加后在编辑模式调整位置与尺寸')
          .fontSize(11)
          .fontColor(SCREEN_SAVER_COLORS.textTertiary)
          .padding({ top: 12, bottom: 20 })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(SCREEN_SAVER_COLORS.bg)
    }
    .hideTitleBar(true)
    .backgroundColor(SCREEN_SAVER_COLORS.bg)
  }
}
