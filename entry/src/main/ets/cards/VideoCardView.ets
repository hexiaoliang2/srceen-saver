/**
 * =============================================================================
 * 视频卡片视图（VideoCardView.ets）
 * =============================================================================
 *
 * 本地视频卡：画面 + 播放/暂停、进度、声音三控件。
 *   · 控件默认隐藏（2s 无操作自动隐藏），点击画面唤起；控件为半透明浮层，
 *     不改变视频画面尺寸；
 *   · 1 列窄条（1×1/1×2/1×3/1×4）只显示居中的播放/暂停；
 *   · 2×1/3×1/4×1 与 2×2 及以上显示三控件；
 *   · 播放/暂停状态来自 Video 回调（onStart/onPause/onFinish/onError）；
 *   · 进度来自 onPrepared/onUpdate（约 1 次/秒），拖动时用本地预览值；
 *   · 声音状态由 VideoSoundSession 运行时管理，不持久化；每次重置回到静音。
 *
 * 控件常显规则已被用户明确覆盖为“点击画面唤起、2s 自动消失”，
 * 但控件层仍为 overlay，不改变画面尺寸、不引起布局抖动。
 * =============================================================================
 */

import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { ScreenSaverLogger } from '../common/Logger';
import { screenSaverVideoThumb } from '../common/VideoThumb';
import {
  screenSaverVideoAudioProbe,
  ScreenSaverVideoAudioTrackState
} from '../common/VideoAudioProbe';
import { screenSaverSystemAudioState } from '../common/SystemAudioState';
import { screenSaverVideoSoundSession } from '../common/VideoSoundSession';
import { SCREEN_SAVER_METRICS } from '../common/ScreenSaverStyle';
import { screenSaverContainSize, screenSaverFittedSize, ScreenSaverFitSize } from '../common/ContentFit';
import {
  screenSaverCardPalette,
  screenSaverTextShadow,
  ScreensaverCardPalette
} from '../common/CardTheme';
import { SCREEN_SAVER_FONT } from '../common/CardTypography';
import { screenSaverResolveDensity } from './CardCatalog';
import { screenSaverAppModel } from '../model/AppModel';
import { ScreensaverCardDensity, ScreensaverCardInstance, ScreensaverCardMode,
  ScreensaverInkTone } from '../model/ConfigModels';

type ScreenSaverVideoPlaybackPhase = 'idle' | 'playing' | 'paused' | 'finished' | 'error';

@ComponentV2
export struct ScreensaverVideoCard {
  @Param card: ScreensaverCardInstance = new ScreensaverCardInstance();
  @Param cardMode: ScreensaverCardMode = 'play';
  /** 屏保在前台时为 true：后台时立即停止播放（省电流控）。 */
  @Param cardActive: boolean = true;
  /** 文字/图标墨色档与投影兜底开关（由屏保页统一解析后下发）。 */
  @Param cardTone: ScreensaverInkTone = 'light';
  @Param cardHalo: boolean = false;
  /** 设置面板预览：允许在 cardMode==='edit' 下播放，但控件不显示。 */
  @Param previewActive: boolean = false;
  /** 请求打开配置面板（「重选」按钮冒泡给父组件）。 */
  @Event onRequestConfig: () => void = (): void => {};

  private density(): ScreensaverCardDensity {
    return screenSaverResolveDensity(this.card.cardType, this.card.colSpan, this.card.rowSpan);
  }

  // ---------- 渲染状态 ----------
  @Local coverPath: string = '';
  @Local unavailable: boolean = false;
  @Local emptyVisible: boolean = true;
  @Local prepared: boolean = false;
  @Local videoRatio: number = 0;
  @Local cardW: number = 0;
  @Local cardH: number = 0;
  @Local audioTrackState: ScreenSaverVideoAudioTrackState = 'unknown';

  // ---------- 播放/进度状态（真实回调驱动） ----------
  @Local playbackPhase: ScreenSaverVideoPlaybackPhase = 'idle';
  @Local playbackError: string = '';
  @Local durationSec: number = 0;
  @Local currentSec: number = 0;
  /** 拖动中的预览值；拖动时 Slider 只显示它，不跟随 onUpdate。 */
  @Local seekDragging: boolean = false;
  @Local seekPreviewSec: number = 0;

