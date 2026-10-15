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
import { SCREEN_SAVER_METRICS } from '../common/ScreenSaverStyle';
import { screenSaverContainSize, screenSaverFittedSize, ScreenSaverFitSize } from '../common/ContentFit';
import {
  screenSaverCardPalette,
  screenSaverTextShadow,
  ScreensaverCardPalette
} from '../common/CardTheme';
import { screenSaverResolveDensity } from './CardCatalog';
import { ScreensaverCardDensity, ScreensaverCardInstance, ScreensaverCardMode,
  ScreensaverInkTone } from '../model/ConfigModels';

@ComponentV2
export struct ScreensaverVideoCard {
  @Param card: ScreensaverCardInstance = new ScreensaverCardInstance();
  @Param cardMode: ScreensaverCardMode = 'play';
  /** 屏保在前台时为 true：后台时立即停止播放（省电流控）。 */
  @Param cardActive: boolean = true;
  /**
   * 文字/图标墨色档与投影兜底开关（变更项 3.2/3.3）。
   * 由屏保页统一解析后下发（同一来源）；默认浅色（设置面板等深色容器里直接用默认）。
   */
  @Param cardTone: ScreensaverInkTone = 'light';
  @Param cardHalo: boolean = false;
  /**
   * 是否处于「设置面板置预览」：预览也需要能验证视频本身（变更项 3）。
   * 为 true 时允许在 cardMode==='edit' 下播放，入口就是面板里的「播放视频」开关。
   */
  @Param previewActive: boolean = false;
  /** 请求打开配置面板（「重选」按钮冒泡给父组件）。 */
  @Event onRequestConfig: () => void = (): void => {};

  /**
   * 当前尺寸对应的内容密度档（尺寸矩阵查表得到）。
   * 直接读 card 的跨度而不是父组件透传的 @Param：@Trace 字段变化会立即
   * 触发本视图重算，不受 ForEach 复用/@Builder 按值传参的影响。
   */
  private density(): ScreensaverCardDensity {
    return screenSaverResolveDensity(this.card.cardType, this.card.colSpan, this.card.rowSpan);
  }

  // ---------- 渲染状态 ----------
  @Local coverPath: string = '';        // 封面帧缓存文件路径
  @Local unavailable: boolean = false;  // 视频不可用（被删/无权限）
  @Local emptyVisible: boolean = true;  // 是否显示「未选择视频」占位
  @Local prepared: boolean = false;     // Video 组件是否已就绪（onPrepared 回调）
  /**
   * 视频原始宽高比（宽/高，0 = 未知）。
   * 变更项 2（视频统一处理）：画面放进「紧贴内容」的圆角容器，
   * 未铺满时内容四角为圆角、铺满时与卡片圆角一致（同一数值）。
   */
  @Local videoRatio: number = 0;
  /** 卡片实际宽高（vp），内容容器尺寸换算用（onAreaChange 更新）。 */
  @Local cardW: number = 0;
  @Local cardH: number = 0;

  /** Video 组件的控制器：start/pause/stop 都通过它操作。 */
  private controller: VideoController = new VideoController();

  /** 组件挂载：检查视频源可用性并生成封面帧。 */
  aboutToAppear(): void {
    void this.prepareSource();
  }

  /** 组件销毁：停止播放（离开屏保页面时最关键的省电动作）。 */
  aboutToDisappear(): void {
    this.pausePlayback();
  }

  /** 换了视频：先停旧播放，重新生成封面帧（新视频不继承「播放」开关）。 */
  @Monitor('card.video.uri')
  onUriChanged(): void {
    this.pausePlayback();
    this.card.video.playing = false;
    this.prepared = false;
    void this.prepareSource();
  }

  /** 播放开关变化：同步播放/暂停。 */
  @Monitor('card.video.playing')
  onPlayingChanged(): void {
    this.syncPlayback();
  }

  /** 退后台：立即暂停播放。 */
  @Monitor('cardActive')
  onActiveChanged(): void {
    if (!this.cardActive) {
      this.pausePlayback();
    }
  }

