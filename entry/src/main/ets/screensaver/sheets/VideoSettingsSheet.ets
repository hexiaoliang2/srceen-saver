/**
 * =============================================================================
 * 视频卡片设置面板（VideoSettingsSheet.ets）
 * =============================================================================
 *
 * 【这个文件是干什么的】
 * 视频卡片的设置抽屉：实时预览、选择视频（系统 picker，单选）、
 * 播放开关、循环播放、静音播放、删除卡片。
 *
 * 【省电优先的设计取向】
 * - 「播放视频」默认关闭：卡片平时只显示封面帧（静态图，几乎不耗电）；
 *   打开后卡片才会真正起播视频。未选视频时打开开关会被拦截并提示。
 * - 「循环播放」默认关：循环意味着持续解码渲染，耗电大头，
 *   界面上明确用 ⚠ 提示持续解码的耗电风险。
 * - 封面帧固定「自动首帧」：由 VideoCardView 自动截取首帧生成，
 *   这里只展示说明，不提供开关。
 *
 * 【换视频时重置播放状态】
 * pickVideo() 选了新视频后强制 playing = false——
 * 新视频先以封面帧示人，避免换完立刻大声播起来。
 * =============================================================================
 */

import {
  ScreenSaverChip,
  ScreenSaverDeleteCardRow,
  ScreenSaverSheetHeader,
  ScreenSaverSizePresetRow,
  ScreenSaverToggleRow
} from '../../common/SheetParts';
import { SCREEN_SAVER_COLORS } from '../../common/ScreenSaverStyle';
import { ScreenSaverLogger } from '../../common/Logger';
import { screenSaverAppModel } from '../../model/AppModel';
import { screenSaverSizePresets } from '../../cards/CardCatalog';
import { ScreensaverVideoCard } from '../../cards/VideoCardView';
import { ScreensaverCardInstance, ScreensaverSizePreset } from '../../model/ConfigModels';
import { screenSaverMediaAccess } from '../../common/MediaAccess';
import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';

/** 内置示例视频的文件名（对应 resources/rawfile/sample_videos/ 下的资源）。 */
const SAMPLE_VIDEO_NAMES: string[] = [
  'sample_landscape_1080p_10s.mp4',
  'sample_portrait_1080p_8s.mp4'
];
/** 示例视频释放到沙箱时的目录名。 */
const SAMPLE_VIDEO_DIR: string = 'sample_videos';

@ComponentV2
export struct ScreenSaverVideoSettingsPanel {
  @Param card: ScreensaverCardInstance = new ScreensaverCardInstance();
  @Event onDone: () => void = (): void => {};
  @Event onDelete: () => void = (): void => {};

  /** 异步选视频进行中标志（防重复点击）。 */
  @Local busy: boolean = false;
  /** 底部状态文案（如「已使用示例视频 …」）。 */
  @Local statusText: string = '';

