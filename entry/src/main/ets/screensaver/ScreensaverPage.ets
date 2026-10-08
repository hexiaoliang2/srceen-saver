import { screenSaverWindowController } from '../common/WindowController';
import { ScreenSaverGlowButton } from '../common/GlowButton';
import { ScreenSaverLogger } from '../common/Logger';
import { screenSaverAppModel } from '../model/AppModel';
import { ScreenSaverCardInstance, ScreenSaverPageConfig } from '../model/ConfigModels';
import { ScreenSaverCardHost } from '../cards/CardHost';

const SCREEN_SAVER_OVERLAY_AUTO_HIDE_MS: number = 6000;

@ComponentV2
struct ScreenSaverPageCanvas {
  @Param page: ScreenSaverPageConfig = new ScreenSaverPageConfig();
  @Param pageIndex: number = 0;

  @Local animatedBg: string = '#000000';

  aboutToAppear(): void {
    this.animatedBg = this.page.ambientColor;
  }

  @Monitor('page.ambientColor')
  onAmbientChanged(): void {
    const target = this.page.ambientColor;
    this.getUIContext().animateTo({
      duration: 800,
      curve: Curve.EaseInOut
    }, (): void => {
      this.animatedBg = target;
    });
  }

  private effectiveBg(): string {
    return screenSaverAppModel.appConfig.settings.ambientColorEnabled ? this.animatedBg : '#000000';
  }

  build() {
    Column() {
      if (this.page.cards.length === 0) {
        Text('请先在编辑器中添加卡片')
          .fontSize(16)
          .fontColor('#666666')
      } else {
        Grid() {
          ForEach(this.page.cards, (card: ScreenSaverCardInstance) => {
            GridItem() {
              ScreenSaverCardHost({
                card: card,
                cardMode: 'play',
                pageIndex: this.pageIndex,
                cardActive: true
              })
            }
            .rowStart(card.rowStart)
            .rowEnd(card.rowStart + card.rowSpan - 1)
            .columnStart(card.colStart)
            .columnEnd(card.colStart + card.colSpan - 1)
          }, (card: ScreenSaverCardInstance): string => card.id)
        }
        .columnsTemplate('1fr 1fr 1fr 1fr')
        .rowsTemplate('1fr 1fr 1fr 1fr 1fr 1fr')
        .width('100%')
        .height('100%')
      }
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.effectiveBg())
  }
}

@ComponentV2
export struct ScreenSaverPlayPage {
  @Param navStack: NavPathStack = new NavPathStack();

  @Local overlayVisible: boolean = false;
  @Local dimmed: boolean = false;

  private dimTimer: number = -1;
  private overlayTimer: number = -1;

  aboutToAppear(): void {
    const context = this.getUIContext().getHostContext();
    if (context !== undefined) {
      void screenSaverWindowController.enter(context);
    }
    this.scheduleDim();
  }

  aboutToDisappear(): void {
    this.stopDimTimer();
    this.stopOverlayTimer();
    const context = this.getUIContext().getHostContext();
    if (context !== undefined) {
      void screenSaverWindowController.exit(context);
    }
  }

  private scheduleDim(): void {
    this.stopDimTimer();
    const settings = screenSaverAppModel.appConfig.settings;
    if (!settings.dimEnabled) {
      return;
    }
    this.dimTimer = setTimeout((): void => {
      this.dimTimer = -1;
      this.dimmed = true;
      const context = this.getUIContext().getHostContext();
      if (context !== undefined) {
        void screenSaverWindowController.setBrightness(context, settings.dimBrightness);
      }
    }, Math.max(5, settings.dimDelaySec) * 1000);
  }

  private stopDimTimer(): void {
    if (this.dimTimer >= 0) {
      clearTimeout(this.dimTimer);
      this.dimTimer = -1;
    }
  }

  private showOverlay(): void {
    this.overlayVisible = true;
    this.stopOverlayTimer();
    this.overlayTimer = setTimeout((): void => {
      this.overlayTimer = -1;
      this.overlayVisible = false;
    }, SCREEN_SAVER_OVERLAY_AUTO_HIDE_MS);
  }

  private stopOverlayTimer(): void {
    if (this.overlayTimer >= 0) {
      clearTimeout(this.overlayTimer);
      this.overlayTimer = -1;
    }
  }

  private handleScreenTap(): void {
    if (this.dimmed) {
      this.dimmed = false;
      const context = this.getUIContext().getHostContext();
      if (context !== undefined) {
        void screenSaverWindowController.setBrightness(context, -1);
      }
      this.showOverlay();
      this.scheduleDim();
      return;
    }
    if (this.overlayVisible) {
      this.overlayVisible = false;
      this.stopOverlayTimer();
      ScreenSaverLogger.info('overlay hidden by tap');
    } else {
      this.showOverlay();
      ScreenSaverLogger.info('overlay shown by tap');
    }
    this.scheduleDim();
  }

  private activePageName(): string {
    const pages = screenSaverAppModel.appConfig.pages;
    if (pages.length === 0) {
      return '';
    }
    return pages[0].name;
  }

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.Top }) {
        if (screenSaverAppModel.appConfig.pages.length === 0) {
          Column() {
            Text('暂无屏保页面，请先在首页新建页面')
              .fontSize(16)
              .fontColor('#666666')
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
        } else {
          ScreenSaverPageCanvas({
            page: screenSaverAppModel.appConfig.pages[0],
            pageIndex: 0
          })
        }

        if (this.overlayVisible) {
          Row() {
            Text(`当前屏保：${this.activePageName()}`)
              .fontSize(14)
              .fontColor('#CCCCCC')
            Blank()
            ScreenSaverGlowButton({
              label: '退出',
              textColor: '#E6E6E6',
              baseColor: '#33FFFFFF',
              glowColor: '#66FFFFFF',
              hPadding: 16,
              onTap: (): void => {
                ScreenSaverLogger.info('exit screensaver requested');
                this.navStack.pop();
              }
            })
          }
          .width('100%')
          .padding({ left: 20, right: 20, top: 16 })
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#000000')
      .onClick((): void => {
        this.handleScreenTap();
      })
    }
    .hideTitleBar(true)
    .backgroundColor('#000000')
  }
}
