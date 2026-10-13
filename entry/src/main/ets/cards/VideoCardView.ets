import { common } from '@kit.AbilityKit';
import { ScreenSaverLogger } from '../common/Logger';
import { screenSaverVideoThumb } from '../common/VideoThumb';
import { ScreensaverCardInstance, ScreensaverCardMode } from '../model/ConfigModels';

@ComponentV2
export struct ScreensaverVideoCard {
  @Param card: ScreensaverCardInstance = new ScreensaverCardInstance();
  @Param cardMode: ScreensaverCardMode = 'play';
  @Param cardActive: boolean = true;
  @Event onRequestConfig: () => void = (): void => {};

  @Local coverPath: string = '';
  @Local unavailable: boolean = false;
  @Local emptyVisible: boolean = true;
  @Local prepared: boolean = false;

  private controller: VideoController = new VideoController();

  aboutToAppear(): void {
    void this.prepareSource();
  }

  aboutToDisappear(): void {
    this.stopPlayback();
  }

  @Monitor('card.video.uri')
  onUriChanged(): void {
    this.stopPlayback();
    this.prepared = false;
    void this.prepareSource();
  }

  @Monitor('card.video.playing')
  onPlayingChanged(): void {
    this.syncPlayback();
  }

  @Monitor('cardActive')
  onActiveChanged(): void {
    if (!this.cardActive) {
      this.stopPlayback();
    }
  }

  private async prepareSource(): Promise<void> {
    const uri = this.card.video.uri;
    if (uri.length === 0) {
      this.emptyVisible = true;
      this.unavailable = false;
      this.coverPath = '';
      return;
    }
    const readable = screenSaverVideoThumb.probeReadable(uri);
    this.unavailable = !readable;
    this.emptyVisible = false;
    if (!readable) {
      this.coverPath = '';
      return;
    }
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext | undefined;
    if (context === undefined) {
      return;
    }
    const cover = await screenSaverVideoThumb.firstFrameFile(context, uri, 640, 360);
    this.coverPath = cover;
  }

  private syncPlayback(): void {
    if (this.card.video.playing && this.cardMode === 'play' && this.cardActive && this.prepared) {
      this.controller.start();
    } else {
      this.controller.pause();
    }
  }

  private stopPlayback(): void {
    try {
      this.controller.stop();
    } catch (err) {
      ScreenSaverLogger.warn('video stop failed');
    }
    if (this.card.video.playing) {
      this.card.video.playing = false;
    }
  }

  private toast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message, duration: 1500 });
    } catch (err) {
      const error = err as Error;
      ScreenSaverLogger.warn(`toast failed: ${error.message}`);
    }
  }

  private handleReselect(): void {
    if (this.cardMode === 'edit') {
      this.onRequestConfig();
    } else {
      this.toast('请在编辑模式中重新选择视频');
    }
  }

  build() {
    Stack() {
      if (this.card.video.uri.length > 0 && !this.unavailable) {
        Video({
          src: this.card.video.uri,
          previewUri: this.coverPath.length > 0 ? this.coverPath : undefined,
          controller: this.controller
        })
          .autoPlay(false)
          .controls(false)
          .loop(this.card.video.loop)
          .muted(this.card.video.muted)
          .objectFit(ImageFit.Cover)
          .width('100%')
          .height('100%')
          .onPrepared((): void => {
            this.prepared = true;
            this.syncPlayback();
          })
          .onFinish((): void => {
            if (!this.card.video.loop) {
              this.card.video.playing = false;
            }
          })
          .onError((): void => {
            ScreenSaverLogger.warn('video component error');
            this.prepared = false;
          })
      }
      if (this.emptyVisible) {
        Column({ space: 4 }) {
          Text('未选择视频')
            .fontSize(13)
            .fontColor('#B3B3B3')
          Text('在配置中选择本地视频')
            .fontSize(11)
            .fontColor('#6E6E73')
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor('#0A0A0C')
      }
      if (this.unavailable) {
        Column({ space: 6 }) {
          Text('视频不可用')
            .fontSize(13)
            .fontColor('#B3B3B3')
          Text('文件已被删除 · 请在配置中重新选择')
            .fontSize(11)
            .fontColor('#6E6E73')
          if (this.cardMode === 'edit') {
            Column() {
              Text('重选')
                .fontSize(12)
                .fontColor('#4A9EFF')
            }
            .constraintSize({ minWidth: 40, minHeight: 40 })
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
            .borderRadius(6)
            .backgroundColor('#26262B')
            .onClick((): void => {
              this.handleReselect();
            })
          }
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor('#0A0A0C')
      }
    }
    .width('100%')
    .height('100%')
    .clip(true)
    .backgroundColor('#0A0A0C')
  }
}