  /**
   * 系统 picker 选一个视频（单选）。
   * 选完强制 playing = false：新视频先显示封面帧，
   * 不换完就自动播，防止突然出声/耗电。
   */
  private async pickVideo(): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    try {
      const uri = await screenSaverMediaAccess.pickVideo();
      if (uri.length > 0) {
        this.card.video.uri = uri;
        this.card.video.playing = false;
        screenSaverAppModel.save();
      }
    } finally {
      this.busy = false;
    }
  }

  /**
   * 使用内置示例视频（缺陷 4 的测试数据）：
   * rawfile 不能直接当视频源用，先复制到应用沙箱 filesDir/sample_videos/，
   * 再把沙箱路径写进卡片。两段素材由 ffmpeg 合成生成（testsrc2 / smptebars），
   * 无第三方版权，随工程一起入库，仅用于功能自测。
   */
  private async useSampleVideo(name: string): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext | undefined;
      if (context === undefined) {
        return;
      }
      const sampleDir = `${context.filesDir}/${SAMPLE_VIDEO_DIR}`;
      try {
        fileIo.mkdirSync(sampleDir);
      } catch (mkdirError) {
        ScreenSaverLogger.info('sample video dir already ready');
      }
      const targetPath = `${sampleDir}/${name}`;
      let exists = false;
      try {
        exists = fileIo.accessSync(targetPath);
      } catch (accessError) {
        exists = false;
      }
      if (!exists) {
        const content = await context.resourceManager.getRawFileContent(`${SAMPLE_VIDEO_DIR}/${name}`);
        const file = fileIo.openSync(targetPath, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE);
        try {
          fileIo.writeSync(file.fd, content.buffer as ArrayBuffer);
        } finally {
          fileIo.closeSync(file);
        }
      }
      // 注意：Video 组件的 src 需要「URI」而不是纯文件路径，
      // 沙箱路径必须加 file:// 前缀才能被播放器解析（图片 Image 则两者都认）。
      this.card.video.uri = `file://${targetPath}`;
      // 新视频先显示封面帧，避免换完立刻播（与原 pickVideo 行为一致）
      this.card.video.playing = false;
      screenSaverAppModel.save();
      this.statusText = `已使用示例视频 ${name}`;
    } finally {
      this.busy = false;
    }
  }

  /**
   * 视频文件显示名：取 uri 最后一段，超过 22 字符截断加省略号。
   */
  private videoName(): string {
    const uri = this.card.video.uri;
    if (uri.length === 0) {
      return '未选择';
    }
    const slash = uri.lastIndexOf('/');
    const name = slash >= 0 ? uri.substring(slash + 1) : uri;
    return name.length > 22 ? `${name.substring(0, 22)}…` : name;
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

  /** 面板标题：带实例标识（如「视频 2 · 设置」），便于核对面板归属哪张卡片。 */
  private panelTitle(): string {
    return `${screenSaverAppModel.cardInstanceTitle(this.card)} · 设置`;
  }

  /**
   * 应用尺寸矩阵里的快捷尺寸（走 AppModel.resizeCardTo：吸附 + 碰撞校验）。
   * 视频卡上限 4×4 是功耗约束（解码面积越大越耗电）。
   */
  private applySizePreset(preset: ScreensaverSizePreset): void {
    const resized = screenSaverAppModel.resizeCardTo(this.card.id, preset.colSpan, preset.rowSpan);
    if (!resized) {
      this.toast('该尺寸不可用（与其它卡片重叠或越界）');
    }
  }

  build() {
    Column() {
      // ---------- 顶栏（标题 + 完成） ----------
      ScreenSaverSheetHeader({
        title: this.panelTitle(),
        onDone: (): void => {
          this.onDone();
        }
      })
      .padding({ left: 16, right: 16 })

      Scroll() {
        Column({ space: 12 }) {
          // ---------- 实时预览 ----------
          // 直接渲染真卡片组件（edit 模式纯展示，不响应手势）。
          // previewActive=true（变更项 3）：面板里打开「播放视频」后，这一小块预览
          // 会真正播放——这是移除卡片中央按钮之后**编辑态的播放入口/验证入口**。
          Column() {
            ScreensaverVideoCard({
              card: this.card,
              cardMode: 'edit',
              cardActive: false,
              previewActive: true
            })
          }
          .width('100%')
          .height(140)
          .borderRadius(8)
          .backgroundColor(SCREEN_SAVER_COLORS.cardBg)
          .clip(true)

          // ---------- 选择视频 ----------
          // 点右侧文件名（或「未选择」）拉起系统 picker（真实使用路径）。
          Row() {
            Text('选择视频')
              .fontSize(14)
              .fontColor('#CCCCCC')
            Blank()
            Text(this.busy ? '请稍候…' : this.videoName())
              .fontSize(13)
              .fontColor(SCREEN_SAVER_COLORS.accent)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .onClick((): void => {
                void this.pickVideo();
              })
          }
          .width('100%')

          // ---------- 内置示例视频（自测用，随工程入库） ----------
          Row({ space: 8 }) {
            Text('示例视频')
              .fontSize(14)
              .fontColor('#CCCCCC')
            Blank()
            ScreenSaverChip({
              label: '横屏',
              onTap: (): void => {
                void this.useSampleVideo(SAMPLE_VIDEO_NAMES[0]);
              }
            })
            ScreenSaverChip({
              label: '竖屏',
              onTap: (): void => {
                void this.useSampleVideo(SAMPLE_VIDEO_NAMES[1]);
              }
            })
          }
          .width('100%')
          if (this.statusText.length > 0) {
            Text(this.statusText)
              .fontSize(11)
              .fontColor(SCREEN_SAVER_COLORS.textTertiary)
              .width('100%')
          }

          // ---------- 播放开关 ----------
          // 未选视频时拦截；⚠ 明示持续解码耗电。
          // 变更项 3 之后：卡片上不再有播放按钮，这里是**编辑态的播放入口**，
          // 打开后上方预览区会真实播放（屏保展示态则是单击卡片切换）。
          ScreenSaverToggleRow({
            label: '播放视频',
            tip: '⚠ 持续解码耗电较高，建议充电时使用；打开后上方预览会播放，屏保里单击卡片可切换',
            isOn: this.card.video.playing,
            onChange: (value: boolean): void => {
              if (value && this.card.video.uri.length === 0) {
                this.toast('请先选择视频');
                return;
              }
              this.card.video.playing = value;
              screenSaverAppModel.save();
            }
          })

          // ---------- 封面帧说明 ----------
          // 封面由 VideoCardView 自动截取首帧生成，无开关。
          Row() {
            Text('封面帧')
              .fontSize(14)
              .fontColor('#CCCCCC')
            Blank()
            Text('自动首帧')
              .fontSize(12)
              .fontColor(SCREEN_SAVER_COLORS.textTertiary)
          }
          .width('100%')

          // ---------- 尺寸 ----------
          // 预设来自尺寸矩阵；画面用 Contain 等比完整显示（比例不一致时露黑边）。
          ScreenSaverSizePresetRow({
            presets: screenSaverSizePresets('video'),
            currentCols: this.card.colSpan,
            currentRows: this.card.rowSpan,
            onPick: (preset: ScreensaverSizePreset): void => {
              this.applySizePreset(preset);
            }
          })

          // ---------- 循环播放 ----------
          ScreenSaverToggleRow({
            label: '循环播放',
            tip: '默认关；开启后持续解码渲染',
            isOn: this.card.video.loop,
            onChange: (value: boolean): void => {
              this.card.video.loop = value;
              screenSaverAppModel.save();
            }
          })

          // ---------- 静音播放 ----------
          ScreenSaverToggleRow({
            label: '静音播放',
            tip: '屏保默认静音，避免打扰',
            isOn: this.card.video.muted,
            onChange: (value: boolean): void => {
              this.card.video.muted = value;
              screenSaverAppModel.save();
            }
          })

          ScreenSaverDeleteCardRow({
            onDelete: (): void => {
              this.onDelete();
            }
          })
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 28 })
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .margin({ top: 4 })
    }
    .width('100%')
    .height('100%')
  }
}
