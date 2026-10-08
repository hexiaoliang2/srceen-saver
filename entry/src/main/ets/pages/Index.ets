import { curves } from '@kit.ArkUI';
import { ScreenSaverGlowButton } from '../common/GlowButton';
import { ScreenSaverLogger } from '../common/Logger';
import { screenSaverAppModel } from '../model/AppModel';
import { ScreenSaverEditorPage } from '../screensaver/EditorPage';
import { ScreenSaverPlayPage } from '../screensaver/ScreensaverPage';
import {
  SCREEN_SAVER_MAX_PAGES,
  ScreenSaverEditorParam,
  ScreenSaverLaunchParam,
  ScreenSaverNumberOption,
  ScreenSaverPageConfig
} from '../model/ConfigModels';

const SCREEN_SAVER_DIM_DELAY_OPTIONS: ScreenSaverNumberOption[] = [
  { value: 30, label: '30 秒' },
  { value: 60, label: '60 秒' },
  { value: 120, label: '120 秒' }
];

const SCREEN_SAVER_DIM_BRIGHTNESS_OPTIONS: ScreenSaverNumberOption[] = [
  { value: 0.1, label: '10%' },
  { value: 0.25, label: '25%' },
  { value: 0.5, label: '50%' }
];

@Entry
@ComponentV2
struct Index {
  @Local navStack: NavPathStack = new NavPathStack();
  @Local bouncePageId: string = '';
  @Local bounceScale: number = 1;

  @Builder
  pageMap(name: string, param: Object) {
    if (name === 'screensaver') {
      ScreenSaverPlayPage({ navStack: this.navStack })
    } else if (name === 'editor') {
      ScreenSaverEditorPage({
        navStack: this.navStack,
        pageIndex: (param as ScreenSaverEditorParam).pageIndex
      })
    }
  }

  private startScreensaver(): void {
    const param: ScreenSaverLaunchParam = { from: 'home' };
    this.navStack.pushPathByName('screensaver', param);
  }

  private openEditor(pageIndex: number): void {
    const param: ScreenSaverEditorParam = { pageIndex: pageIndex };
    this.navStack.pushPathByName('editor', param);
  }

  private addPage(): void {
    const added = screenSaverAppModel.addPage();
    if (!added) {
      this.toast(`最多支持 ${SCREEN_SAVER_MAX_PAGES} 个页面`);
    }
  }

  private pinPage(pageId: string): void {
    const pinned = screenSaverAppModel.pinPageToTop(pageId);
    if (!pinned) {
      return;
    }
    this.playBounce(pageId);
  }

  private playBounce(pageId: string): void {
    this.bouncePageId = pageId;
    this.bounceScale = 1;
    this.getUIContext().animateTo({
      duration: 180,
      curve: Curve.EaseOut
    }, (): void => {
      this.bounceScale = 1.05;
    });
    setTimeout((): void => {
      this.getUIContext().animateTo({
        curve: curves.springCurve(10, 1, 228, 30)
      }, (): void => {
        this.bounceScale = 1.0;
      });
      setTimeout((): void => {
        this.bouncePageId = '';
      }, 600);
    }, 190);
  }

