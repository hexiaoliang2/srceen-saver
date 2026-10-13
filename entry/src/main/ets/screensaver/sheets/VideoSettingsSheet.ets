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

  @Local busy: boolean = false;

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

  private videoName(): string {
    const uri = this.card.video.uri;
    if (uri.length === 0) {
      return '未选择';
    }
    const slash = uri.lastIndexOf('/');
    const name = slash >= 0 ? uri.substring(slash + 1) : uri;
    return name.length > 22 ? `${name.substring(0, 22)}…` : name;
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
    Column() {
      ScreenSaverSheetHeader({
        title: '视频卡片',
        onDone: (): void => {
          this.onDone();
        }
      })
      .padding({ left: 16, right: 16 })

      Scroll() {
        Column({ space: 12 }) {
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

          ScreenSaverToggleRow({
            label: '循环播放',
            tip: '默认关；开启后持续解码渲染',
            isOn: this.card.video.loop,
            onChange: (value: boolean): void => {
              this.card.video.loop = value;
              screenSaverAppModel.save();
            }
          })

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