  /**
   * 准备视频源：
   *   - 空 uri → 显示「未选择视频」；
   *   - 探测不可读 → 显示「视频不可用」；
   *   - 可读 → 读取视频真实宽高（计算内容容器比例）并生成（或命中缓存的）首帧封面图。
   * 封面缓存仍以「目标尺寸」入文件名：变更项 2 之后按视频等比尺寸生成
   * （不再固定 640×360），避免竖屏视频封面被拉伸后与容器比例不符。
   */
  private async prepareSource(): Promise<void> {
    const uri = this.card.video.uri;
    if (uri.length === 0) {
      this.emptyVisible = true;
      this.unavailable = false;
      this.coverPath = '';
      this.videoRatio = 0;
      return;
    }
    const readable = screenSaverVideoThumb.probeReadable(uri);
    this.unavailable = !readable;
    this.emptyVisible = false;
    if (!readable) {
      this.coverPath = '';
      this.videoRatio = 0;
      return;
    }
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext | undefined;
    if (context === undefined) {
      return;
    }
    // 视频真实尺寸（元数据读取一次并缓存；失败时 videoRatio=0 → Contain 兜底）。
    const videoSize = await screenSaverVideoThumb.probeVideoSize(uri);
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
    this.coverPath = cover;
  }

  /** 当前墨色档的调色板（文字颜色与兜底投影色都从这里取，同一来源）。 */
  private palette(): ScreensaverCardPalette {
    return screenSaverCardPalette(this.cardTone);
  }

  /** 文字投影参数（halo 关闭时 radius=0 = 不画，不引入条件分支）。 */
  private textShadow(): ShadowOptions {
    return screenSaverTextShadow(this.cardHalo, this.palette().halo);
  }

  /**
   * 内容容器尺寸（vp）：按视频真实比例等比放进卡片，未铺满时留出透明区域。
   * 比例未知（探测失败/未选视频）时返回整卡尺寸（等价旧的 Contain 兜底渲染）。
   */
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

  /**
   * 播放同步（变更项 3 后的触发条件）：
   *   playing 开关打开 且（屏保展示态且在前台 或 处于设置面板预览）且 播放器已就绪。
   * 任何条件不满足一律 pause（宁可保守，不可偷跑解码）。
   *
   * 注意：这里**不依赖卡片上的按钮**——屏保态的播放入口是「单击卡片」
   * （由 ScreensaverPage.handlePlayModeCardTap 统一分发，改 playing 开关），
   * 编辑态/面板预览的入口是设置面板里的「播放视频」开关。
   */
  private syncPlayback(): void {
    const contextActive = (this.cardMode === 'play' && this.cardActive) || this.previewActive;
    if (this.card.video.playing && contextActive && this.prepared) {
      ScreenSaverLogger.info(`video start uri=${this.card.video.uri} preview=${this.previewActive}`);
      this.controller.start();
    } else {
      this.controller.pause();
    }
  }