  // ---------- 控件显隐（用户覆盖为 2s 自动隐藏） ----------
  @Local controlsVisible: boolean = false;
  private hideTimer: number = -1;
  /** 拖动 seek 的失败回退看门狗（一次性定时器，不是常驻循环）。 */
  private seekTimer: number = -1;
  private pendingSeekSec: number = -1;
  private seekPreviousSec: number = 0;

  // 控件触摸位移判定：>10vp 视为滑动，不执行点击。
  private controlDownX: number = 0;
  private controlDownY: number = 0;
  private controlMoved: boolean = false;

  private controller: VideoController = new VideoController();

  aboutToAppear(): void {
    // 卡片重建/实例重新挂载：集中重置所有视频卡声音。
    screenSaverVideoSoundSession.reset('card-appear');
    void this.prepareSource();
  }

  aboutToDisappear(): void {
    this.clearHideTimer();
    this.clearSeekTimer();
    this.pausePlayback();
    screenSaverVideoSoundSession.reset('card-disappear');
  }

  /** 换视频：停止旧播放、清空运行态，并重置声音会话。 */
  @Monitor('card.video.uri')
  onUriChanged(): void {
    this.clearHideTimer();
    this.clearSeekTimer();
    this.pausePlayback();
    this.card.video.playing = false;
    this.prepared = false;
    this.playbackPhase = 'idle';
    this.playbackError = '';
    this.durationSec = 0;
    this.currentSec = 0;
    this.seekDragging = false;
    this.seekPreviewSec = 0;
    this.audioTrackState = 'unknown';
    this.controlsVisible = false;
    screenSaverVideoSoundSession.reset('uri-change');
    void this.prepareSource();
  }

  @Monitor('card.video.playing')
  onPlayingChanged(): void {
    this.syncPlayback();
  }

  @Monitor('cardActive')
  onActiveChanged(): void {
    if (this.cardActive) {
      this.syncPlayback();
    } else {
      this.pausePlayback();
      this.controlsVisible = false;
      this.clearHideTimer();
      screenSaverVideoSoundSession.reset('card-inactive');
    }
  }

  @Monitor('controlsVisible')
  onControlsVisibleChanged(): void {
    ScreenSaverLogger.info(`video controls visible=${this.controlsVisible} card=${this.card.id}`);
  }

  /** 源准备：可用性、音轨、尺寸、封面。 */
  private async prepareSource(): Promise<void> {
    const uri = this.card.video.uri;
    if (uri.length === 0) {
      this.emptyVisible = true;
      this.unavailable = false;
      this.coverPath = '';
      this.videoRatio = 0;
      this.audioTrackState = 'unknown';
      return;
    }
    const readable = screenSaverVideoThumb.probeReadable(uri);
    this.unavailable = !readable;
    this.emptyVisible = false;
    if (!readable) {
      this.coverPath = '';
      this.videoRatio = 0;
      this.audioTrackState = 'unknown';
      return;
    }
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext | undefined;
    if (context === undefined) {
      return;
    }
    const trackState = await screenSaverVideoAudioProbe.probe(uri);
    if (this.card.video.uri !== uri) {
      return;
    }
    this.audioTrackState = trackState;
    if (trackState !== 'present') {
      screenSaverVideoSoundSession.disable(this.card.id);
    }
    ScreenSaverLogger.info(`video card audio track: ${trackState} uri=${uri}`);

    const videoSize = await screenSaverVideoThumb.probeVideoSize(uri);
    if (this.card.video.uri !== uri) {
      return;
    }
    let coverWidth = 640;
    let coverHeight = 360;
    if (videoSize !== undefined && videoSize.width > 0 && videoSize.height > 0) {
      this.videoRatio = videoSize.width / videoSize.height;
      const fitted: ScreenSaverFitSize = screenSaverFittedSize(videoSize.width, videoSize.height, 640, 360, 1280);
      coverWidth = fitted.width;
      coverHeight = fitted.height;
    } else {
      this.videoRatio = 0;
    }
    const cover = await screenSaverVideoThumb.firstFrameFile(context, uri, coverWidth, coverHeight);
    if (this.card.video.uri === uri) {
      this.coverPath = cover;
    }
  }

  private palette(): ScreensaverCardPalette {
    return screenSaverCardPalette(this.cardTone);
  }

  private textShadow(): ShadowOptions {
    return screenSaverTextShadow(this.cardHalo, this.palette().halo);
  }