  private toast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message, duration: 1500 });
    } catch (err) {
      const error = err as Error;
      ScreenSaverLogger.warn(`showToast failed: ${error.message}`);
    }
  }

  build() {
    Navigation(this.navStack) {
      Scroll() {
        Column({ space: 16 }) {
          Column({ space: 6 }) {
            Text('低功耗自定义屏保：时钟与相册自由组合')
              .fontSize(13)
              .fontColor('#888888')
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)

          ScreenSaverGlowButton({
            label: '启动屏保',
            textColor: '#FFFFFF',
            baseColor: '#3D6FBF',
            glowColor: '#5B87D9',
            fontSize: 16,
            btnHeight: 48,
            hPadding: 24,
            fullWidth: true,
            onTap: (): void => {
              this.startScreensaver();
            }
          })

          Row() {
            Text('屏保页面')
              .fontSize(15)
              .fontColor('#F2F2F2')
            Blank()
            Text(`${screenSaverAppModel.appConfig.pages.length} / ${SCREEN_SAVER_MAX_PAGES}`)
              .fontSize(12)
              .fontColor('#777777')
          }
          .width('100%')

          Text('屏保仅播放列表顶部的页面，点击「置顶」可切换启用的屏保页')
            .fontSize(11)
            .fontColor('#777777')
            .width('100%')

          if (screenSaverAppModel.appConfig.pages.length === 0) {
            Column() {
              Text('还没有页面，点击下方按钮新建')
                .fontSize(13)
                .fontColor('#777777')
            }
            .width('100%')
            .padding(20)
            .borderRadius(10)
            .backgroundColor('#1A1A1E')
          }

          ForEach(screenSaverAppModel.appConfig.pages, (page: ScreenSaverPageConfig, index: number) => {
            Row() {
              Column() {
                Row() {
                  Text(page.name)
                    .fontSize(14)
                    .fontColor('#F2F2F2')
                  if (index === 0) {
                    Text('当前启用')
                      .fontSize(10)
                      .fontColor('#0E0E10')
                      .padding({ left: 6, right: 6, top: 1, bottom: 1 })
                      .borderRadius(4)
                      .backgroundColor('#7BD88F')
                      .margin({ left: 6 })
                  }
                }
                Text(screenSaverAppModel.pageSummary(page))
                  .fontSize(11)
                  .fontColor('#888888')
                  .margin({ top: 2 })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
              if (index > 0) {
                ScreenSaverGlowButton({
                  label: '置顶',
                  textColor: '#8AB4F8',
                  glowColor: '#4A9EFF',
                  btnHeight: 30,
                  hPadding: 12,
                  onTap: (): void => {
                    this.pinPage(page.id);
                  }
                })
              }
              ScreenSaverGlowButton({
                label: '编辑',
                textColor: '#8AB4F8',
                glowColor: '#4A9EFF',
                btnHeight: 30,
                hPadding: 12,
                marginLeft: 8,
                onTap: (): void => {
                  this.openEditor(index);
                }
              })
              ScreenSaverGlowButton({
                label: '删除',
                textColor: '#E6A6A6',
                glowColor: '#E67A7A',
                btnHeight: 30,
                hPadding: 12,
                marginLeft: 8,
                onTap: (): void => {
                  screenSaverAppModel.removePage(page.id);
                }
              })
            }
            .width('100%')
            .padding(14)
            .borderRadius(10)
            .backgroundColor('#1A1A1E')
            .scale({
              x: page.id === this.bouncePageId ? this.bounceScale : 1,
              y: page.id === this.bouncePageId ? this.bounceScale : 1
            })
          }, (page: ScreenSaverPageConfig): string => page.id)

          ScreenSaverGlowButton({
            label: '＋ 新建页面',
            textColor: '#8AB4F8',
            baseColor: '#1A1A1E',
            glowColor: '#2A2A33',
            fontSize: 14,
            btnHeight: 40,
            hPadding: 16,
            fullWidth: true,
            onTap: (): void => {
              this.addPage();
            }
          })

          Text('显示设置')
            .fontSize(15)
            .fontColor('#F2F2F2')
            .width('100%')
            .margin({ top: 4 })

          Row() {
            Column() {
              Text('环境色背景')
                .fontSize(14)
                .fontColor('#DDDDDD')
              Text('整页底色随当前照片主色调变化')
                .fontSize(11)
                .fontColor('#777777')
                .margin({ top: 2 })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: screenSaverAppModel.appConfig.settings.ambientColorEnabled })
              .selectedColor('#3D6FBF')
              .onChange((isOn: boolean): void => {
                screenSaverAppModel.appConfig.settings.ambientColorEnabled = isOn;
                screenSaverAppModel.save();
              })
          }
          .width('100%')
          .padding(14)
          .borderRadius(10)
          .backgroundColor('#1A1A1E')

          Row() {
            Column() {
              Text('夜间自动调暗')
                .fontSize(14)
                .fontColor('#DDDDDD')
              Text('屏保静置一段时间后自动降低亮度，触摸恢复；屏保期间默认保持亮屏')
                .fontSize(11)
                .fontColor('#777777')
                .margin({ top: 2 })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: screenSaverAppModel.appConfig.settings.dimEnabled })
              .selectedColor('#3D6FBF')
              .onChange((isOn: boolean): void => {
                screenSaverAppModel.appConfig.settings.dimEnabled = isOn;
                screenSaverAppModel.save();
              })
          }
          .width('100%')
          .padding(14)
          .borderRadius(10)
          .backgroundColor('#1A1A1E')

          if (screenSaverAppModel.appConfig.settings.dimEnabled) {
            Row() {
              Text('调暗延时')
                .fontSize(14)
                .fontColor('#DDDDDD')
              Blank()
              ForEach(SCREEN_SAVER_DIM_DELAY_OPTIONS, (option: ScreenSaverNumberOption) => {
                ScreenSaverGlowButton({
                  label: option.label,
                  textColor: screenSaverAppModel.appConfig.settings.dimDelaySec === option.value ?
                  '#FFFFFF' : '#BBBBBB',
                  baseColor: screenSaverAppModel.appConfig.settings.dimDelaySec === option.value ?
                  '#3D6FBF' : '#26262B',
                  glowColor: '#4A9EFF',
                  fontSize: 12,
                  btnHeight: 28,
                  hPadding: 10,
                  marginLeft: 6,
                  onTap: (): void => {
                    screenSaverAppModel.appConfig.settings.dimDelaySec = option.value;
                    screenSaverAppModel.save();
                  }
                })
              }, (option: ScreenSaverNumberOption): string => option.label)
            }
            .width('100%')
            .padding(14)
            .borderRadius(10)
            .backgroundColor('#1A1A1E')

            Row() {
              Text('调暗亮度')
                .fontSize(14)
                .fontColor('#DDDDDD')
              Blank()
              ForEach(SCREEN_SAVER_DIM_BRIGHTNESS_OPTIONS, (option: ScreenSaverNumberOption) => {
                ScreenSaverGlowButton({
                  label: option.label,
                  textColor: screenSaverAppModel.appConfig.settings.dimBrightness === option.value ?
                  '#FFFFFF' : '#BBBBBB',
                  baseColor: screenSaverAppModel.appConfig.settings.dimBrightness === option.value ?
                  '#3D6FBF' : '#26262B',
                  glowColor: '#4A9EFF',
                  fontSize: 12,
                  btnHeight: 28,
                  hPadding: 10,
                  marginLeft: 6,
                  onTap: (): void => {
                    screenSaverAppModel.appConfig.settings.dimBrightness = option.value;
                    screenSaverAppModel.save();
                  }
                })
              }, (option: ScreenSaverNumberOption): string => option.label)
            }
            .width('100%')
            .padding(14)
            .borderRadius(10)
            .backgroundColor('#1A1A1E')
          }

          Text('v1 支持时钟与相册卡片；屏保跟随系统方向自动旋转，视频卡片将在后续版本提供')
            .fontSize(11)
            .fontColor('#666666')
            .margin({ top: 4, bottom: 24 })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 8 })
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
    }
    .title('卡片屏保')
    .mode(NavigationMode.Stack)
    .navDestination(this.pageMap)
    .backgroundColor('#0E0E10')
  }
}
