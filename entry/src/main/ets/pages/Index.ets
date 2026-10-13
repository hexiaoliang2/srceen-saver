import { ScreenSaverLogger } from '../common/Logger';
import { SCREEN_SAVER_COLORS } from '../common/ScreenSaverStyle';
import { screenSaverAppModel } from '../model/AppModel';
import { screenSaverCardTypeName } from '../cards/CardCatalog';
import { ScreensaverCardHost } from '../cards/CardHost';
import { ScreenSaverPlayPage } from '../screensaver/ScreensaverPage';
import { ScreenSaverSettingsPage } from '../screensaver/SettingsPage';
import { ScreenSaverGuidePage } from '../screensaver/GuidePage';
import { ScreenSaverCardLibraryPage } from '../screensaver/CardLibraryPage';
import { ScreensaverLaunchParam, ScreensaverCardInstance } from '../model/ConfigModels';

@ComponentV2
struct ScreenSaverConsole {
  @Param navStack: NavPathStack = new NavPathStack();

  private startScreensaver(): void {
    const param: ScreensaverLaunchParam = { from: 'home' };
    this.navStack.pushPathByName('screensaver', param);
  }

  private cardTitle(card: ScreensaverCardInstance): string {
    const name = screenSaverCardTypeName(card.cardType);
    const sameType = screenSaverAppModel.cardsOfType(card.cardType);
    if (sameType.length > 1) {
      const index = sameType.findIndex((item: ScreensaverCardInstance): boolean => item.id === card.id);
      if (index >= 0) {
        return `${name} ${index + 1}`;
      }
    }
    return name;
  }