  private contentWidth(): number {
    const width = this.cardW > 0 ? this.cardW : 320;
    const height = this.cardH > 0 ? this.cardH : 480;
    return screenSaverContainSize(width, height, this.videoRatio).width;
  }

  private contentHeight(): number {
    const width = this.cardW > 0 ? this.cardW : 320;
    const height = this.cardH > 0 ? this.cardH : 480;
    return screenSaverContainSize(width, height, this.videoRatio).height;
  }

  /** 单列窄条：只保留播放/暂停（用户确认的尺寸规则）。 */
  private compactControls(): boolean {
    return this.card.colSpan === 1;
  }

  private soundEnabled(): boolean {
    return screenSaverVideoSoundSession.isActive(this.card.id);
  }

  private soundAvailable(): boolean {
    return this.audioTrackState === 'present';
  }

  private soundHint(): string {
    if (this.audioTrackState === 'absent') {
      return '该视频无音轨';
    }
    if (this.audioTrackState === 'unsupported') {
      return '该视频音轨编码不受支持（如 AC3/DTS）';
    }
    if (this.audioTrackState === 'unknown') {
      return '音轨检测失败，暂不可开启声音';
    }
    return '';
  }

  private soundShortLabel(): string {
    if (this.audioTrackState === 'absent') {
      return '无音轨';
    }
    if (this.audioTrackState === 'unsupported') {
      return '音轨不支持';
    }
    if (this.audioTrackState === 'unknown') {
      return '检测失败';
    }
    return '';
  }

  /** 播放/暂停状态只由 Video 回调更新；未就绪时按 not playing 处理。 */
  private isActuallyPlaying(): boolean {
    return this.playbackPhase === 'playing';
  }

  private syncPlayback(): void {
    const contextActive = (this.cardMode === 'play' && this.cardActive) || this.previewActive;
    if (this.card.video.playing && contextActive && this.prepared &&
      this.playbackPhase !== 'error') {
      ScreenSaverLogger.info(`video start uri=${this.card.video.uri} preview=${this.previewActive}`);
      this.controller.start();
    } else {
      this.controller.pause();
    }
  }

  private pausePlayback(): void {
    try {
      this.controller.pause();
    } catch (err) {
      ScreenSaverLogger.warn('video pause failed');
    }
  }

  private togglePlayback(): void {
    if (this.card.video.uri.length === 0 || this.unavailable || this.playbackPhase === 'error') {
      return;
    }
    this.showControls();
    if (this.isActuallyPlaying() || this.card.video.playing) {
      this.card.video.playing = false;
      this.pausePlayback();
      screenSaverAppModel.save();
      return;
    }
    if (this.playbackPhase === 'finished') {
      this.currentSec = 0;
      this.seekPreviewSec = 0;
      try {
        this.controller.setCurrentTime(0, SeekMode.Accurate);
      } catch (err) {
        ScreenSaverLogger.warn('video restart seek failed');
      }
    }
    this.card.video.playing = true;
    screenSaverAppModel.save();
    if (this.prepared) {
      this.syncPlayback();
    }
  }

  private toggleSound(): void {
    this.showControls();
    if (!this.soundAvailable()) {
      const hint = this.soundHint();
      if (hint.length > 0) {
        this.toast(hint);
      }
      return;
    }
    if (this.soundEnabled()) {
      screenSaverVideoSoundSession.disable(this.card.id);
      return;
    }
    const systemState = screenSaverSystemAudioState.read();
    screenSaverVideoSoundSession.request(this.card.id);
    if (systemState.known && (systemState.muted || systemState.volume <= 0)) {
      this.toast('系统媒体音量为 0 或已静音，请在系统设置中调整');
    }
  }

  private showControls(): void {
    if (this.cardMode !== 'play' || this.card.video.uri.length === 0 || this.unavailable) {
      ScreenSaverLogger.info(`video controls blocked: mode=${this.cardMode} ` +
        `uri=${this.card.video.uri.length} unavailable=${this.unavailable} card=${this.card.id}`);
      return;
    }
    ScreenSaverLogger.info(`video controls show: card=${this.card.id}`);
    this.controlsVisible = true;
    this.scheduleHide();
  }

