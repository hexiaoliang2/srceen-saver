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
import { fileIo } from '@kit.CoreFileKit';
import { ScreenSaverLogger } from '../common/Logger';
import { SCREEN_SAVER_COLORS } from '../common/ScreenSaverStyle';
import { ScreenSaverChip, ScreenSaverToggleRow } from '../common/SheetParts';
import { screenSaverApplyFontScale } from '../common/FontScale';
import { screenSaverAppModel } from '../model/AppModel';
import { screenSaverMediaAccess } from '../common/MediaAccess';
import { screenSaverCanvasBackground } from '../common/CanvasBackground';
import {
  SCREEN_SAVER_CANVAS_COLORS,
  SCREEN_SAVER_DEFAULT_CANVAS_COLOR,
  SCREEN_SAVER_PHOTO_INTERVAL_OPTIONS,
  ScreensaverCanvasColorOption,
  ScreensaverStringOption
} from '../model/ConfigModels';

/** 背景色选择列表：默认纯黑 + 24 个预设色（变更项 7）。 */
function screenSaverCanvasColorOptions(): ScreensaverCanvasColorOption[] {
  const options: ScreensaverCanvasColorOption[] = [];
  const defaultOption: ScreensaverCanvasColorOption = {
    value: SCREEN_SAVER_DEFAULT_CANVAS_COLOR,
    label: '纯黑·默认'
  };
  options.push(defaultOption);
  for (const option of SCREEN_SAVER_CANVAS_COLORS) {
    options.push(option);
  }
  return options;
}

const CANVAS_COLOR_OPTIONS: ScreensaverCanvasColorOption[] = screenSaverCanvasColorOptions();

/**
 * 文字颜色三档（变更项 3.2）：黑色 / 白色 / 自动（默认）。
 * value 与 ScreensaverTextToneMode 一一对应：auto=自动、dark=黑色、light=白色。
 */
const TEXT_TONE_OPTIONS: ScreensaverStringOption[] = [
  { value: 'auto', label: '自动（默认）' },
  { value: 'dark', label: '黑色' },
  { value: 'light', label: '白色' }
];

