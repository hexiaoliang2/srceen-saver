import { common } from '@kit.AbilityKit';
import { ScreenSaverLogger } from '../common/Logger';
import { SCREEN_SAVER_COLORS } from '../common/ScreenSaverStyle';
import { ScreenSaverChip, ScreenSaverToggleRow } from '../common/SheetParts';
import { screenSaverApplyFontScale } from '../common/FontScale';
import { screenSaverAppModel } from '../model/AppModel';
import { screenSaverMediaAccess } from '../common/MediaAccess';
import { SCREEN_SAVER_PHOTO_INTERVAL_OPTIONS } from '../model/ConfigModels';

@ComponentV2
export struct ScreenSaverSettingsPage {
  @Param navStack: NavPathStack = new NavPathStack();

  private context(): common.UIAbilityContext | undefined {
    return this.getUIContext().getHostContext() as common.UIAbilityContext | undefined;
  }

  private toast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message, duration: 1500 });
    } catch (err) {
      const error = err as Error;
      ScreenSaverLogger.warn(`toast failed: ${error.message}`);
    }
  }

  private async openPermissionSetting(): Promise<void> {
    const context = this.context();
    if (context === undefined) {
      return;
    }
    await screenSaverMediaAccess.openPermissionSetting(context);
  }

  build() {
    NavDestination() {
      Scroll() {
        Column({ space: 10 }) {
          Row() {
            Text('返回')
              .fontSize(14)
              .fontColor('#CCCCCC')
              .padding({ left: 16, right: 12, top: 12, bottom: 12 })
              .onClick((): void => {
                this.navStack.pop();
              })
            Blank()
            Text('设置')
              .fontSize(16)
              .fontColor(SCREEN_SAVER_COLORS.textPrimary)
            Blank()
            Text('')
              .width(40)
          }
          .width('100%')

          Row() {
            Text('默认切换间隔')
              .fontSize(14)
              .fontColor('#CCCCCC')
            Blank()
            Row({ space: 8 }) {
              ForEach(SCREEN_SAVER_PHOTO_INTERVAL_OPTIONS, (seconds: number) => {
                ScreenSaverChip({
                  label: `${seconds} 秒`,
                  selected: screenSaverAppModel.layout.settings.defaultIntervalSec === seconds,
                  onTap: (): void => {
                    screenSaverAppModel.layout.settings.defaultIntervalSec = seconds;
                    screenSaverAppModel.save();
                  }
                })
              }, (seconds: number): string => `default_${seconds}`)
            }
          }
          .width('100%')
          .padding(14)
          .borderRadius(10)
          .backgroundColor(SCREEN_SAVER_COLORS.bgElevated)

          Column() {
            ScreenSaverToggleRow({
              label: '字号跟随系统',
              tip: '关闭后应用内字号固定为标准大小',
              isOn: screenSaverAppModel.layout.settings.fontFollowSystem,
              onChange: (value: boolean): void => {
                screenSaverAppModel.layout.settings.fontFollowSystem = value;
                screenSaverAppModel.save();
                const context = this.context();
                if (context !== undefined) {
                  screenSaverApplyFontScale(context, value);
                }
              }
            })
          }
          .width('100%')
          .padding(14)
          .borderRadius(10)
          .backgroundColor(SCREEN_SAVER_COLORS.bgElevated)

          Column() {
            ScreenSaverToggleRow({
              label: '单卡片垂直居中',
              tip: '仅当布局只有一张卡片时生效，默认关闭（靠顶）',
              isOn: screenSaverAppModel.layout.settings.singleCardCentered,
              onChange: (value: boolean): void => {
                screenSaverAppModel.layout.settings.singleCardCentered = value;
                screenSaverAppModel.save();
              }
            })
          }
          .width('100%')
          .padding(14)
          .borderRadius(10)
          .backgroundColor(SCREEN_SAVER_COLORS.bgElevated)

          Row() {
            Column() {
              Text('相册来源')
                .fontSize(14)
                .fontColor('#CCCCCC')
              Text('在相册卡片的半模态中按相册选择')
                .fontSize(11)
                .fontColor(SCREEN_SAVER_COLORS.textTertiary)
                .margin({ top: 2 })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            Text('全部')
              .fontSize(13)
              .fontColor(SCREEN_SAVER_COLORS.accent)
          }
          .width('100%')
          .padding(14)
          .borderRadius(10)
          .backgroundColor(SCREEN_SAVER_COLORS.bgElevated)

          Column() {
            ScreenSaverToggleRow({
              label: '视频默认播放',
              tip: '默认仅显示封面帧，开启后新添加的视频卡片默认播放',
              isOn: screenSaverAppModel.layout.settings.videoDefaultAutoplay,
              onChange: (value: boolean): void => {
                screenSaverAppModel.layout.settings.videoDefaultAutoplay = value;
                screenSaverAppModel.save();
              }
            })
          }
          .width('100%')
          .padding(14)
          .borderRadius(10)
          .backgroundColor(SCREEN_SAVER_COLORS.bgElevated)

          Column() {
            ScreenSaverToggleRow({
              label: '保持亮屏',
              tip: '屏保期间屏幕保持常亮',
              isOn: screenSaverAppModel.layout.settings.keepScreenOn,
              onChange: (value: boolean): void => {
                screenSaverAppModel.layout.settings.keepScreenOn = value;
                screenSaverAppModel.save();
              }
            })
          }
          .width('100%')
          .padding(14)
          .borderRadius(10)
          .backgroundColor(SCREEN_SAVER_COLORS.bgElevated)

          Column() {
            ScreenSaverToggleRow({
              label: '关闭动效',
              tip: '转场与切换改为直切，静态优先最省电',
              isOn: screenSaverAppModel.layout.settings.motionDisabled,
              onChange: (value: boolean): void => {
                screenSaverAppModel.layout.settings.motionDisabled = value;
                screenSaverAppModel.save();
              }
            })
          }
          .width('100%')
          .padding(14)
          .borderRadius(10)
          .backgroundColor(SCREEN_SAVER_COLORS.bgElevated)

          Row() {
            Text('权限管理')
              .fontSize(14)
              .fontColor('#CCCCCC')
              .layoutWeight(1)
            Text('相册读取')
              .fontSize(12)
              .fontColor(SCREEN_SAVER_COLORS.textTertiary)
            Text('去设置')
              .fontSize(13)
              .fontColor(SCREEN_SAVER_COLORS.accent)
              .margin({ left: 10 })
              .onClick((): void => {
                void this.openPermissionSetting();
              })
          }
          .width('100%')
          .padding(14)
          .borderRadius(10)
          .backgroundColor(SCREEN_SAVER_COLORS.bgElevated)

          Row() {
            Text('关于')
              .fontSize(14)
              .fontColor('#CCCCCC')
              .layoutWeight(1)
            Text('v0.1')
              .fontSize(13)
              .fontColor(SCREEN_SAVER_COLORS.textSecondary)
          }
          .width('100%')
          .padding(14)
          .borderRadius(10)
          .backgroundColor(SCREEN_SAVER_COLORS.bgElevated)

          Text('应用内全屏展示 · 卡片自由布局 · 深色省电 · 静态优先')
            .fontSize(11)
            .fontColor(SCREEN_SAVER_COLORS.textTertiary)
            .margin({ top: 4, bottom: 24 })
        }
        .width('100%')
        .padding({ left: 16, right: 16 })
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
      .backgroundColor(SCREEN_SAVER_COLORS.bg)
    }
    .hideTitleBar(true)
    .backgroundColor(SCREEN_SAVER_COLORS.bg)
  }
}
