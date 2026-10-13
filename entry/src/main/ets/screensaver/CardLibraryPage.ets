import { ScreenSaverLogger } from '../common/Logger';
import { SCREEN_SAVER_COLORS } from '../common/ScreenSaverStyle';
import { screenSaverAppModel } from '../model/AppModel';
import { SCREEN_SAVER_CARD_CATALOG } from '../cards/CardCatalog';
import { ScreensaverCardMeta } from '../model/ConfigModels';

@ComponentV2
export struct ScreenSaverCardLibraryPage {
  @Param navStack: NavPathStack = new NavPathStack();

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

  private uniqueAdded(meta: ScreensaverCardMeta): boolean {
    return meta.unique && screenSaverAppModel.cardsOfType(meta.cardType).length > 0;
  }

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

  private toast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message, duration: 1500 });
    } catch (err) {
      const error = err as Error;
      ScreenSaverLogger.warn(`toast failed: ${error.message}`);
    }
  }

  build() {
    NavDestination() {
      Column() {
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
          Text('')
            .width(40)
        }
        .width('100%')

        Text('选择要加入屏保的卡片')
          .fontSize(12)
          .fontColor(SCREEN_SAVER_COLORS.textTertiary)
          .width('100%')
          .padding({ left: 16, right: 16, bottom: 8 })

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
                  Text('已添加')
                    .fontSize(13)
                    .fontColor(SCREEN_SAVER_COLORS.textTertiary)
                    .padding({ left: 14, right: 14, top: 8, bottom: 8 })
                    .borderRadius(8)
                    .backgroundColor(SCREEN_SAVER_COLORS.divider)
                } else {
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

        Text('时钟 / Git 最多添加一张，相册 / 视频可添加多张 · 添加后在编辑模式调整位置与尺寸')
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