  private scheduleHide(): void {
    this.clearHideTimer();
    this.hideTimer = setTimeout((): void => {
      this.hideTimer = -1;
      if (this.seekDragging) {
        this.scheduleHide();
        return;
      }
      this.controlsVisible = false;
    }, 2000);
  }

  private clearHideTimer(): void {
    if (this.hideTimer >= 0) {
      clearTimeout(this.hideTimer);
      this.hideTimer = -1;
    }
  }

  private clearSeekTimer(): void {
    if (this.seekTimer >= 0) {
      clearTimeout(this.seekTimer);
      this.seekTimer = -1;
    }
    this.pendingSeekSec = -1;
  }

  private trackControlTouch(event: TouchEvent): void {
    if (event.type === TouchType.Down) {
      this.controlMoved = false;
      if (event.touches.length > 0) {
        this.controlDownX = event.touches[0].x;
        this.controlDownY = event.touches[0].y;
      }
      return;
    }
    if (event.type === TouchType.Move && event.touches.length > 0) {
      const dx = event.touches[0].x - this.controlDownX;
      const dy = event.touches[0].y - this.controlDownY;
      if (Math.sqrt(dx * dx + dy * dy) > 10) {
        this.controlMoved = true;
      }
    }
  }

  private controlClick(action: () => void): void {
    if (this.controlMoved) {
      this.controlMoved = false;
      return;
    }
    action();
  }

  private durationValid(): boolean {
    return Number.isFinite(this.durationSec) && this.durationSec > 0.05;
  }

  private sliderMax(): number {
    return this.durationValid() ? this.durationSec : 1;
  }

  private sliderValue(): number {
    const value = this.seekDragging ? this.seekPreviewSec : this.currentSec;
    if (!Number.isFinite(value) || value < 0) {
      return 0;
    }
    return Math.min(value, this.sliderMax());
  }

  private formatClock(seconds: number): string {
    if (!Number.isFinite(seconds) || seconds < 0) {
      return '--:--';
    }
    const total = Math.floor(seconds);
    const minutes = Math.floor(total / 60);
    const remain = total % 60;
    const mm = minutes < 10 ? `0${minutes}` : `${minutes}`;
    const ss = remain < 10 ? `0${remain}` : `${remain}`;
    return `${mm}:${ss}`;
  }

  private timeText(): string {
    if (!this.durationValid()) {
      return '--:-- / --:--';
    }
    const total = Math.ceil(this.durationSec);
    const shown = this.seekDragging ? this.seekPreviewSec : this.currentSec;
    const current = Math.min(Math.floor(shown), total);
    return `${this.formatClock(current)} / ${this.formatClock(total)}`;
  }

  private onSeekChange(value: number, mode: SliderChangeMode): void {
    if (!this.durationValid()) {
      return;
    }
    this.showControls();
    const clamped = Math.max(0, Math.min(value, this.durationSec));
    if (mode === SliderChangeMode.Begin || mode === SliderChangeMode.Moving) {
      this.seekDragging = true;
      this.seekPreviewSec = clamped;
      return;
    }
    if (mode === SliderChangeMode.Click) {
      this.seekDragging = true;
      this.seekPreviewSec = clamped;
    }
    this.commitSeek(clamped);
  }

  private commitSeek(target: number): void {
    if (this.pendingSeekSec >= 0 && Math.abs(target - this.pendingSeekSec) < 0.05) {
      return;
    }
    this.clearSeekTimer();
    const previous = this.currentSec;
    this.seekPreviousSec = previous;
    this.seekDragging = false;
    this.seekPreviewSec = target;
    // VideoController 没有 seek Promise，本机也不回调 onSeeking/onSeeked；
    // 这里乐观显示目标位置，若播放器报 onError 再回退（见 onError）。
    this.currentSec = target;
    if (Math.abs(target - previous) < 0.2) {
      return;
    }
    this.pendingSeekSec = target;
    ScreenSaverLogger.info(`video seek request: target=${target} previous=${previous}`);
    try {
      this.controller.setCurrentTime(target, SeekMode.Accurate);
    } catch (err) {
      this.revertSeek('进度跳转失败，已回到原位置');
      return;
    }
    // 仅用于清理 pending 标记；不因缺少回调而误判失败。
    this.seekTimer = setTimeout((): void => {
      this.seekTimer = -1;
      this.pendingSeekSec = -1;
    }, 1500);
  }

