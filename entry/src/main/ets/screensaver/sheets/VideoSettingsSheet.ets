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
  ScreenSaverToggleRow
} from '../../common/SheetParts';
import { SCREEN_SAVER_COLORS } from '../../common/ScreenSaverStyle';
import { ScreenSaverLogger } from '../../common/Logger';
import { screenSaverAppModel } from '../../model/AppModel';
import { ScreensaverVideoCard } from '../../cards/VideoCardView';
import { ScreensaverCardInstance } from '../../model/ConfigModels';
import { screenSaverMediaAccess } from '../../common/MediaAccess';

@ComponentV2
export struct ScreenSaverVideoSettingsPanel {
  @Param card: ScreensaverCardInstance = new ScreensaverCardInstance();
  @Event onDone: () => void = (): void => {};
  @Event onDelete: () => void = (): void => {};

  /** 异步选视频进行中标志（防重复点击）。 */
  @Local busy: boolean = false;

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

  build() {
    Column() {
      // ---------- 顶栏（标题 + 完成） ----------
      ScreenSaverSheetHeader({
        title: '视频卡片',
        onDone: (): void => {
          this.onDone();
        }
      })
      .padding({ left: 16, right: 16 })

      Scroll() {
        Column({ space: 12 }) {
          // ---------- 实时预览 ----------
          // 直接渲染真卡片组件（edit 模式纯展示，不响应手势）。
          Column() {
            ScreensaverVideoCard({
              card: this.card,
              cardMode: 'edit',
              cardActive: false
            })
          }
          .width('100%')
          .height(140)
          .borderRadius(8)
          .backgroundColor(SCREEN_SAVER_COLORS.cardBg)
          .clip(true)

          // ---------- 选择视频 ----------
          // 点右侧文件名（或「未选择」）拉起系统 picker。
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

          // ---------- 播放开关 ----------
          // 未选视频时拦截；⚠ 明示持续解码耗电。
          ScreenSaverToggleRow({
            label: '播放视频',
            tip: '⚠ 持续解码耗电较高，建议充电时使用',
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