  private toast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message, duration: 1500 });
    } catch (err) {
      const error = err as Error;
      ScreenSaverLogger.warn(`toast failed: ${error.message}`);
    }
  }

  @Builder
  previewCard() {
    Column({ space: 6 }) {
      ForEach(screenSaverAppModel.layout.cards.slice(0, 3), (card: ScreensaverCardInstance) => {
        if (card.enabled) {
          Column() {
            ScreensaverCardHost({
              card: card,
              cardMode: 'edit',
              cardActive: false
            })
          }
          .width('100%')
          .height(card.cardType === 'clock' ? 56 : 44)
          .borderRadius(8)
          .backgroundColor(SCREEN_SAVER_COLORS.cardBg)
          .clip(true)
        } else {
          Row() {
            Text(`${this.cardTitle(card)} · 已停用`)
              .fontSize(11)
              .fontColor(SCREEN_SAVER_COLORS.textTertiary)
          }
          .width('100%')
          .height(card.cardType === 'clock' ? 56 : 44)
          .borderRadius(8)
          .border({
            width: 1,
            color: '#33FFFFFF',
            style: BorderStyle.Dashed
          })
          .justifyContent(FlexAlign.Center)
        }
      }, (card: ScreensaverCardInstance): string => card.id)
      if (screenSaverAppModel.layout.cards.length === 0) {
        Text('还没有卡片 · 点「＋ 添加卡片」加入')
          .fontSize(12)
          .fontColor(SCREEN_SAVER_COLORS.textTertiary)
          .height(56)
      }
      Row() {
        Text(`当前布局 · ${screenSaverAppModel.layout.cards.length} 张卡片`)
          .fontSize(11)
          .fontColor(SCREEN_SAVER_COLORS.textTertiary)
      }
      .width('100%')
    }
    .width('100%')
    .padding(12)
    .borderRadius(12)
    .backgroundColor(SCREEN_SAVER_COLORS.bgElevated)
  }

  @Builder
  addCardRow() {
    Row() {
      Text('＋ 添加卡片')
        .fontSize(14)
        .fontColor(SCREEN_SAVER_COLORS.accent)
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .padding({ top: 13, bottom: 13 })
    .borderRadius(10)
    .backgroundColor(SCREEN_SAVER_COLORS.bgElevated)
    .onClick((): void => {
      this.navStack.pushPathByName('library', '');
    })
  }

  build() {
    Scroll() {
      Column({ space: 14 }) {
        Column({ space: 4 }) {
          Text('屏保')
            .fontSize(20)
            .fontWeight(FontWeight.Medium)
            .fontColor(SCREEN_SAVER_COLORS.textPrimary)
            .width('100%')
          Text('应用内全屏展示')
            .fontSize(12)
            .fontColor(SCREEN_SAVER_COLORS.textTertiary)
            .width('100%')
        }
        .width('100%')

        this.previewCard()

        Text('开启屏保')
          .fontSize(16)
          .fontColor(SCREEN_SAVER_COLORS.white)
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ top: 14, bottom: 14 })
          .borderRadius(26)
          .backgroundColor(SCREEN_SAVER_COLORS.accentStrong)
          .onClick((): void => {
            this.startScreensaver();
          })

        Row() {
          Text('我的卡片')
            .fontSize(15)
            .fontColor(SCREEN_SAVER_COLORS.textPrimary)
          Blank()
          Text('开关控制是否显示')
            .fontSize(11)
            .fontColor(SCREEN_SAVER_COLORS.textTertiary)
        }
        .width('100%')

        ForEach(screenSaverAppModel.layout.cards, (card: ScreensaverCardInstance) => {
          Row() {
            Column() {
              Text(this.cardTitle(card))
                .fontSize(14)
                .fontColor(SCREEN_SAVER_COLORS.textPrimary)
              Text(screenSaverAppModel.cardInstanceSummary(card))
                .fontSize(11)
                .fontColor(SCREEN_SAVER_COLORS.textTertiary)
                .margin({ top: 2 })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: card.enabled })
              .selectedColor(SCREEN_SAVER_COLORS.accentStrong)
              .onChange((value: boolean): void => {
                screenSaverAppModel.setCardEnabled(card.id, value);
              })
          }
          .width('100%')
          .padding(14)
          .borderRadius(10)
          .backgroundColor(SCREEN_SAVER_COLORS.bgElevated)
        }, (card: ScreensaverCardInstance): string => card.id)

        this.addCardRow()

        Row() {
          Text('设置')
            .fontSize(14)
            .fontColor('#CCCCCC')
            .layoutWeight(1)
          Text('间隔 / 字号 / 权限')
            .fontSize(11)
            .fontColor(SCREEN_SAVER_COLORS.textTertiary)
          Text('›')
            .fontSize(16)
            .fontColor(SCREEN_SAVER_COLORS.textTertiary)
            .margin({ left: 8 })
        }
        .width('100%')
        .padding(14)
        .borderRadius(10)
        .backgroundColor(SCREEN_SAVER_COLORS.bgElevated)
        .onClick((): void => {
          this.navStack.pushPathByName('settings', '');
        })

        Text('v0.1 · 深色省电 · 静态优先')
          .fontSize(11)
          .fontColor(SCREEN_SAVER_COLORS.textTertiary)
          .margin({ top: 4, bottom: 24 })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12 })
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .backgroundColor(SCREEN_SAVER_COLORS.bg)
  }
}

@Entry
@ComponentV2
struct Index {
  @Local navStack: NavPathStack = new NavPathStack();

  aboutToAppear(): void {
    screenSaverAppModel.whenLoaded((): void => {
      if (!screenSaverAppModel.isGuideDone()) {
        this.navStack.pushPathByName('guide', '');
      }
    });
  }

  @Builder
  pageMap(name: string) {
    if (name === 'screensaver') {
      ScreenSaverPlayPage({ navStack: this.navStack })
    } else if (name === 'settings') {
      ScreenSaverSettingsPage({ navStack: this.navStack })
    } else if (name === 'guide') {
      ScreenSaverGuidePage({ navStack: this.navStack })
    } else if (name === 'library') {
      ScreenSaverCardLibraryPage({ navStack: this.navStack })
    }
  }

  build() {
    Navigation(this.navStack) {
      ScreenSaverConsole({ navStack: this.navStack })
    }
    .title('屏保')
    .titleMode(NavigationTitleMode.Mini)
    .mode(NavigationMode.Stack)
    .navDestination(this.pageMap)
    .backgroundColor(SCREEN_SAVER_COLORS.bg)
  }
}