  private revertSeek(message: string): void {
    ScreenSaverLogger.warn(`video seek revert: ${message}`);
    this.pendingSeekSec = -1;
    this.seekDragging = false;
    this.seekPreviewSec = this.seekPreviousSec;
    this.currentSec = this.seekPreviousSec;
    this.clearSeekTimer();
    this.toast(message);
  }

  private handlePrepared(duration: number): void {
    if (Number.isFinite(duration) && duration > 0) {
      this.durationSec = duration;
    } else {
      this.durationSec = 0;
    }
    this.currentSec = Math.min(this.currentSec, this.durationValid() ? this.durationSec : 0);
    this.prepared = true;
    if (this.playbackPhase === 'idle') {
      this.playbackPhase = 'paused';
    }
    this.syncPlayback();
  }

  private handleUpdate(time: number): void {
    if (!Number.isFinite(time) || time < 0) {
      return;
    }
    if (this.seekDragging) {
      return;
    }
    // seek 已发出但播放器还没跳到目标时，忽略旧的进度回调，避免 UI 回跳。
    if (this.pendingSeekSec >= 0) {
      if (Math.abs(time - this.pendingSeekSec) < 1.5) {
        this.pendingSeekSec = -1;
        if (this.seekTimer >= 0) {
          clearTimeout(this.seekTimer);
          this.seekTimer = -1;
        }
        const max = this.durationValid() ? this.durationSec : time;
        this.currentSec = Math.min(time, max);
      }
      return;
    }
    const max = this.durationValid() ? this.durationSec : time;
    this.currentSec = Math.min(time, max);
  }

  private handleSeeked(time: number): void {
    ScreenSaverLogger.info(`video seeked: time=${time}`);
    if (this.seekTimer >= 0) {
      clearTimeout(this.seekTimer);
      this.seekTimer = -1;
    }
    this.pendingSeekSec = -1;
    if (Number.isFinite(time) && time >= 0) {
      this.currentSec = Math.min(time, this.durationValid() ? this.durationSec : time);
      this.seekPreviewSec = this.currentSec;
    }
    this.seekDragging = false;
  }

