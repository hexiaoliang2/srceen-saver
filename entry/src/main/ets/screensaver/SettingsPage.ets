/**
 * =============================================================================
 * 设置页面（SettingsPage.ets）
 * =============================================================================
 *
 * 【这个文件是干什么的】
 * 全局设置页（不属于任何一张卡片的设置）：默认切换间隔、字号跟随系统、
 * 单卡片居中、视频默认播放、保持亮屏、减弱动效、低电量自动退出、
 * 权限管理和关于信息。
 *
 * 【统一的交互模式】
 * 每个设置项都是「改动 → 存 AppModel → save() 持久化」三步。
 * 界面直接读写 layout.settings（@ObservedV2），改动即时生效并自动落盘。
 *
 * 【两个即时生效的特殊项】
 * - 字号跟随系统：改动后要立刻调 screenSaverApplyFontScale，
 *   不用等下次启动才生效；
 * - 权限管理：跳系统授权界面，回来后 MediaAccess 的标记会自动更新。
 * =============================================================================
 */

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

  /** 获取应用上下文（字号缩放、权限设置需要传给系统 API）。 */
  private context(): common.UIAbilityContext | undefined {
    return this.getUIContext().getHostContext() as common.UIAbilityContext | undefined;
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

  /** 打开系统授权设置界面（相册读取权限）。 */
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
          // ---------- 自绘顶栏（返回 + 标题，右侧占位保持标题居中） ----------
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

          // ---------- 默认切换间隔 ----------
          // 新建的相册卡片会继承这个值（卡片可单独覆盖）。
          // 当前值直接显示在右侧；下方胶囊组点击即改。
          Column() {
            Row() {
              Column() {
                Text('默认切换间隔')
                  .fontSize(14)
                  .fontColor('#CCCCCC')
                Text('卡片可单独覆盖')
                  .fontSize(11)
                  .fontColor(SCREEN_SAVER_COLORS.textTertiary)
                  .margin({ top: 2 })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
              Text(`${screenSaverAppModel.layout.settings.defaultIntervalSec} 秒`)
                .fontSize(13)
                .fontColor(SCREEN_SAVER_COLORS.accent)
            }
            .width('100%')
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
            .margin({ top: 10 })
          }
          .width('100%')
          .padding(14)
          .borderRadius(10)
          .backgroundColor(SCREEN_SAVER_COLORS.bgElevated)

          // ---------- 字号跟随系统 ----------
          // 开关改动后除了持久化，还立即调用 screenSaverApplyFontScale
          // 让本次会话马上生效（不用重启应用）。
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

          // ---------- 单卡片垂直居中 ----------
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

          // ---------- 视频默认播放 ----------
          // 只影响「新添加」的视频卡片（已有卡片的开关不联动）。
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

          // ---------- 保持亮屏 ----------
          // 屏保的核心能力之一：挂机时屏幕不熄灭。
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

          // ---------- 减弱动效 ----------
          // 打开后所有动画时长压缩或归零（见 Motion.ets 的三档策略）。
          Column() {
            ScreenSaverToggleRow({
              label: '减弱动效',
              tip: '跟随系统设置',
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

          // ---------- 低电量自动退出 ----------
          // 低于 20% 且不在充电时，屏保页自动退出（详见 ScreensaverPage 轮询）。
          Column() {
            ScreenSaverToggleRow({
              label: '低电量自动退出',
              tip: '低于 20% 时自动退出屏保',
              isOn: screenSaverAppModel.layout.settings.lowBatteryAutoExit,
              onChange: (value: boolean): void => {
                screenSaverAppModel.layout.settings.lowBatteryAutoExit = value;
                screenSaverAppModel.save();
              }
            })
          }
          .width('100%')
          .padding(14)
          .borderRadius(10)
          .backgroundColor(SCREEN_SAVER_COLORS.bgElevated)

          // ---------- 权限管理 ----------
          // 相册读取权限：跳系统授权界面（用户可能之前拒绝过弹窗，
          // 系统不再弹，只能来这里手动开）。
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

          // ---------- 关于 ----------
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

          // ---------- 页脚 ----------
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