  /**
   * 暂停播放（缺陷 4 修正点）。
   *
   * 只暂停，**不把 card.video.playing 写回 false**：离开屏保、切后台、组件销毁
   * 这些都是「临时状态」，用户打开的「播放视频」偏好应当保留，回到屏保后
   * 按原设置继续播。旧实现在这里顺手把 playing 置 false 并落盘，等于用户
   * 每次退出屏保就被静默改了一次配置。
   */
  private pausePlayback(): void {
    try {
      this.controller.pause();
    } catch (err) {
      ScreenSaverLogger.warn('video pause failed');
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
   * 封面帧的 URI 形式。
   * Video 组件的 src / previewUri 都走 URI 解析：沙箱文件必须带 file:// 前缀，
   * 只给纯路径会被当成「找不到的 base path」从而显示黑屏。
   */
  private coverUri(): string {
    if (this.coverPath.length === 0) {
      return '';
    }
    if (this.coverPath.startsWith('file://')) {
      return this.coverPath;
    }
    return `file://${this.coverPath}`;
  }

  /**
   * 界面结构（Stack 分层）——变更项 1~3 之后不再有任何常驻控件层：
   *   1. 视频画面（有视频且可用时）放进「内容容器」：
   *      · 容器尺寸 = 按视频真实比例等比放进卡片（变更项 2）；
   *      · 容器圆角 = 卡片圆角（SCREEN_SAVER_METRICS.cardRadius，10vp），
   *        未铺满时圆角落在画面四角上，铺满时与卡片圆角一致（两次确认后的方案）；
   *      · **不播放**时用 Image 显示封面帧（objectFit=Contain，letterbox 透明）；
   *      · **播放**时挂载 Video 组件（objectFit=Contain，容器已贴合视频比例，
   *        播放器内部不再出现 letterbox 黑边）。
   *   2. 「未选择视频」占位（极简档压成一行小字，避免 1×1 里文字溢出）；
   *   3. 「视频不可用」占位（含编辑态「重选」按钮，仅完整档显示按钮）。
   *
   * 已移除：卡片正中的播放/停止按钮与半透明遮罩层（原「▶/❚❚」角标）。
   * 播放入口改为：屏保展示态单击卡片（ScreensaverPage 统一分发）；
   * 编辑态/面板预览用设置面板里的「播放视频」开关。
   *
   * 文字颜色随墨色档切换（变更项 3.2），复杂背景/对比度不足时带轻投影兜底。
   */
  build() {
    Stack() {
      if (this.card.video.uri.length > 0 && !this.unavailable) {
        Stack() {
          if (!this.card.video.playing && this.coverUri().length > 0) {
            // 静态态：封面帧用 Image 显示（letterbox 透明）
            Image(this.coverUri())
              .objectFit(ImageFit.Contain)
              .width('100%')
              .height('100%')
          } else {
            Video({
              src: this.card.video.uri,
              // previewUri：播放器就绪前的预览图（封面帧缓存，需 file:// 前缀）
              previewUri: this.coverUri().length > 0 ? this.coverUri() : undefined,
              controller: this.controller
            })
              .autoPlay(false)   // 永不自动播放，由 syncPlayback 统一控制
              .controls(false)   // 屏保上不要系统控制条
              .loop(this.card.video.loop)
              .muted(this.card.video.muted)
              .objectFit(ImageFit.Contain)
              .width('100%')
              .height('100%')
              .backgroundColor(Color.Transparent)
              // 原生 surface 的圆角：官方 FAQ 要求「同组件设置 borderRadius +
              // 背景色透明」，父容器再叠一层 clip 裁剪兜底（双保险）。
              .borderRadius(SCREEN_SAVER_METRICS.cardRadius)
              .clip(true)
              .onPrepared((): void => {
                // 播放器就绪后才能 start；如果开关已经打开，这里立即开始播
                ScreenSaverLogger.info('video component prepared');
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
        }
        // 内容容器：紧贴视频比例 + 与卡片一致的圆角裁剪（变更项 2）
        .width(this.contentWidth())
        .height(this.contentHeight())
        .align(Alignment.Center)
        .borderRadius(SCREEN_SAVER_METRICS.cardRadius)
        .clip(true)
      }
      if (this.emptyVisible) {
        if (this.density() === 'minimal') {
          // 1×1 这类极小尺寸只留一行提示，保证「不是空白」且不溢出
          Text('无视频')
            .fontSize(10)
            .fontColor(this.palette().textTertiary)
            .textShadow(this.textShadow())
        } else {
          Column({ space: 4 }) {
            Text('未选择视频')
              .fontSize(this.density() === 'compact' ? 11 : 13)
              .fontColor(this.palette().textSecondary)
              .textShadow(this.textShadow())
            if (this.density() === 'full') {
              Text('在配置中选择本地视频')
                .fontSize(11)
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
            .fontSize(this.density() === 'minimal' ? 10 : (this.density() === 'compact' ? 11 : 13))
            .fontColor(this.palette().textSecondary)
            .textShadow(this.textShadow())
          if (this.density() === 'full') {
            Text('文件已被删除 · 请在配置中重新选择')
              .fontSize(11)
              .fontColor(this.palette().textTertiary)
              .textShadow(this.textShadow())
          }
          // 「重选」只在编辑态 + 完整档显示（小尺寸放不下按钮，整卡点按仍可进配置）
          if (this.cardMode === 'edit' && this.density() === 'full') {
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
      }
    }
    .width('100%')
    .height('100%')
    .clip(true)
    // 变更项 1/3.1：卡片自身无底色、无边框——画面未铺满时留白完全透明，
    // 露出屏保整体背景（不再是黑色块）。
    .backgroundColor(Color.Transparent)
    // 记录卡片实际尺寸：内容容器按比例实时重算（缩放/拖拽过程中圆角随之更新）。
    .onAreaChange((oldArea: Area, newArea: Area): void => {
      this.cardW = typeof newArea.width === 'number' ? newArea.width : 0;
      this.cardH = typeof newArea.height === 'number' ? newArea.height : 0;
    })
  }
}
