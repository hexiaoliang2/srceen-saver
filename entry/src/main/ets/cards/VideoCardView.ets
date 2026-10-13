/**
 * =============================================================================
 * 视频卡片视图（VideoCardView.ets）
 * =============================================================================
 *
 * 【这个文件是干什么的】
 * 视频卡片：默认只显示「封面帧」（视频第 0 秒画面的小图，零解码成本），
 * 用户开了「播放视频」才真正启动 Video 组件解码播放。
 *
 * 【为什么默认不播放，而是显示封面帧】
 * 视频解码是本应用最耗电的操作（CPU+GPU 持续工作），屏保又往往整夜挂机。
 * 设计取舍：
 *   - 默认封面帧：静态图，几乎不耗电，视觉上依然是「视频卡片」；
 *   - 需要播放时手动打开（设置里也有全局默认值），并在面板里明确提示耗电。
 *
 * 【封面帧的显示原理】
 * VideoThumb 服务把视频首帧生成成 jpg 缓存文件，这里把缓存路径作为
 * Video 组件的 previewUri 传入——就算不播放，Video 组件也先显示这张预览图。
 *
 * 【异常兜底】
 * - 没选视频 → 「未选择视频」占位；
 * - 视频文件被删/权限失效 → 「视频不可用」占位 + 编辑态「重选」按钮；
 * - 播放结束且未开循环 → 自动把 playing 置回 false（回到封面帧态）。
 * =============================================================================
 */

import { common } from '@kit.AbilityKit';
import { ScreenSaverLogger } from '../common/Logger';
import { screenSaverVideoThumb } from '../common/VideoThumb';
import { ScreensaverCardInstance, ScreensaverCardMode } from '../model/ConfigModels';

@ComponentV2
export struct ScreensaverVideoCard {
  @Param card: ScreensaverCardInstance = new ScreensaverCardInstance();
  @Param cardMode: ScreensaverCardMode = 'play';
  /** 屏保在前台时为 true：后台时立即停止播放（省电流控）。 */
  @Param cardActive: boolean = true;
  /** 请求打开配置面板（「重选」按钮冒泡给父组件）。 */
  @Event onRequestConfig: () => void = (): void => {};

  // ---------- 渲染状态 ----------
  @Local coverPath: string = '';        // 封面帧缓存文件路径
  @Local unavailable: boolean = false;  // 视频不可用（被删/无权限）
  @Local emptyVisible: boolean = true;  // 是否显示「未选择视频」占位
  @Local prepared: boolean = false;     // Video 组件是否已就绪（onPrepared 回调）

  /** Video 组件的控制器：start/pause/stop 都通过它操作。 */
  private controller: VideoController = new VideoController();

  /** 组件挂载：检查视频源可用性并生成封面帧。 */
  aboutToAppear(): void {
    void this.prepareSource();
  }

  /** 组件销毁：停止播放（离开屏保页面时最关键的省电动作）。 */
  aboutToDisappear(): void {
    this.stopPlayback();
  }

  /** 换了视频：先停旧播放，重新生成封面帧。 */
  @Monitor('card.video.uri')
  onUriChanged(): void {
    this.stopPlayback();
    this.prepared = false;
    void this.prepareSource();
  }

  /** 播放开关变化：同步播放/暂停。 */
  @Monitor('card.video.playing')
  onPlayingChanged(): void {
    this.syncPlayback();
  }

  /** 退后台：立即停止播放。 */
  @Monitor('cardActive')
  onActiveChanged(): void {
    if (!this.cardActive) {
      this.stopPlayback();
    }
  }

  /**
   * 准备视频源：
   *   - 空 uri → 显示「未选择视频」；
   *   - 探测不可读 → 显示「视频不可用」；
   *   - 可读 → 生成（或命中缓存的）首帧封面图。
   * cover 用 640×360 而不是卡片实际尺寸：封面只是预览图，
   * 统一规格能显著提高缓存命中率（不同大小卡片共享同一份封面文件）。
   */
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

  /**
   * 播放同步：四个条件全满足才真正 start——
   * 开关打开 + 播放模式 + 屏保在前台 + 播放器已就绪。
   * 任何条件不满足一律 pause（宁可保守，不可偷跑解码）。
   */
  private syncPlayback(): void {
    if (this.card.video.playing && this.cardMode === 'play' && this.cardActive && this.prepared) {
      this.controller.start();
    } else {
      this.controller.pause();
    }
  }

  /** 停止播放并把开关复位（组件销毁/退后台/换视频时调用）。 */
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

  /** 弹 toast 提示（播放态点「重选」时提示先去编辑模式）。 */
  private toast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message, duration: 1500 });
    } catch (err) {
      const error = err as Error;
      ScreenSaverLogger.warn(`toast failed: ${error.message}`);
    }
  }

  /** 「重选」按钮：编辑态冒泡打开配置面板，播放态提示去编辑模式。 */
  private handleReselect(): void {
    if (this.cardMode === 'edit') {
      this.onRequestConfig();
    } else {
      this.toast('请在编辑模式中重新选择视频');
    }
  }

  /**
   * 界面结构（Stack 分层）：
   *   1. Video 组件（有视频且可用时）：关闭控制条/自动播放，默认显示封面预览；
   *   2. 「未选择视频」占位；
   *   3. 「视频不可用」占位（含编辑态「重选」按钮）。
   */
  build() {
    Stack() {
      if (this.card.video.uri.length > 0 && !this.unavailable) {
        Video({
          src: this.card.video.uri,
          // previewUri：播放前的预览图（封面帧缓存），不播放时看到的就是它
          previewUri: this.coverPath.length > 0 ? this.coverPath : undefined,
          controller: this.controller
        })
          .autoPlay(false)   // 永不自动播放，由 syncPlayback 统一控制
          .controls(false)   // 屏保上不要系统控制条
          .loop(this.card.video.loop)
          .muted(this.card.video.muted)
          .objectFit(ImageFit.Cover)
          .width('100%')
          .height('100%')
          .onPrepared((): void => {
            // 播放器就绪后才能 start；如果开关已经打开，这里立即开始播
            this.prepared = true;
            this.syncPlayback();
          })
          .onFinish((): void => {
            // 播完（未开循环）：开关复位，回到封面帧状态
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
          // 「重选」只在编辑态显示（播放态保持不可交互的纯净观感）
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