/** 内置示例背景图的文件名（对应 resources/rawfile/sample_photos/ 下的自生成素材）。 */
const CANVAS_SAMPLE_FILE: string = 'photo_landscape_4k.jpg';
/** 内置示例背景图（暗色）：用于验证「较暗图片背景」下的自动文字色判定。 */
const CANVAS_SAMPLE_DARK_FILE: string = 'photo_dark.jpg';

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

  // ==================== 屏保整体背景（变更项 7） ====================

  /** 切换背景色：写入设置并落盘（背景层在屏保页最底层，不参与卡片定位）。 */
  private setCanvasColor(value: string): void {
    screenSaverAppModel.layout.settings.canvasColor = value;
    screenSaverAppModel.save();
  }

  // ==================== 文字与图标颜色（变更项 3.2/3.3） ====================

  /** 切换文字色档位（三档：自动/黑色/白色），立即落盘、重启后恢复。 */
  private setTextTone(value: string): void {
    const settings = screenSaverAppModel.layout.settings;
    if (value === 'dark') {
      settings.textTone = 'dark';
    } else if (value === 'light') {
      settings.textTone = 'light';
    } else {
      settings.textTone = 'auto';
    }
    screenSaverAppModel.save();
    this.toast(settings.textTone === 'auto' ? '已切换为自动（按整体背景明度）' : '已固定文字颜色档位');
  }

  /** 当前文字色档位的显示文案（右对齐的小字）。 */
  private textToneLabel(): string {
    const tone = screenSaverAppModel.layout.settings.textTone;
    if (tone === 'dark') {
      return '黑色';
    }
    if (tone === 'light') {
      return '白色';
    }
    return '自动';
  }

  /**
   * 选择本地图片作为背景（替代「桌面透视模糊」，原因见下方说明文案）。
   * 选完立即做一次**离屏模糊**并把结果缓存起来（screenSaverCanvasBackground），
   * 之后渲染只用缓存位图，不再重复计算。
   */
  private async pickCanvasImage(): Promise<void> {
    const picked = await screenSaverMediaAccess.pickImages(1);
    if (picked.length === 0) {
      return;
    }
    const settings = screenSaverAppModel.layout.settings;
    settings.canvasImageUri = picked[0];
    screenSaverAppModel.save();
    await screenSaverCanvasBackground.ensure(settings.canvasImageUri, settings.canvasBlur);
    this.toast(settings.canvasBlur ? '已设置背景图片（离屏模糊已计算并缓存）' : '已设置背景图片');
  }

  /** 清除自定义背景图片（回到纯色背景）。 */
  private clearCanvasImage(): void {
    const settings = screenSaverAppModel.layout.settings;
    if (settings.canvasImageUri.length === 0) {
      return;
    }
    settings.canvasImageUri = '';
    screenSaverAppModel.save();
    screenSaverCanvasBackground.clear();
    this.toast('已移除背景图片');
  }

  /**
   * 使用内置示例图作为背景（自测用，与视频/相册面板的「示例素材」同一套做法）：
   * 工程内自生成素材（rawfile），复制到应用沙箱后写入背景配置，
   * 并立刻做一次离屏模糊（若开关打开）以便验证缓存复用。
   */
  private async useSampleCanvasImage(): Promise<void> {
    await this.copySampleCanvasImage(CANVAS_SAMPLE_FILE);
  }

  /** 使用内置「暗色」示例图作为背景（验证较暗图片背景下的自动判定用）。 */
  private async useDarkSampleCanvasImage(): Promise<void> {
    await this.copySampleCanvasImage(CANVAS_SAMPLE_DARK_FILE);
  }

  /** 复制内置示例图到沙箱并设为背景（亮/暗两张共用同一条链路）。 */
  private async copySampleCanvasImage(fileName: string): Promise<void> {
    const context = this.context();
    if (context === undefined) {
      return;
    }
    try {
      const sampleDir = `${context.filesDir}/canvas_backgrounds`;
      try {
        fileIo.mkdirSync(sampleDir);
      } catch (mkdirError) {
        ScreenSaverLogger.info('canvas sample dir already ready');
      }
      const targetPath = `${sampleDir}/${fileName}`;
      let exists = false;
      try {
        exists = fileIo.accessSync(targetPath);
      } catch (accessError) {
        exists = false;
      }
      if (!exists) {
        const content = await context.resourceManager.getRawFileContent(`sample_photos/${fileName}`);
        const file = fileIo.openSync(targetPath, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE);
        try {
          fileIo.writeSync(file.fd, content.buffer as ArrayBuffer);
        } finally {
          fileIo.closeSync(file);
        }
      }
      const settings = screenSaverAppModel.layout.settings;
      settings.canvasImageUri = `file://${targetPath}`;
      screenSaverAppModel.save();
      await screenSaverCanvasBackground.ensure(settings.canvasImageUri, settings.canvasBlur);
      this.toast('已使用示例背景图（模糊按当前开关）');
    } catch (err) {
      const error = err as Error;
      ScreenSaverLogger.warn(`canvas sample image failed: ${error.message}`);
      this.toast('示例背景图不可用');
    }
  }

  /** 背景图片显示名（取 uri 最后一段，过长截断）。 */
  private canvasImageName(): string {
    const uri = screenSaverAppModel.layout.settings.canvasImageUri;
    if (uri.length === 0) {
      return '未选择';
    }
    const slash = uri.lastIndexOf('/');
    const name = slash >= 0 ? uri.substring(slash + 1) : uri;
    return name.length > 18 ? `${name.substring(0, 18)}…` : name;
  }

  /** 背景色选项（色块 + 名字，点击即切换）。 */
  @Builder
  canvasColorGrid() {
    Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
      ForEach(CANVAS_COLOR_OPTIONS, (option: ScreensaverCanvasColorOption) => {
        Column({ space: 3 }) {
          Column()
            .width(34)
            .height(34)
            .borderRadius(17)
            .backgroundColor(option.value)
            .border({
              width: screenSaverAppModel.layout.settings.canvasColor === option.value ? 2 : 1,
              color: screenSaverAppModel.layout.settings.canvasColor === option.value ?
              SCREEN_SAVER_COLORS.accent : '#33FFFFFF'
            })
          Text(option.label)
            .fontSize(9)
            .fontColor(SCREEN_SAVER_COLORS.textTertiary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width(60)
        .margin({ right: 2, bottom: 8 })
        .onClick((): void => {
          this.setCanvasColor(option.value);
        })
      }, (option: ScreensaverCanvasColorOption): string => `canvas_${option.value}`)
    }
    .width('100%')
    .margin({ top: 10 })
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

          // ---------- 显示卡片边框 ----------
          // 默认关闭 = 当前「透明边框」状态；开启后屏保页每张卡片显示细边框。
          Column() {
            ScreenSaverToggleRow({
              label: '显示卡片边框',
              tip: '关闭时卡片为透明边框（默认）；开启后屏保页每张卡片显示细边框',
              isOn: screenSaverAppModel.layout.settings.showCardBorder,
              onChange: (value: boolean): void => {
                screenSaverAppModel.layout.settings.showCardBorder = value;
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

          // ---------- 屏保整体背景（变更项 7） ----------
          Column({ space: 8 }) {
            Row() {
              Column() {
                Text('屏保背景')
                  .fontSize(14)
                  .fontColor('#CCCCCC')
                Text('默认纯黑 · 24 个预设色 · 可自选本地图片')
                  .fontSize(11)
                  .fontColor(SCREEN_SAVER_COLORS.textTertiary)
                  .margin({ top: 2 })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
              Text(screenSaverAppModel.layout.settings.canvasColor)
                .fontSize(11)
                .fontColor(SCREEN_SAVER_COLORS.textTertiary)
            }
            .width('100%')

            this.canvasColorGrid()

            // ---- 自定义背景图片（替代「桌面透视模糊」） ----
            Row() {
              Text('背景图片')
                .fontSize(14)
                .fontColor('#CCCCCC')
              Blank()
              Text(this.canvasImageName())
                .fontSize(12)
                .fontColor(SCREEN_SAVER_COLORS.textTertiary)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text('选择')
                .fontSize(13)
                .fontColor(SCREEN_SAVER_COLORS.accent)
                .margin({ left: 10 })
                .onClick((): void => {
                  void this.pickCanvasImage();
                })
              Text('示例图')
                .fontSize(13)
                .fontColor(SCREEN_SAVER_COLORS.accent)
                .margin({ left: 10 })
                .onClick((): void => {
                  void this.useSampleCanvasImage();
                })
              Text('暗示例')
                .fontSize(13)
                .fontColor(SCREEN_SAVER_COLORS.accent)
                .margin({ left: 10 })
                .onClick((): void => {
                  void this.useDarkSampleCanvasImage();
                })
              if (screenSaverAppModel.layout.settings.canvasImageUri.length > 0) {
                Text('移除')
                  .fontSize(13)
                  .fontColor(SCREEN_SAVER_COLORS.danger)
                  .margin({ left: 10 })
                  .onClick((): void => {
                    this.clearCanvasImage();
                  })
              }
            }
            .width('100%')

            ScreenSaverToggleRow({
              label: '背景模糊',
              tip: '仅对自选图片生效：离屏计算一次并缓存，不做实时模糊',
              isOn: screenSaverAppModel.layout.settings.canvasBlur,
              onChange: (value: boolean): void => {
                screenSaverAppModel.layout.settings.canvasBlur = value;
                screenSaverAppModel.save();
                const settings = screenSaverAppModel.layout.settings;
                if (settings.canvasImageUri.length > 0) {
                  void screenSaverCanvasBackground.ensure(settings.canvasImageUri, value);
                }
              }
            })

            Text('说明：系统壁纸接口（@ohos.wallpaper）自 API 9 起为系统 API，' +
              '三方应用无法读取桌面壁纸、也无法对桌面做模糊（需要系统级权限 GET_WALLPAPER），' +
              '因此这里提供「自选本地图片 + 一次性离屏模糊缓存」作为替代：不是实时桌面模糊，' +
              '换桌面壁纸后需要重新选图。⚠ 浅色背景会显著增加屏幕耗电（OLED 上等效点亮更多像素），' +
              '与「极低功耗」目标冲突，默认纯黑最省电。')
              .fontSize(11)
              .fontColor(SCREEN_SAVER_COLORS.textTertiary)
              .width('100%')
          }
          .width('100%')
          .padding(14)
          .borderRadius(10)
          .backgroundColor(SCREEN_SAVER_COLORS.bgElevated)

          // ---------- 文字与图标颜色（变更项 3.2/3.3/3.4） ----------
          // 三档：黑色 / 白色 / 自动（默认）。自动 = 按屏保整体背景明度判定，
          // 结果同时驱动卡片文字颜色与图标/装饰素材版本（同一来源）。
          Column({ space: 8 }) {
            Row() {
              Column() {
                Text('文字与图标颜色')
                  .fontSize(14)
                  .fontColor('#CCCCCC')
                Text('自动 = 按屏保整体背景明度判定（默认）')
                  .fontSize(11)
                  .fontColor(SCREEN_SAVER_COLORS.textTertiary)
                  .margin({ top: 2 })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
              Text(this.textToneLabel())
                .fontSize(13)
                .fontColor(SCREEN_SAVER_COLORS.accent)
            }
            .width('100%')

            Row({ space: 8 }) {
              ForEach(TEXT_TONE_OPTIONS, (option: ScreensaverStringOption) => {
                ScreenSaverChip({
                  label: option.label,
                  selected: screenSaverAppModel.layout.settings.textTone === option.value,
                  onTap: (): void => {
                    this.setTextTone(option.value);
                  }
                })
              }, (option: ScreensaverStringOption): string => `tone_${option.value}`)
            }
            .width('100%')

            ScreenSaverToggleRow({
              label: '文字投影兜底',
              tip: '背景为图片或对比度不足 4.5:1 时，为文字加一层轻投影保证可读',
              isOn: screenSaverAppModel.layout.settings.textHalo,
              onChange: (value: boolean): void => {
                screenSaverAppModel.layout.settings.textHalo = value;
                screenSaverAppModel.save();
              }
            })

            Text('判定说明：整体背景为纯色时用其色值算 WCAG 相对亮度；背景为图片/模糊图时' +
              '取整图主色（≈主要区域平均色）算亮度，取样在背景图就绪时执行一次并缓存。' +
              '自动档阈值取黑白文字的对比度交叉点（相对亮度 0.179），保证纯色背景下 ' +
              '所选文字色对比度 ≥ 4.5:1（WCAG AA 正文下限）；图片背景局部像素不可预知，' +
              '因此启用轻投影兜底。装饰素材（天气图标等）随档位切换深浅两套。')
              .fontSize(11)
              .fontColor(SCREEN_SAVER_COLORS.textTertiary)
              .width('100%')
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