  private toast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message, duration: 1800 });
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

  private coverUri(): string {
    if (this.coverPath.length === 0) {
      return '';
    }
    if (this.coverPath.startsWith('file://')) {
      return this.coverPath;
    }
    return `file://${this.coverPath}`;
  }

  @Builder
  playButton(size: number) {
    Button({ type: ButtonType.Circle, stateEffect: true }) {
      SymbolGlyph(this.isActuallyPlaying() ? $r('sys.symbol.pause_fill') : $r('sys.symbol.play_fill'))
        .fontSize(size)
        .fontColor(['#F2F2F2'])
    }
    .width(44)
    .height(44)
    .padding(0)
    .backgroundColor('#66000000')
    .onTouch((event: TouchEvent): void => {
      this.trackControlTouch(event);
    })
    .onClick((): void => {
      this.controlClick((): void => {
        this.togglePlayback();
      });
    })
  }

  @Builder
  soundButton() {
    Button({ type: ButtonType.Circle, stateEffect: true }) {
      Column({ space: 1 }) {
        SymbolGlyph(this.soundEnabled() ? $r('sys.symbol.speaker_wave_2_fill') :
          $r('sys.symbol.speaker_slash_fill'))
          .fontSize(20)
          .fontColor([this.soundAvailable() ? '#F2F2F2' : '#80F2F2F2'])
        if (!this.soundAvailable()) {
          Text(this.soundShortLabel())
            .fontSize(7)
            .fontColor('#CCF2F2F2')
            .maxLines(1)
        }
      }
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    }
    .width(44)
    .height(44)
    .padding(0)
    .backgroundColor('#66000000')
    .opacity(this.soundAvailable() ? 1 : 0.55)
    .onTouch((event: TouchEvent): void => {
      this.trackControlTouch(event);
    })
    .onClick((): void => {
      this.controlClick((): void => {
        this.toggleSound();
      });
    })
  }

  @Builder
  compactOverlay() {
    Stack({ alignContent: Alignment.Center }) {
      this.playButton(24)
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  fullOverlay() {
    Stack({ alignContent: Alignment.Bottom }) {
      Row({ space: 3 }) {
        this.playButton(21)
        // 时间与进度条同一行：2×2 也能稳定显示当前/总时长。
        Text(this.timeText())
          .fontSize(8)
          .fontColor('#D9F2F2F2')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Clip })
          .width(68)
        Slider({
          value: this.sliderValue(),
          min: 0,
          max: this.sliderMax(),
          step: this.durationValid() && this.durationSec < 10 ? 0.1 : 1
        })
          .layoutWeight(1)
          .height(44)
          .trackThickness(2)
          .blockSize({ width: 10, height: 10 })
          .selectedColor('#F2F2F2')
          .trackColor('#66FFFFFF')
          .enabled(this.durationValid())
          .onChange((value: number, mode: SliderChangeMode): void => {
            this.onSeekChange(value, mode);
          })
        this.soundButton()
      }
      .width('100%')
      // 44vp 控件热区 + 26vp 底部安全留白：避开系统底部手势区。
      .height(70)
      .alignItems(VerticalAlign.Center)
      .padding({ left: 6, right: 6, bottom: 26 })
      .backgroundColor('#66000000')
    }
    .width('100%')
    .height('100%')
  }

  build() {
    Stack() {
      if (this.card.video.uri.length > 0 && !this.unavailable) {
        Stack() {
          Video({
            src: this.card.video.uri,
            previewUri: this.coverUri().length > 0 ? this.coverUri() : undefined,
            controller: this.controller
          })
            .autoPlay(false)
            .controls(false)
            .loop(this.card.video.loop)
            .muted(!this.soundEnabled())
            .objectFit(ImageFit.Contain)
            .width('100%')
            .height('100%')
            .backgroundColor(Color.Transparent)
            .borderRadius(SCREEN_SAVER_METRICS.cardRadius)
            .clip(true)
            // 原生 Video surface 会优先消费触摸；控件唤起必须挂在 Video 自身。
            .onClick((): void => {
              this.showControls();
            })
            .onPrepared((event?: PreparedInfo): void => {
              const duration = event !== undefined ? event.duration : -1;
              const systemAudio = screenSaverSystemAudioState.read();
              ScreenSaverLogger.info(`video component prepared: duration=${duration} ` +
                `muted=${!this.soundEnabled()} systemVolume=${systemAudio.volume} ` +
                `systemMuted=${systemAudio.muted} track=${this.audioTrackState}`);
              this.handlePrepared(duration);
            })
            .onStart((): void => {
              const systemAudio = screenSaverSystemAudioState.read();
              ScreenSaverLogger.info(`video component start: muted=${!this.soundEnabled()} ` +
                `systemVolume=${systemAudio.volume} systemMuted=${systemAudio.muted} ` +
                `track=${this.audioTrackState} renderers=` +
                screenSaverSystemAudioState.describeActiveRenderers());
              this.playbackPhase = 'playing';
              this.playbackError = '';
            })
            .onPause((): void => {
              if (this.playbackPhase !== 'finished' && this.playbackPhase !== 'error') {
                this.playbackPhase = 'paused';
              }
            })
            .onFinish((): void => {
              if (this.card.video.loop) {
                this.currentSec = 0;
                return;
              }
              this.card.video.playing = false;
              this.playbackPhase = 'finished';
              if (this.durationValid()) {
                this.currentSec = this.durationSec;
              }
              screenSaverAppModel.save();
            })
            .onError((err?: BusinessError): void => {
              const code = err !== undefined ? err.code : -1;
              ScreenSaverLogger.warn(`video component error: code=${code}`);
              if (this.pendingSeekSec >= 0) {
                this.revertSeek('进度跳转失败，已回到原位置');
              }
              this.prepared = false;
              this.playbackPhase = 'error';
              this.playbackError = code >= 0 ? `视频播放失败（${code}）` : '视频播放失败';
              this.controlsVisible = false;
              screenSaverVideoSoundSession.disable(this.card.id);
            })
            .onSeeking((event?: PlaybackInfo): void => {
              ScreenSaverLogger.info(`video seeking: time=${event !== undefined ? event.time : -1}`);
              if (event !== undefined && this.seekDragging) {
                this.seekPreviewSec = Math.min(event.time, this.sliderMax());
              }
            })
            .onSeeked((event?: PlaybackInfo): void => {
              if (event !== undefined) {
                this.handleSeeked(event.time);
              }
            })
            .onUpdate((event?: PlaybackInfo): void => {
              if (event !== undefined) {
                this.handleUpdate(event.time);
              }
            })

          // 透明点击捕获层：Video 原生 surface 不透传点击，用它可靠唤起控件。
          // 控件显示时移除，避免遮挡 Slider/按钮的命中测试。
          if (!this.controlsVisible) {
            Stack()
              .width('100%')
              .height('100%')
              .backgroundColor(Color.Transparent)
              .onClick((): void => {
                ScreenSaverLogger.info(`video catcher tap: card=${this.card.id}`);
                this.showControls();
              })
          }

          // 控件放在内容容器内：严格受视频内容边界裁剪，不会超出卡片。
          if (this.cardMode === 'play' && this.controlsVisible &&
            this.playbackPhase !== 'error') {
            if (this.compactControls()) {
              this.compactOverlay()
            } else {
              this.fullOverlay()
            }
          }
        }
        .width(this.contentWidth())
        .height(this.contentHeight())
        .align(Alignment.Center)
        .borderRadius(SCREEN_SAVER_METRICS.cardRadius)
        .clip(true)

        if (this.playbackPhase === 'error') {
          Column({ space: 4 }) {
            Text('视频播放失败')
              .fontSize(this.density() === 'minimal' ? SCREEN_SAVER_FONT.L6 : SCREEN_SAVER_FONT.L5)
              .fontColor(this.palette().textPrimary)
              .textShadow(this.textShadow())
            if (this.playbackError.length > 0 && this.density() !== 'minimal') {
              Text(this.playbackError)
                .fontSize(SCREEN_SAVER_FONT.L6)
                .fontColor(this.palette().textSecondary)
                .textShadow(this.textShadow())
            }
            if (this.cardMode === 'edit' && this.density() !== 'minimal') {
              Text('重选')
                .fontSize(SCREEN_SAVER_FONT.L5)
                .fontColor('#4A9EFF')
                .padding({ left: 8, right: 8, top: 4, bottom: 4 })
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
          .backgroundColor('#66000000')
        }
      }

      if (this.emptyVisible) {
        if (this.density() === 'minimal') {
          Text('无视频')
            .fontSize(SCREEN_SAVER_FONT.L6)
            .fontColor(this.palette().textTertiary)
            .textShadow(this.textShadow())
        } else {
          Column({ space: 4 }) {
            Text('未选择视频')
              .fontSize(this.density() === 'compact' ? SCREEN_SAVER_FONT.L5 : SCREEN_SAVER_FONT.L4)
              .fontColor(this.palette().textSecondary)
              .textShadow(this.textShadow())
            if (this.density() === 'full') {
              Text('在配置中选择本地视频')
                .fontSize(SCREEN_SAVER_FONT.L5)
                .fontColor(this.palette().textTertiary)
                .textShadow(this.textShadow())
            }
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
        }
      }

      if (this.unavailable) {
        Column({ space: 6 }) {
          Text('视频不可用')
            .fontSize(this.density() === 'minimal' ? SCREEN_SAVER_FONT.L6 :
            (this.density() === 'compact' ? SCREEN_SAVER_FONT.L5 : SCREEN_SAVER_FONT.L4))
            .fontColor(this.palette().textSecondary)
            .textShadow(this.textShadow())
          if (this.density() === 'full') {
            Text('文件已被删除 · 请在配置中重新选择')
              .fontSize(SCREEN_SAVER_FONT.L5)
              .fontColor(this.palette().textTertiary)
              .textShadow(this.textShadow())
          }
          if (this.cardMode === 'edit' && this.density() === 'full') {
            Column() {
              Text('重选')
                .fontSize(SCREEN_SAVER_FONT.L5)
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
      }
    }
    .width('100%')
    .height('100%')
    .clip(true)
    .backgroundColor(Color.Transparent)
    .onClick((): void => {
      if (this.cardMode === 'play' && this.card.video.uri.length > 0 && !this.unavailable &&
        this.playbackPhase !== 'error') {
        ScreenSaverLogger.info('video card surface tap');
        this.showControls();
      }
    })
    .onAreaChange((oldArea: Area, newArea: Area): void => {
      this.cardW = typeof newArea.width === 'number' ? newArea.width : 0;
      this.cardH = typeof newArea.height === 'number' ? newArea.height : 0;
    })
  }
}
