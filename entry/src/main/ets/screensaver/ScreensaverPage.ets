/**
 * =============================================================================
 * 屏保播放页（ScreensaverPage.ets）—— 整个应用的核心页面
 * =============================================================================
 *
 * 【这个文件是干什么的】
 * 全屏屏保页：4×8 网格上自由摆放时钟/相册/视频/Git 卡片。
 * 一个页面承载了五种交互状态：
 *   1. 播放态：卡片正常运转（时钟走字、照片轮播），点击唤出退出胶囊；
 *   2. 胶囊态：点屏幕出现「退出屏保」胶囊，几秒后自动淡出；
 *   3. 编辑态：长按进入，卡片可拖动换位、拉伸右下角改尺寸、
 *      单击选中、双击（再点）打开设置、× 删除、＋ 添加；
 *   4. 空态：一张卡片都没有时显示兜底时钟 + 引导文案；
 *   5. Sheet 态：编辑态下点卡片弹出对应设置面板（bindSheet）。
 *
 * 【防烧屏（burn-in）机制】
 * AMOLED 屏长时间显示静止内容会留残影。方案：每 15 分钟把「时钟」
 * 卡片微微挪动一次（5 组预设偏移轮流切换，编辑态不挪）。
 * 只挪时钟是因为它是唯一 24 小时纯静止内容的卡片。
 *
 * 【低电量自动退出】
 * 每 60 秒查一次电量：≤20%、非充电、非编辑态、且开关打开 →
 * toast 提示后自动退出屏保（省电优先）。
 *
 * 【编辑的安全网：快照】
 * 进入编辑态先 snapshotCards() 存一份布局文本快照；
 * 「取消」= restoreCardsFromSnapshot 回滚，「完成」= 保留改动。
 * 拖到一半误触取消也不怕。
 *
 * 【拖动/拉伸的手势数学】
 * 手指位移（vp）÷ 单元格尺寸 = 移动了几个格子（四舍五入）；
 * 拖动时 canPlace 实时校验目标格合法性，非法则描红边；
 * 松手非法 → 卡片弹回原位（animateOffsetsToZero 回弹动画）+ toast。
 * 拉伸（右下角手柄）同理，改的是 colSpan/rowSpan。
 *
 * 【断点适配】
 * 手机 4×8、折叠屏 8×8、平板 12×7（见 Breakpoints.ets）。
 * 宽屏播放态用 reflowForColumns 把手机布局重排到宽网格；
 * 编辑态永远回 4×8（编辑跨设备一致性），宽屏编辑网格限宽 480。
 * =============================================================================
 */

import { mediaquery } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import { batteryInfo } from '@kit.BasicServicesKit';
import { ScreenSaverLogger } from '../common/Logger';
import { ScreenSaverAppStateListener, screenSaverTicker } from '../common/Ticker';
import {
  screenSaverWindowController,
  screenSaverZeroInsets,
  ScreenSaverWindowInsets
} from '../common/WindowController';
import { screenSaverVibration } from '../common/VibrationHelper';
import { screenSaverVideoThumb } from '../common/VideoThumb';
import { screenSaverOpenEntry, ScreenSaverLinkResult } from '../common/AppLinkLauncher';
import { screenSaverRequestQuotesRefreshFor } from '../model/QuotesViewModel';
import { ScreensaverCardHost } from '../cards/CardHost';
import { screenSaverAppModel } from '../model/AppModel';
import { screenSaverGitViewModel } from '../model/GitViewModel';
import { SCREEN_SAVER_COLORS, SCREEN_SAVER_METRICS } from '../common/ScreenSaverStyle';
import { screenSaverCardPalette, screenSaverCurrentCardSkin, ScreensaverCardPalette,
  ScreensaverCardSkin } from '../common/CardTheme';
import { screenSaverCanvasBackground } from '../common/CanvasBackground';
import { screenSaverLockGestureController } from '../common/LockGestureController';
import { ScreensaverGallery } from './ScreensaverGallery';
import {
  screenSaverGridMetrics,
  screenSaverRectOf,
  screenSaverSpanFromOffset,
  screenSaverCellDelta,
  screenSaverCenteredRowOffset,
  screenSaverRowOffsetToVp,
  ScreenSaverGridMetrics,
  ScreenSaverSpan
} from '../common/GridLayout';
import {
  screenSaverMotionDuration,
  screenSaverSnapDuration,
  screenSaverBounceDuration,
  SCREEN_SAVER_MOTION_ENTER_MS,
  SCREEN_SAVER_MOTION_EXIT_MS,
  SCREEN_SAVER_MOTION_EDIT_ENTER_MS,
  SCREEN_SAVER_MOTION_CAPSULE_MS
} from '../common/Motion';
import {
  ScreenSaverBreakpoint,
  ScreenSaverBreakpointObserver
} from '../common/Breakpoints';
import { ScreensaverClockCard } from '../cards/ClockCardView';
import {
  screenSaverCardTypeName,
  screenSaverResolveDensity,
  screenSaverSnapCardSize
} from '../cards/CardCatalog';
import { ScreenSaverClockSettingsPanel } from './sheets/ClockSettingsSheet';
import { ScreenSaverPhotoSettingsPanel } from './sheets/PhotoSettingsSheet';
import { ScreenSaverVideoSettingsPanel } from './sheets/VideoSettingsSheet';
import { ScreenSaverGitSettingsPanel } from './sheets/GitSettingsSheet';
import { ScreenSaverWeatherSettingsPanel } from './sheets/WeatherSettingsSheet';
import { ScreenSaverEntrySettingsPanel } from './sheets/EntrySettingsSheet';
import { ScreenSaverQuotesSettingsPanel } from './sheets/QuotesSettingsSheet';
import { ScreenSaverCountdownSettingsPanel } from './sheets/CountdownSettingsSheet';
import { ScreenSaverTodoSettingsPanel } from './sheets/TodoSettingsSheet';
import {
  SCREEN_SAVER_DEFAULT_CANVAS_COLOR,
  SCREEN_SAVER_GRID_COLS,
  SCREEN_SAVER_GRID_ROWS,
  SCREEN_SAVER_LANDSCAPE_GRID_COLS,
  SCREEN_SAVER_LANDSCAPE_GRID_ROWS,
  ScreenSaverModeSettingsParam,
  ScreenSaverOrientation,
  SheetKind,
  ScreensaverCardInstance,
  ScreensaverLockScreenMode,
  screenSaverClampGalleryTheme,
  ScreensaverGridPos,
  ScreensaverInkTone
} from '../model/ConfigModels';

const FALLBACK_CARD_ID: string = 'fallback_clock';
/** 宽屏（折叠屏/平板）编辑态下网格的最大宽度，保证编辑视图不会太宽。 */
const SCREEN_SAVER_EDIT_MAX_WIDTH: number = 480;
/**
 * 悬浮层（需求 B）的 zIndex 基准：一定高于网格卡片的 zIndex（index，最大 <16）
 * 与拖动中的网格卡（20），保证「悬浮时钟始终盖在其他卡片之上」。
 */
const SCREEN_SAVER_FLOAT_Z_BASE: number = 30;
/** 拖动中的悬浮卡再抬一层，保证它在其它悬浮卡之上。 */
const SCREEN_SAVER_FLOAT_Z_DRAGGING: number = 40;
/**
 * 编辑态辅助层（网格线 + 顶/底栏）的层级。
 * 必须高于悬浮卡（30/40）：悬浮钟默认就停在屏幕上方，如果它的 zIndex 压过顶栏，
 * 会把「完成/取消」的点击吃掉（实测出现过点完成没反应）。
 */
const SCREEN_SAVER_EDIT_CHROME_Z: number = 50;

/**
 * 网格卡片条目：卡片 + 它在 layout.cards 里的原始下标。
 * 保留原始下标是为了让 positionOf / widePositions 的「下标一一对应」契约
 * 在过滤掉悬浮卡之后依然成立（需求 B）。
 */
interface ScreensaverGridEntry {
  card: ScreensaverCardInstance;
  index: number;
}

/** 悬浮卡的渲染矩形（vp）：位置 + 尺寸。 */
interface ScreensaverFloatRect {
  x: number;
  y: number;
  width: number;
  height: number;
}
/** 防烧屏位移间隔：15 分钟挪一次。 */
const SCREEN_SAVER_BURN_IN_INTERVAL_MS: number = 15 * 60 * 1000;
/** 低电量轮询间隔：60 秒查一次。 */
const SCREEN_SAVER_BATTERY_POLL_MS: number = 60 * 1000;
/** 低电量阈值：电量百分比 ≤ 20 触发退出。 */
const SCREEN_SAVER_LOW_BATTERY_SOC: number = 20;
/**
 * 防烧屏偏移表（vp）：五组偏移轮流使用。
 * 位移很小（≤5vp），肉眼几乎察觉不到，但能改变像素点亮周期。
 */
const SCREEN_SAVER_BURN_IN_OFFSETS: number[][] = [[0, 0], [5, -3], [-3, 5], [-5, -3], [3, 5]];

/**
 * 构建空态兜底时钟卡片（不进布局，只是本地展示用的假实例）。
 */
function buildFallbackCard(): ScreensaverCardInstance {
  const card = new ScreensaverCardInstance();
  card.id = FALLBACK_CARD_ID;
  card.cardType = 'clock';
  card.colSpan = 4;
  card.rowSpan = 2;
  card.clock.format = 'timeDate';
  return card;
}

@ComponentV2
export struct ScreenSaverPlayPage {
  @Param navStack: NavPathStack = new NavPathStack();
  /** 本次屏保方向：决定 4×8 / 5×2 网格与长按进入哪个方向的设置页。 */
  @Param mode: ScreenSaverOrientation = ScreenSaverOrientation.Portrait;

  // ============ 状态标志（@Local：组件内响应式） ============
  /** 整页透明度：进出场动画用（0 透明 → 1 完全显示）。 */
  @Local displayOpacity: number = 0;
  /**
   * 卡片层进场缩放（缺陷 2 转场）：0.98 → 1.0 与整页淡入同时进行，
   * 只在「进入屏保」这一瞬间跑一次，静止态恒为 1（无常驻动画）。
   */
  @Local cardLayerScale: number = 1;
  /** 「退出屏保」胶囊是否可见。 */
  @Local capsuleVisible: boolean = false;
  /** 是否处于编辑模式。 */
  @Local editMode: boolean = false;
  /** 进入编辑模式的过渡进度（0→1，驱动卡片缩放到 0.96 的入场感）。 */
  @Local editProgress: number = 0;
  /** 编辑态当前选中的卡片 id（'' = 无选中）。 */
  @Local selectedCardId: string = '';
  /** 设置面板（bindSheet）是否可见。 */
  @Local sheetVisible: boolean = false;
  /** 设置面板类型：clock/photo/video/git/none。 */
  @Local sheetKind: SheetKind = 'none';
  /** 设置面板对应的卡片 id。 */
  @Local sheetCardId: string = '';
  /** 当前锁屏形态：cards = 卡片锁屏（默认），gallery = 固定主题锁屏。 */
  @Local lockMode: ScreensaverLockScreenMode = 'cards';
  /** 固定主题索引（与 settings.galleryThemeIndex 同步并持久化）。 */
  @Local galleryThemeIndex: number = 0;
  /** 模式切换的一次性淡入透明度（≤300ms，不做两套叠加）。 */
  @Local modeSwitchOpacity: number = 1;
  /** 模式切换动画期间丢弃重复触发。 */
  private modeSwitching: boolean = false;

  // ============ 拖动状态 ============
  /** 正在拖动的卡片 id（'' = 没在拖）。 */
  @Local dragCardId: string = '';
  /**
   * 手指按下但「还没确认是拖动」的卡片 id（'' = 无）。
   * 存在的意义：把「按下」与「拖动」区分开——按下不碰选中态，
   * 只有位移超过阈值、真正开始拖动时才选中（缺陷 1 的根因修复点）。
   */
  @Local pendingTouchCardId: string = '';
  /** 拖动产生的 X 位移（vp），实时作用到卡片 offset 上。 */
  @Local dragOffsetX: number = 0;
  /** 拖动产生的 Y 位移（vp）。 */
  @Local dragOffsetY: number = 0;
  /** 拖动目标格非法（重叠/越界）标志——给卡片描红边。 */
  @Local dragInvalid: boolean = false;

  // ============ 拉伸（改尺寸）状态 ============
  /** 正在拉伸的卡片 id。 */
  @Local resizeCardId: string = '';
  @Local resizeOffsetX: number = 0;
  @Local resizeOffsetY: number = 0;
  /** 拉伸时显示的尺寸标签（如「4×2」；发生吸附时追加「已吸附」）。 */
  @Local resizeLabel: string = '';
  /** 本次拉伸的请求尺寸是否被尺寸矩阵吸附过（用于给用户反馈）。 */
  @Local resizeSnapped: boolean = false;
  /** 拉伸预览是否与其它卡片重叠/越界（重叠时描红边，松手回滚）。 */
  @Local resizeInvalid: boolean = false;

  // ============ 断点/网格 ============
  /** 当前断点的列数（播放态用，编辑态固定 4）。 */
  @Local columns: number = SCREEN_SAVER_GRID_COLS;
  /** 当前断点的行数（播放态用，编辑态固定 8）。 */
  @Local rows: number = SCREEN_SAVER_GRID_ROWS;
  /** 是否宽屏断点（≥600vp）。 */
  @Local isWide: boolean = false;
  /** 页面是否活跃（aboutToDisappear 置 false，让卡片停止刷新）。 */
  @Local pageActive: boolean = true;
  /** 空态兜底时钟（本地实例，不进布局）。 */
  @Local fallbackCard: ScreensaverCardInstance = buildFallbackCard();
  /** 防烧屏当前 X 偏移（vp）。 */
  @Local burnInShiftX: number = 0;
  /** 防烧屏当前 Y 偏移（vp）。 */
  @Local burnInShiftY: number = 0;
  // ============ 屏保整体背景（变更项 7） ============
  /**
   * 背景图片的（模糊）位图。由 screenSaverCanvasBackground 离屏一次计算后缓存，
   * 这里只持有引用用于渲染——页面重绘/卡片切换都不会触发重新计算。
   */
  @Local canvasPixel: image.PixelMap | undefined = undefined;
  /** 已加载的背景键（uri|blurRadius），用于避免重复触发加载。 */
  @Local canvasPixelKey: string = '';
  /** 刘海/底部导航指示条的安全区（vp）：只作用于内容层，背景仍全屏铺满。 */
  @Local safeInsets: ScreenSaverWindowInsets = screenSaverZeroInsets();

  // ============ 卡片皮肤（变更项 3.2/3.3：文字色三档 + 兜底投影） ============
  /**
   * 生效的文字墨色档（浅色/深色文字）。由 screenSaverCurrentCardSkin 统一解析：
   * 来源 = 设置里的档位（自动/黑/白）+ 整体背景明度（唯一判定来源），
   * 解析一次下发给整棵卡片树，避免「黑字配白色图标」这类不一致。
   */
  @Local inkTone: ScreensaverInkTone = 'light';
  /** 是否启用文字轻投影兜底（复杂背景或对比度不足时）。 */
  @Local inkHalo: boolean = false;

  // ============ 悬浮卡拖动状态（需求 B） ============
  /** 正在拖动的悬浮卡 id（'' = 没在拖）。 */
  @Local floatDragCardId: string = '';
  /** 悬浮卡拖动产生的 X/Y 位移（vp）。 */
  @Local floatDragOffsetX: number = 0;
  @Local floatDragOffsetY: number = 0;
  /**
   * 网格实际渲染尺寸（vp，onAreaChange 回调里更新，拖动换算用）。
   * 必须用 @Local：悬浮层、播放态居中偏移等都要在量到尺寸后重新计算，
   * 普通字段不参与观察模型，会导致悬浮层一直用「尺寸未知」的兜底值。
   */
  @Local gridW: number = 0;
  @Local gridH: number = 0;

  // ============ 非响应式私有字段 ============
  /** 胶囊自动隐藏定时器 id（-1 = 无定时器）。 */
  private capsuleTimer: number = -1;
  /** 防烧屏定时器 id。 */
  private burnInTimer: number = -1;
  /** 低电量轮询定时器 id。 */
  private batteryTimer: number = -1;
  /** 防烧屏偏移表当前步进（0~4 循环）。 */
  private burnInStep: number = 0;
  /** 拖动手势起点坐标（vp）。 */
  private touchStartX: number = 0;
  private touchStartY: number = 0;
  /** 拉伸手势起点坐标（vp）。 */
  private resizeTouchStartX: number = 0;
  private resizeTouchStartY: number = 0;
  /** 悬浮卡拖动的起点坐标（vp）。 */
  private floatTouchStartX: number = 0;
  private floatTouchStartY: number = 0;
  /** 拉伸开始前卡片的矩形（松手回滚用）。 */
  private resizeOriginColStart: number = 0;
  private resizeOriginRowStart: number = 0;
  private resizeOriginColSpan: number = 0;
  private resizeOriginRowSpan: number = 0;
  /**
   * 最近一次「拖动/缩放」提交的时间戳（毫秒）。
   * 用于屏蔽手势结束后系统补发的 click：拖动或缩放松手后 300ms 内的 click
   * 一律忽略，避免「刚拖完就把设置面板点开」。
   */
  private gestureCommitAtMs: number = 0;
  /**
   * 最近一次「屏保态卡片动作」的时间戳（毫秒）。
   * 让可交互卡片（跳转卡/视频卡）吃掉点击后不再唤出「退出屏保」胶囊——
   * 点击会在卡片与页面两层各派发一次，250ms 窗口内忽略页面那次。
   */
  private cardActionAtMs: number = 0;
  private lastScreenTapMs: number = 0;
  /** 最近一次长按时间：长按进入编辑后，松手补发的 click 不得触发行情刷新。 */
  private longPressAtMs: number = 0;
  /** 行情卡点击刷新限频：cardId → 最近一次发起时间（1s 内合并）。 */
  private quotesTapAt: Map<string, number> = new Map<string, number>();
  /**
   * 最近一次打开方向设置页的时间戳：卡片级与页面级长按可能同时命中，
   * 800ms 内只允许 push 一次，避免叠两个设置页。
   */
  private settingsOpenedAtMs: number = 0;
  /** 编辑模式快照（JSON 文本），「取消」时回滚。 */
  private editSnapshotText: string = '';
  /** 宽屏重排后的卡片位置表（与 layout.cards 下标一一对应）。 */
  private widePositions: ScreensaverGridPos[] = [];
  /** 断点观察者（监听窗口宽度变化切换网格规格）。 */
  private breakpointObserver: ScreenSaverBreakpointObserver = new ScreenSaverBreakpointObserver();
  /**
   * 前后台切换：退后台立即把 pageActive 置 false，并停掉防烧屏/低电量/胶囊定时器；
   * 回前台恢复（行情轮询随 cardActive 重新启动）。
   */
  private appStateListener: ScreenSaverAppStateListener = (active: boolean): void => {
    this.pageActive = active;
    if (active) {
      this.startBurnInTimer();
      this.startBatteryWatch();
    } else {
      this.stopBurnInTimer();
      this.stopBatteryWatch();
      this.hideCapsule();
    }
  };

  /**
   * 页面出现：
   * 1. 进入「屏保窗口模式」：保持亮屏 + 沉浸式全屏（按设置决定 keepScreenOn）；
   * 2. 启动断点监听；
   * 3. 进场淡入动画（减弱动效时直接显示，不播动画）；
   * 4. Git 卡片先显示本地缓存（hydrate），避免白等网络；
   * 5. 启动防烧屏定时器和低电量轮询。
   */
  aboutToAppear(): void {
    // 方向由入口通过 @Param 带入；这里再同步一次，保证卡片读写命中正确布局。
    screenSaverAppModel.setActiveOrientation(this.mode);
    // 固定锁屏模式不持久化：每次进入屏保都从卡片锁屏开始，避免被困住。
    this.lockMode = 'cards';
    this.galleryThemeIndex = screenSaverClampGalleryTheme(
      screenSaverAppModel.layout.settings.galleryThemeIndex);
    const context = this.getUIContext().getHostContext();
    if (context !== undefined) {
      void screenSaverWindowController.enter(context, screenSaverAppModel.layout.settings.keepScreenOn,
        this.mode);
    }
    this.breakpointObserver.start(
      (condition: string): mediaquery.MediaQueryListener => this.getUIContext().getMediaQuery().matchMediaSync(condition),
      (value: ScreenSaverBreakpoint): void => {
        this.onBreakpointChanged(value);
      });
    // 进场动画（缺陷 2 转场）：一次性「整页淡入 + 卡片层轻微放大」，
    // 让卡片不是硬切入；motionDuration 会按「减弱动效」设置压缩时长，0 则直接显示。
    // 只用一次 animateTo，不引入常驻动画——屏保静止态没有任何动画在跑。
    const enterMs = screenSaverMotionDuration(SCREEN_SAVER_MOTION_ENTER_MS);
    if (enterMs <= 0) {
      this.displayOpacity = 1;
      this.cardLayerScale = 1;
    } else {
      this.cardLayerScale = 0.98;
      this.getUIContext().animateTo({
        duration: enterMs,
        curve: Curve.EaseOut
      }, (): void => {
        this.displayOpacity = 1;
        this.cardLayerScale = 1;
      });
    }
    screenSaverGitViewModel.hydrateFromCache();
    this.refreshCanvasBackground();
    this.refreshCardSkin();
    // 启动定时器/轮询并注册前后台监听（幂等：onShown 再次调用不会重复起表）。
    this.onPageShown();
  }

  /**
   * 页面重新可见（首次显示 / 从方向设置页返回 / 回前台）。
   * 恢复防烧屏、低电量轮询与卡片激活态；行情轮询由卡片自身的
   * cardActive 变化驱动（pageActive=true 后自动重新开始）。
   */
  private onPageShown(): void {
    this.pageActive = true;
    // 从「屏保设置」返回时同步固定锁屏主题；主题选择器已在设置页持久化。
    this.galleryThemeIndex = screenSaverClampGalleryTheme(
      screenSaverAppModel.layout.settings.galleryThemeIndex);
    this.startBurnInTimer();
    this.startBatteryWatch();
    screenSaverTicker.addAppStateListener(this.appStateListener);
    this.refreshCanvasBackground();
    this.refreshCardSkin();
    this.refreshSafeInsets();
    this.syncLockGestureSubscription();
    ScreenSaverLogger.info(`screensaver page shown: ${this.mode}`);
  }

  /**
   * 屏保要求卡片铺满整屏：内容层不再加刘海/导航条内边距，
   * 四边都从窗口边缘开始（背景与卡片均全屏）。
   */
  private refreshSafeInsets(): void {
    this.safeInsets = screenSaverZeroInsets();
  }

  /**
   * 页面被遮住（push 方向设置页）或退出：停止全部轮询/延时器。
   * 与 onPageShown 成对出现，保证进入设置页后屏保侧不再发请求。
   */
  private onPageHidden(): void {
    this.pageActive = false;
    this.hideCapsule();
    this.stopBurnInTimer();
    this.stopBatteryWatch();
    this.stopLockGestureSubscription('page hidden');
    screenSaverTicker.removeAppStateListener(this.appStateListener);
    ScreenSaverLogger.info('screensaver page hidden: timers stopped');
  }

  /**
   * 遮盖切换订阅的唯一入口：仅在「屏保可见 + 展示态 + 开关开启」时订阅。
   * 编辑态、设置面板、切后台、离开页面都必须解除。
   */
  private syncLockGestureSubscription(): void {
    const settings = screenSaverAppModel.layout.settings;
    const shouldRun = this.pageActive && !this.editMode && !this.sheetVisible &&
      settings.gestureLockEnabled;
    if (!shouldRun) {
      this.stopLockGestureSubscription('not displaying');
      return;
    }
    if (screenSaverLockGestureController.isRunning()) {
      return;
    }
    const ok = screenSaverLockGestureController.start((): void => {
      this.onCoverGestureTriggered();
    });
    if (!ok) {
      // 订阅失败：关闭开关并落盘，避免每次进屏保都重试；原因由设置页展示。
      settings.gestureLockEnabled = false;
      screenSaverAppModel.save();
      ScreenSaverLogger.warn(`lock gesture start failed: ${screenSaverLockGestureController.errorText}`);
    }
  }

  private stopLockGestureSubscription(reason: string): void {
    if (screenSaverLockGestureController.isRunning()) {
      screenSaverLockGestureController.stop(reason);
    }
  }

  /** 传感器上升沿回调：模式切换 + 一次性过渡。 */
  private onCoverGestureTriggered(): void {
    if (!this.pageActive || this.editMode || this.sheetVisible || this.modeSwitching) {
      return;
    }
    this.switchLockMode(this.lockMode === 'cards' ? 'gallery' : 'cards');
  }

  /**
   * 锁屏形态切换：整体替换内容区（不做两套叠加），只做一次 ≤300ms 的淡入。
   * 切到 gallery 时卡片整体卸载，卡片自己的定时器/轮询在 aboutToDisappear 中停止；
   * 切回 cards 时卡片重新挂载，按既有「进入屏保请求一次 + 交易时段 5s」恢复。
   */
  private switchLockMode(target: ScreensaverLockScreenMode): void {
    if (this.modeSwitching || this.lockMode === target) {
      return;
    }
    this.modeSwitching = true;
    this.hideCapsule();
    if (target === 'gallery') {
      this.stopBurnInTimer();
      this.galleryThemeIndex = screenSaverClampGalleryTheme(
        screenSaverAppModel.layout.settings.galleryThemeIndex);
    } else {
      this.startBurnInTimer();
    }
    this.lockMode = target;
    this.syncLockGestureSubscription();
    this.modeSwitchOpacity = 0.2;
    this.getUIContext().animateTo({
      duration: 240,
      curve: Curve.EaseOut
    }, (): void => {
      this.modeSwitchOpacity = 1;
    });
    setTimeout((): void => {
      this.modeSwitching = false;
    }, 260);
    ScreenSaverLogger.info(`lock screen mode switched: ${target}`);
  }

  /**
   * 重新解析卡片皮肤（变更项 3.2）：文字墨色档 + 兜底投影开关。
   * 判定来源是整体背景（色值亮度或背景图主色亮度的缓存），解析是纯读取，
   * 不触发任何解码/取色——背景图就绪时由 refreshCanvasBackground 回调再刷一次。
   */
  private refreshCardSkin(): void {
    const skin: ScreensaverCardSkin = screenSaverCurrentCardSkin();
    this.inkTone = skin.tone;
    this.inkHalo = skin.halo;
  }

  /**
   * 加载/刷新屏保整体背景图片（变更项 7）。
   *
   * 性能约束：模糊是**离屏一次性计算**（screenSaverCanvasBackground 内部缓存），
   * 这里只在「图片/模糊开关的键变化」时才触发；键不变时直接复用已缓存的位图，
   * 卡片切换、进出编辑态、回前台都不会重算。
   */
  private refreshCanvasBackground(): void {
    const settings = screenSaverAppModel.layout.settings;
    const uri = settings.canvasImageUri;
    if (uri.length === 0) {
      this.canvasPixel = undefined;
      this.canvasPixelKey = '';
      screenSaverCanvasBackground.clear();
      return;
    }
    const key = `${uri}|${settings.canvasBlur ? 'blur' : 'plain'}`;
    if (key === this.canvasPixelKey && this.canvasPixel !== undefined) {
      return;
    }
    this.canvasPixelKey = key;
    screenSaverCanvasBackground.ensure(uri, settings.canvasBlur).then((pixel: image.PixelMap | undefined): void => {
      this.canvasPixel = pixel;
      // 背景图就绪后重算皮肤：图片背景的明度来自刚缓存的主色亮度（变更项 3.2）。
      this.refreshCardSkin();
      ScreenSaverLogger.info(`canvas background applied: uri=${uri} blurred=${settings.canvasBlur}`);
    });
  }

  /** 回前台时补一次背景校验（设置在别处被改过时也能生效）。 */
  @Monitor('pageActive')
  onPageActiveChanged(): void {
    if (this.pageActive) {
      this.refreshCanvasBackground();
      this.refreshCardSkin();
    }
    this.syncLockGestureSubscription();
  }

  /** 编辑态/设置面板会打断「屏保展示态」，立即解除传感器订阅。 */
  @Monitor('editMode', 'sheetVisible')
  onLockGestureContextChanged(): void {
    this.syncLockGestureSubscription();
  }

  /**
   * 页面消失（退出屏保）：
   * 清掉所有定时器 → 退出屏保窗口模式 → 强制把未落盘的改动刷盘。
   */
  aboutToDisappear(): void {
    this.onPageHidden();
    this.breakpointObserver.stop();
    const context = this.getUIContext().getHostContext();
    if (context !== undefined) {
      void screenSaverWindowController.exit(context);
    }
    void screenSaverAppModel.flush();
  }

  /**
   * 断点变化：更新网格列行数；宽屏时把手机布局重排（reflow）到宽网格，
   * 播放态优先用重排结果。
   */
  private onBreakpointChanged(value: ScreenSaverBreakpoint): void {
    this.columns = value.columns;
    this.rows = value.rows;
    // 横屏方向固定 5×2，不使用竖屏的宽屏重排（否则 4×8 布局会被再折算一次）。
    const useWide = value.isWide && this.mode === ScreenSaverOrientation.Portrait;
    this.isWide = useWide;
    if (useWide) {
      this.widePositions = screenSaverAppModel.reflowForColumns(value.columns, value.rows);
    } else {
      this.widePositions = [];
    }
  }

  /** 当前布局里的卡片列表（单一数据源 AppModel）。 */
  private cards(): ScreensaverCardInstance[] {
    return screenSaverAppModel.layout.cards;
  }

  private cardAt(index: number): ScreensaverCardInstance {
    return screenSaverAppModel.layout.cards[index];
  }

  /**
   * 计算卡片 index 的渲染位置：
   * 播放态 + 宽屏 → 用重排位置表（widePositions）；
   * 其余情况（编辑态、窄屏）→ 用卡片自身存储的位置。
   */
  private positionOf(index: number, card: ScreensaverCardInstance): ScreensaverGridPos {
    if (!this.editMode && this.mode === ScreenSaverOrientation.Portrait && this.isWide &&
      index < this.widePositions.length) {
      return this.widePositions[index];
    }
    const pos: ScreensaverGridPos = {
      colStart: card.colStart,
      rowStart: card.rowStart,
      colSpan: card.colSpan,
      rowSpan: card.rowSpan
    };
    return pos;
  }

  /**
   * 渲染用的位置与跨度。
   *
   * 拉伸预览直接写在卡片自身（card.colStart/colSpan 等 @Trace 字段）上，
   * 所以这里统一读卡片字段即可——GridItem 与卡片内容都会跟着刷新。
   * （早先尝试用「页面临时预览跨度」再经 @Builder 参数下发，
   * 但 @Builder 多参数按值传递、ForEach 复用时不刷新，实测会读到陈旧值。）
   */
  private renderSpanOf(index: number, card: ScreensaverCardInstance): ScreensaverGridPos {
    return this.positionOf(index, card);
  }

  // ==================== 悬浮层（需求 B）====================

  /**
   * 网格层要渲染的卡片（排除悬浮卡）。
   * 带上 layout.cards 的原始下标，保证 positionOf 与 widePositions 的下标对应关系不被破坏。
   */
  private gridEntries(): ScreensaverGridEntry[] {
    const entries: ScreensaverGridEntry[] = [];
    const cards = this.cards();
    for (let index = 0; index < cards.length; index++) {
      const card = cards[index];
      if (card.floating) {
        continue;
      }
      const entry: ScreensaverGridEntry = { card: card, index: index };
      entries.push(entry);
    }
    return entries;
  }

  /** 悬浮层要渲染的卡片（不占网格、始终在最上层）。 */
  private floatingEntries(): ScreensaverGridEntry[] {
    const entries: ScreensaverGridEntry[] = [];
    const cards = this.cards();
    for (let index = 0; index < cards.length; index++) {
      const card = cards[index];
      if (!card.floating) {
        continue;
      }
      const entry: ScreensaverGridEntry = { card: card, index: index };
      entries.push(entry);
    }
    return entries;
  }

  /**
   * 悬浮卡的渲染矩形：尺寸仍由跨度换算（colSpan/4 × rowSpan/8），
   * 位置按存储的 floatX/floatY 并夹进画布，保证整卡可见。
   * 拖动中用临时位移叠加，松手才写回模型（避免每帧落盘）。
   */
  private floatRect(card: ScreensaverCardInstance): ScreensaverFloatRect {
    // 悬浮卡按手机网格（4×8）的跨度换算显示尺寸；位置用 floatX/floatY 并夹进画布。
    const metrics = this.gridMetrics();
    const size = screenSaverRectOf(0, 0, card.colSpan, card.rowSpan, metrics);
    const width = this.gridW > 0 ? size.width : 100;
    const height = this.gridH > 0 ? size.height : 100;
    const maxX = Math.max(0, this.gridW - width);
    const maxY = Math.max(0, this.gridH - height);
    const dragX = this.floatDragCardId === card.id ? this.floatDragOffsetX : 0;
    const dragY = this.floatDragCardId === card.id ? this.floatDragOffsetY : 0;
    const rect: ScreensaverFloatRect = {
      // 网格内容层有安全区内边距时，悬浮层坐标也要跟着偏移，保持所见即所得。
      x: Math.max(0, Math.min(card.floatX + dragX, maxX)) + this.safeInsets.left,
      y: Math.max(0, Math.min(card.floatY + dragY, maxY)) + this.safeInsets.top,
      width: width,
      height: height
    };
    return rect;
  }

  /**
   * 悬浮卡触摸（编辑态）：
   * Down 记录起点（锁定位置时直接提示，不进入拖动）；
   * Move 更新位移（自由移动，不做网格吸附）；
   * Up/Cancel 夹取边界后写回模型并落盘。
   */
  private onFloatTouch(card: ScreensaverCardInstance, event: TouchEvent): void {
    const touch = event.touches[0];
    if (touch === undefined) {
      return;
    }
    // 变更项 3：TouchObject.windowX/windowY 的官方单位就是 **vp**（不是 px），
    // 不能再做 px2vp 转换——否则位移会被压缩成 1/屏幕密度，拖动几乎不动。
    const x = touch.windowX;
    const y = touch.windowY;
    if (event.type === TouchType.Down) {
      if (card.floatLocked) {
        this.toast('位置已锁定：可在「卡片设置」里解锁');
        return;
      }
      this.floatDragCardId = card.id;
      this.floatTouchStartX = x;
      this.floatTouchStartY = y;
      this.floatDragOffsetX = 0;
      this.floatDragOffsetY = 0;
      this.selectCard(card.id);
      return;
    }
    if (event.type === TouchType.Move) {
      if (this.floatDragCardId === card.id) {
        this.floatDragOffsetX = x - this.floatTouchStartX;
        this.floatDragOffsetY = y - this.floatTouchStartY;
      }
      return;
    }
    if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      if (this.floatDragCardId !== card.id) {
        return;
      }
      if (event.type === TouchType.Up) {
        this.floatDragOffsetX = x - this.floatTouchStartX;
        this.floatDragOffsetY = y - this.floatTouchStartY;
      }
      const targetX = card.floatX + this.floatDragOffsetX;
      const targetY = card.floatY + this.floatDragOffsetY;
      screenSaverAppModel.setFloatPosition(card.id, targetX, targetY, this.gridW, this.gridH);
      ScreenSaverLogger.info(`float commit ${card.id} -> ${card.floatX},${card.floatY}`);
      this.floatDragCardId = '';
      this.floatDragOffsetX = 0;
      this.floatDragOffsetY = 0;
      this.gestureCommitAtMs = Date.now();
    }
  }

  /**
   * 生成 Grid 的等分模板："1fr 1fr 1fr 1fr"（列数/行数动态）。
   */
  private templateOf(count: number): string {
    let text = '';
    for (let index = 0; index < count; index++) {
      text = index === 0 ? '1fr' : `${text} 1fr`;
    }
    return text;
  }

  /**
   * 长按进入「当前方向的设置页」（唯一入口）。
   * 进入前先停掉屏保侧的轮询/延时器；返回时 NavDestination.onShown 恢复。
   */
  private openModeSettings(): void {
    if (Date.now() - this.settingsOpenedAtMs < 800) {
      return;
    }
    this.settingsOpenedAtMs = Date.now();
    ScreenSaverLogger.info(`open mode settings: ${this.mode}`);
    if (this.editMode) {
      // 编辑中的位置/尺寸已经通过 drag/resize 提交；进入设置页前收起编辑层。
      this.exitEditMode(false);
    }
    this.onPageHidden();
    const param: ScreenSaverModeSettingsParam = { from: 'screensaver', mode: this.mode };
    this.navStack.pushPathByName('modeSettings', param);
  }

  /**
   * 旧的编辑模式入口：保留方法体但不再被任何手势调用。
   * 屏保页本轮起为纯播放态，卡片布局编辑全部在方向设置页完成。
   */
  private enterEditMode(): void {
    if (this.editMode) {
      return;
    }
    ScreenSaverLogger.info('enter edit mode');
    screenSaverVibration.longPressFeedback();
    this.editSnapshotText = screenSaverAppModel.snapshotCards();
    this.editMode = true;
    // 编辑入场：editProgress 0 → 1（卡片随之缩到 0.96）
    const duration = screenSaverMotionDuration(SCREEN_SAVER_MOTION_EDIT_ENTER_MS);
    if (duration <= 0) {
      this.editProgress = 1;
    } else {
      this.getUIContext().animateTo({
        duration: duration,
        curve: Curve.EaseOut
      }, (): void => {
        this.editProgress = 1;
      });
    }
    this.hideCapsule();
  }

  /**
   * 退出编辑模式。
   * restore=true：用快照回滚布局（「取消」）；
   * restore=false：保留改动（「完成」/系统返回键）。
   */
  private exitEditMode(restore: boolean): void {
    if (restore) {
      screenSaverAppModel.restoreCardsFromSnapshot(this.editSnapshotText);
    }
    this.editSnapshotText = '';
    this.selectedCardId = '';
    this.editMode = false;
    this.editProgress = 0;
    this.closeSheet();
  }

  /**
   * 显示「退出屏保」胶囊：几秒后自动淡出（capsuleAutoHideMs）。
   */
  private showCapsule(): void {
    if (this.editMode) {
      return;
    }
    ScreenSaverLogger.info('capsule shown');
    this.capsuleVisible = true;
    this.stopCapsuleTimer();
    this.capsuleTimer = setTimeout((): void => {
      this.capsuleTimer = -1;
      this.hideCapsuleWithFade();
    }, SCREEN_SAVER_METRICS.capsuleAutoHideMs);
  }

  /** 立即隐藏胶囊（无动画）。 */
  private hideCapsule(): void {
    this.stopCapsuleTimer();
    this.capsuleVisible = false;
  }

  /** 带淡出动画隐藏胶囊（自动超时用）。 */
  private hideCapsuleWithFade(): void {
    this.stopCapsuleTimer();
    const duration = screenSaverMotionDuration(SCREEN_SAVER_MOTION_CAPSULE_MS);
    if (duration <= 0) {
      this.capsuleVisible = false;
      return;
    }
    this.getUIContext().animateTo({
      duration: duration,
      curve: Curve.EaseOut
    }, (): void => {
      this.capsuleVisible = false;
    });
  }

  /** 清除胶囊自动隐藏定时器。 */
  private stopCapsuleTimer(): void {
    if (this.capsuleTimer >= 0) {
      clearTimeout(this.capsuleTimer);
      this.capsuleTimer = -1;
    }
  }

  /**
   * 启动防烧屏定时器：每 15 分钟切换到下一组偏移。
   */
  private startBurnInTimer(): void {
    if (this.burnInTimer >= 0) {
      return;
    }
    this.burnInTimer = setInterval((): void => {
      this.burnInStep = (this.burnInStep + 1) % SCREEN_SAVER_BURN_IN_OFFSETS.length;
      const offset = SCREEN_SAVER_BURN_IN_OFFSETS[this.burnInStep];
      this.burnInShiftX = offset[0];
      this.burnInShiftY = offset[1];
    }, SCREEN_SAVER_BURN_IN_INTERVAL_MS);
  }

  /** 停止防烧屏定时器并复位偏移。 */
  private stopBurnInTimer(): void {
    if (this.burnInTimer >= 0) {
      clearInterval(this.burnInTimer);
      this.burnInTimer = -1;
    }
    this.burnInShiftX = 0;
    this.burnInShiftY = 0;
  }

  /**
   * 计算卡片 X 方向的防烧屏位移：
   * 编辑态不挪（否则拖动/布局坐标会乱）；只有时钟卡片挪
   * （其它卡片内容本身会动，不存在像素长期点亮问题）。
   */
  private burnInX(card: ScreensaverCardInstance): number {
    if (this.editMode || card.cardType !== 'clock') {
      return 0;
    }
    return this.burnInShiftX;
  }

  /** Y 方向防烧屏位移（规则同 burnInX）。 */
  private burnInY(card: ScreensaverCardInstance): number {
    if (this.editMode || card.cardType !== 'clock') {
      return 0;
    }
    return this.burnInShiftY;
  }

  /**
   * 启动低电量轮询：立即查一次，之后每 60 秒查一次。
   */
  private startBatteryWatch(): void {
    if (this.batteryTimer >= 0) {
      return;
    }
    this.checkBattery();
    this.batteryTimer = setInterval((): void => {
      this.checkBattery();
    }, SCREEN_SAVER_BATTERY_POLL_MS);
  }

  /** 停止低电量轮询。 */
  private stopBatteryWatch(): void {
    if (this.batteryTimer >= 0) {
      clearInterval(this.batteryTimer);
      this.batteryTimer = -1;
    }
  }

  /**
   * 低电量检查：
   * 编辑态不打扰 / 开关没开不查 / 电量 >20% 或 ≤0（读取异常）不退 /
   * 充电中不退（充电时耗电无所谓）。
   * 满足全部条件 → toast + 自动退出屏保。
   */
  private checkBattery(): void {
    if (this.editMode || !screenSaverAppModel.layout.settings.lowBatteryAutoExit) {
      return;
    }
    const soc = batteryInfo.batterySOC;
    if (soc <= 0 || soc > SCREEN_SAVER_LOW_BATTERY_SOC) {
      return;
    }
    if (batteryInfo.chargingStatus === batteryInfo.BatteryChargeState.ENABLE) {
      return;
    }
    this.toast('电量低于 20%，已自动退出屏保');
    this.exitScreensaver();
  }

  /**
   * 播放态点击屏幕：切换胶囊显隐（编辑态不响应）。
   *
   * 变更项 2/3 的联动：可交互卡片（跳转卡/视频卡）会「吃掉」这一次点击，
   * 此时不允许再把胶囊唤出来（否则「点卡片」会同时触发卡片动作 + 弹胶囊）。
   * 判定方式是时间窗：卡片动作刚执行过（250ms 内）就跳过唤胶囊，
   * 因为点击会在卡片与页面两层各派发一次。
   */
  private handleScreenTap(): void {
    // 固定屏保互动已全部注释：gallery 展示态不响应任何屏幕点击（不唤胶囊、不触发特效）
    if (this.lockMode === 'gallery') {
      return;
    }
    const now = Date.now();
    if (now - this.lastScreenTapMs < 240) {
      return;
    }
    this.lastScreenTapMs = now;
    ScreenSaverLogger.info(`screen tap, editMode=${this.editMode}, capsule=${this.capsuleVisible}`);
    if (this.editMode) {
      return;
    }
    if (Date.now() - this.cardActionAtMs < 250) {
      ScreenSaverLogger.info('screen tap skipped: card action just handled');
      return;
    }
    if (this.capsuleVisible) {
      this.hideCapsuleWithFade();
    } else {
      this.showCapsule();
    }
  }

  /**
   * 屏保展示态的卡片点击——**变更项 2 / 3 的唯一拦截点**。
   *
   * 屏保态与编辑态的差异全部集中在这里，不在各卡片里分别特判：
   *   · 视频卡   → 切换播放/停止（变更项 3）
   *   · 跳转卡   → 发起跳转（变更项 2）
   *   · 其它卡片 → 保持原语义：唤出「退出屏保」胶囊
   * 退出方式不变：点空白处唤胶囊、返回键退出（点可交互卡片不再唤胶囊）。
   */
  private handlePlayModeCardTap(card: ScreensaverCardInstance): void {
    if (card.cardType === 'video') {
      this.cardActionAtMs = Date.now();
      this.toggleVideoPlayback(card);
      return;
    }
    if (card.cardType === 'entry') {
      this.cardActionAtMs = Date.now();
      this.jumpFromEntryCard(card);
      return;
    }
    if (card.cardType === 'quotes') {
      // §3.2 白名单例外：仅行情卡允许屏保态点击刷新，不得推广到其它卡片。
      this.handleQuotesCardTap(card);
      return;
    }
    if (card.cardType === 'todo') {
      // 待办卡：只有行首圆可点（圆自身 stopPropagation）。
      // 卡片其他位置 / 行文字 / 空白一律无动作；吃掉这次点击，避免顺带唤出退出胶囊。
      this.cardActionAtMs = Date.now();
      ScreenSaverLogger.info('todo card tap ignored: only check circle is interactive');
      return;
    }
    // 其它卡片没有卡片级动作：走原来的「唤胶囊」路径
    ScreenSaverLogger.info(`play-mode card tap: pass through ${card.cardType}`);
    this.handleScreenTap();
  }

  /**
   * 屏保态点视频卡：切换播放/停止。
   * 未选视频 / 视频不可用时给出明确提示（否则用户会以为「点了没反应」）。
   */
  private toggleVideoPlayback(card: ScreensaverCardInstance): void {
    if (card.video.uri.length === 0) {
      this.toast('未选择视频：请在编辑模式里配置');
      return;
    }
    if (!screenSaverVideoThumb.probeReadable(card.video.uri)) {
      this.toast('视频不可用：请在编辑模式里重新选择');
      return;
    }
    card.video.playing = !card.video.playing;
    screenSaverAppModel.save();
    ScreenSaverLogger.info(`video toggle by tap: playing=${card.video.playing}`);
  }

  /**
   * 屏保态点跳转卡：整卡即热区，按卡片配置的目标类型发起跳转。
   *
   * - url：按用户填写的链接打开（历史行为不变）；
   * - thirdparty / system：目标失效时保留配置并持久化失效态，提示重新选择；
   * - 拉起重试成功后自动清除失效标记。
   */
  private jumpFromEntryCard(card: ScreensaverCardInstance): void {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext | undefined;
    if (context === undefined) {
      ScreenSaverLogger.warn('play-mode entry tap: no ability context');
      this.toast('无法获取应用上下文，跳转未发起');
      return;
    }
    if (card.entry.targetType === 'url') {
      const link = card.entry.link.trim();
      if (link.length === 0) {
        ScreenSaverLogger.info('play-mode entry tap: link not configured');
        this.toast('未配置跳转链接');
        return;
      }
      ScreenSaverLogger.info(`play-mode entry tap: url ${link}`);
    } else {
      if (card.entry.presetId.length === 0) {
        ScreenSaverLogger.info('play-mode entry tap: preset not selected');
        this.toast('未选择目标应用：请在编辑模式设置里选择');
        return;
      }
      ScreenSaverLogger.info(`play-mode entry tap: ${card.entry.targetType} ${card.entry.presetId}`);
    }
    screenSaverOpenEntry(context, card.entry).then((result: ScreenSaverLinkResult): void => {
      if (result.ok) {
        if (card.entry.targetType !== 'url' &&
          (card.entry.invalid || card.entry.failureCount > 0 || card.entry.lastFailureAt > 0)) {
          card.entry.invalid = false;
          card.entry.lastFailureAt = 0;
          card.entry.failureCount = 0;
          screenSaverAppModel.save();
        }
        return;
      }
      if (card.entry.targetType !== 'url') {
        card.entry.invalid = true;
        card.entry.lastFailureAt = Date.now();
        card.entry.failureCount = Math.min(card.entry.failureCount + 1, 9999);
        screenSaverAppModel.save();
      }
      ScreenSaverLogger.warn(`play-mode entry open failed: ${result.reason}`);
      this.toast(result.reason.length > 0 ? result.reason : '跳转失败');
    });
  }

  /**
   * 屏保态点行情卡（§3.2 唯一白名单例外）：
   *   · 长按 600ms 进入编辑/设置的补发 click：忽略；
   *   · 1s 内多次点击同一张卡：合并为一次，只发一次请求；
   *   · 实际刷新与成功/失败反馈由卡片自身的独立刷新通道完成。
   */
  private handleQuotesCardTap(card: ScreensaverCardInstance): void {
    // 无论是否真正发起请求，都吃掉这次点击，避免同时唤出退出胶囊。
    this.cardActionAtMs = Date.now();
    if (Date.now() - this.longPressAtMs < 600) {
      ScreenSaverLogger.info('quotes tap skipped: long press gesture');
      return;
    }
    const now = Date.now();
    const last = this.quotesTapAt.get(card.id);
    if (last !== undefined && now - last < 1000) {
      ScreenSaverLogger.info(`quotes tap merged: ${card.id}`);
      return;
    }
    this.quotesTapAt.set(card.id, now);
    ScreenSaverLogger.info(`quotes tap refresh: ${card.id}`);
    screenSaverRequestQuotesRefreshFor(card.id);
  }

  /**
   * 退出屏保：淡出动画 → navStack.pop() 返回主页。
   */
  private exitScreensaver(): void {
    const duration = screenSaverMotionDuration(SCREEN_SAVER_MOTION_EXIT_MS);
    ScreenSaverLogger.info('exit screensaver');
    this.hideCapsule();
    if (duration <= 0) {
      // 减弱动效：直接关
      this.displayOpacity = 0;
      this.navStack.pop();
      return;
    }
    this.getUIContext().animateTo({
      duration: duration,
      curve: Curve.EaseInOut,
      onFinish: (): void => {
        this.navStack.pop();
      }
    }, (): void => {
      this.displayOpacity = 0;
    });
  }

  /** 编辑态选中一张卡片。 */
  private selectCard(cardId: string): void {
    this.selectedCardId = cardId;
  }

  /**
   * 打开某张卡片的设置面板（唯一入口）。
   *
   * cardId 是「面板归属哪张卡片」的唯一依据：选中态、面板卡片 id、面板类型
   * 全部由它派生。这样就不会再出现「先改选中态、再按选中态反查卡片」导致
   * 操作落到别的卡片上的问题（缺陷 1 的根因形态）。
   */
  private openSheetForCard(cardId: string, kind: SheetKind): void {
    ScreenSaverLogger.info(`open sheet kind=${kind} cardId=${cardId}`);
    this.selectedCardId = cardId;
    this.sheetCardId = cardId;
    this.sheetKind = kind;
    this.sheetVisible = true;
  }

  /**
   * 对「当前选中」卡片打开其类型的设置面板（底栏「卡片设置」按钮入口）。
   * 未选中时给出提示而不是静默无反应。
   */
  private openSettingsForSelected(): void {
    const card = screenSaverAppModel.cardById(this.selectedCardId);
    if (card === undefined) {
      this.toast('请先选择一张卡片');
      return;
    }
    this.openSheetForCard(card.id, card.cardType);
  }

  /** 关闭设置面板。 */
  private closeSheet(): void {
    this.sheetVisible = false;
    this.sheetKind = 'none';
  }

  /**
   * 面板彻底消失后清空面板归属卡片（在 onDisappear 里调用，
   * 避免关闭动画期间把 sheetKind/sheetCardId 清掉导致内容闪空）。
   */
  private clearSheetTarget(): void {
    this.closeSheet();
    this.sheetCardId = '';
  }

  /**
   * 移除「设置面板归属」的那张卡片（面板里的删除入口）。
   * 用 sheetCardId 而不是 selectedCardId：删除必须落在面板正在编辑的卡片上。
   */
  private removeSheetCard(): void {
    const cardId = this.sheetCardId;
    if (cardId.length === 0) {
      return;
    }
    if (this.selectedCardId === cardId) {
      this.selectedCardId = '';
    }
    screenSaverAppModel.removeCard(cardId);
  }

  /**
   * 编辑态点 × 删除卡片：弹系统确认对话框（危险操作二次确认）。
   */
  private confirmRemoveCard(cardId: string): void {
    this.getUIContext().showAlertDialog({
      title: '移除卡片',
      message: '确定要移除这张卡片吗？',
      primaryButton: {
        value: '取消',
        action: (): void => {}
      },
      secondaryButton: {
        value: '移除',
        fontColor: SCREEN_SAVER_COLORS.danger,
        action: (): void => {
          if (this.selectedCardId === cardId) {
            this.selectedCardId = '';
          }
          screenSaverAppModel.removeCard(cardId);
        }
      }
    });
  }

  // ==================== 拖动（移动卡片）====================

  /**
   * 开始拖动：记录卡片 id，清零位移，顺带选中它。
   * 只会在「手指位移超过阈值」之后被调用（见 onCellTouch），
   * 因此「选中」语义属于拖动，而不是按下。
   */
  private beginDrag(cardId: string): void {
    ScreenSaverLogger.info(`begin drag ${cardId}`);
    this.dragCardId = cardId;
    this.pendingTouchCardId = '';
    this.dragOffsetX = 0;
    this.dragOffsetY = 0;
    this.dragInvalid = false;
    this.selectCard(cardId);
  }

  /**
   * 拖动中：更新位移；并把目标格合法性实时算出来
   * （非法时卡片描红边，用户在松手前就知道放不下）。
   */
  private updateDrag(cardId: string, offsetX: number, offsetY: number): void {
    if (this.dragCardId !== cardId) {
      return;
    }
    this.dragOffsetX = offsetX;
    this.dragOffsetY = offsetY;
    const card = screenSaverAppModel.cardById(cardId);
    if (card === undefined || this.gridW <= 0) {
      return;
    }
    const target = this.targetSlot(card, offsetX, offsetY);
    this.dragInvalid = !screenSaverAppModel.canPlace(cardId, target.colStart, target.rowStart, card.colSpan,
      card.rowSpan);
  }

  /**
   * 把手指位移（vp）换算成目标格子坐标：
   * 位移 ÷ 单元格尺寸 = 格子增量（四舍五入到最近的格），再 clamp 到网格边界内。
   * 换算统一走 common/GridLayout（变更项 1：编辑态与屏保态共用同一套坐标基准）。
   */
  private targetSlot(card: ScreensaverCardInstance, offsetX: number, offsetY: number): ScreensaverGridPos {
    const delta = screenSaverCellDelta(offsetX, offsetY, this.gridMetrics());
    let colStart = card.colStart + delta.colSpan;
    let rowStart = card.rowStart + delta.rowSpan;
    colStart = Math.max(0, Math.min(colStart, this.gridColumns() - card.colSpan));
    rowStart = Math.max(0, Math.min(rowStart, this.gridRows() - card.rowSpan));
    const pos: ScreensaverGridPos = {
      colStart: colStart,
      rowStart: rowStart,
      colSpan: card.colSpan,
      rowSpan: card.rowSpan
    };
    return pos;
  }

  /**
   * 松手提交拖动：
   * - 非法 → 弹回原位（回弹动画）+ toast；
   * - 位移不足一格 → 吸附回原位（快速归零动画）；
   * - 合法 → moveCard 真正改坐标（模型校验失败同样回弹）。
   */
  private commitDrag(cardId: string): void {
    const offsetX = this.dragOffsetX;
    const offsetY = this.dragOffsetY;
    const invalid = this.dragInvalid;
    ScreenSaverLogger.info(`commit drag ${cardId} offset=${offsetX},${offsetY} invalid=${invalid}`);
    this.dragCardId = '';
    this.dragInvalid = false;
    // 记下拖动结束时刻：拖动松手后系统可能再补一个 click，
    // 用时间窗把它挡掉，避免「拖完卡片顺手把设置面板打开」。
    this.gestureCommitAtMs = Date.now();
    const card = screenSaverAppModel.cardById(cardId);
    if (card === undefined || this.gridW <= 0) {
      this.resetDragOffsets();
      return;
    }
    if (invalid) {
      this.animateOffsetsToZero(screenSaverBounceDuration());
      this.toast('该位置已被占用，松手回弹');
      return;
    }
    const target = this.targetSlot(card, offsetX, offsetY);
    const deltaCol = target.colStart - card.colStart;
    const deltaRow = target.rowStart - card.rowStart;
    if (deltaCol === 0 && deltaRow === 0) {
      // 没挪出格子：吸附动画归位即可
      this.animateOffsetsToZero(screenSaverSnapDuration());
      return;
    }
    const moved = screenSaverAppModel.moveCard(cardId, deltaCol, deltaRow);
    if (!moved) {
      this.animateOffsetsToZero(screenSaverBounceDuration());
      this.toast('该位置已被占用，松手回弹');
      return;
    }
    this.resetDragOffsets();
  }

  /**
   * 把拖动位移动画归零（回弹/吸附的视觉过渡）。
   * 注意：moveCard 成功时直接 reset（新格子坐标立即生效，不做归零动画）。
   */
  private animateOffsetsToZero(duration: number): void {
    if (duration <= 0) {
      this.resetDragOffsets();
      return;
    }
    this.getUIContext().animateTo({
      duration: duration,
      curve: Curve.EaseOut,
      onFinish: (): void => {
        this.resetDragOffsets();
      }
    }, (): void => {
      this.dragOffsetX = 0;
      this.dragOffsetY = 0;
    });
  }

  /** 直接清零拖动位移。 */
  private resetDragOffsets(): void {
    this.dragOffsetX = 0;
    this.dragOffsetY = 0;
  }

  /**
   * 编辑态与屏保态的**统一网格度量**（变更项 1 的坐标基准）：
   * 单元格尺寸 = 画布宽高 / 4×8 网格。拖动、缩放、悬浮、背景全都用它，
   * 不再有「某个状态用另一套偏移」的情况。
   */
  private gridMetrics(): ScreenSaverGridMetrics {
    return screenSaverGridMetrics(this.gridW, this.gridH, this.gridColumns(), this.gridRows());
  }

  // ==================== 拉伸（改尺寸）====================

  /** 开始拉伸：记录「拖动前的矩形」作为回滚点，顺带选中它。 */
  private beginResize(cardId: string): void {
    ScreenSaverLogger.info(`begin resize ${cardId}`);
    const card = screenSaverAppModel.cardById(cardId);
    if (card === undefined) {
      return;
    }
    this.resizeCardId = cardId;
    this.resizeOffsetX = 0;
    this.resizeOffsetY = 0;
    this.resizeSnapped = false;
    this.resizeInvalid = false;
    this.resizeOriginColStart = card.colStart;
    this.resizeOriginRowStart = card.rowStart;
    this.resizeOriginColSpan = card.colSpan;
    this.resizeOriginRowSpan = card.rowSpan;
    this.selectCard(cardId);
    this.resizeLabel = `${card.colSpan}×${card.rowSpan}`;
  }

  /**
   * 拉伸中：把「请求跨度」经尺寸矩阵吸附后**直接写到卡片上**（不落盘）。
   * 卡片跨度是 @Trace 字段，写进去之后格子尺寸与卡片内容排版都会实时变化，
   * 这就是「拖拽缩放实时预览」的实现方式。
   */
  private updateResize(cardId: string, offsetX: number, offsetY: number): void {
    if (this.resizeCardId !== cardId) {
      return;
    }
    this.resizeOffsetX = offsetX;
    this.resizeOffsetY = offsetY;
    const card = screenSaverAppModel.cardById(cardId);
    const target = this.targetSpanFor(cardId, offsetX, offsetY);
    if (card === undefined || target === undefined) {
      return;
    }
    const wanted = this.wantedSpan(offsetX, offsetY);
    this.resizeSnapped = target.colSpan !== wanted.colSpan || target.rowSpan !== wanted.rowSpan;
    this.resizeInvalid = !screenSaverAppModel.previewCardRect(cardId, target.colStart, target.rowStart,
      target.colSpan, target.rowSpan);
    this.resizeLabel = this.resizeSnapped ?
      `${wanted.colSpan}×${wanted.rowSpan} → ${target.colSpan}×${target.rowSpan} 已吸附` :
      `${target.colSpan}×${target.rowSpan}`;
  }

  /**
   * 手指位移换算出的「用户想要的跨度」（未吸附）。
   * 基准是**拖动前的跨度**（resizeOrigin*），不是卡片当前的跨度：
   * 预览会实时改写卡片跨度，若以当前值为基准，每一次 Move 都会在上一次
   * 结果上再叠加一次位移，尺寸会失控放大。
   * 换算统一走 common/GridLayout（与拖动共用同一套「位移 → 格子」逻辑）。
   */
  private wantedSpan(offsetX: number, offsetY: number): ScreenSaverSpan {
    return screenSaverSpanFromOffset(this.resizeOriginColSpan, this.resizeOriginRowSpan, offsetX, offsetY,
      this.gridMetrics());
  }

  /**
   * 把拉伸位移换算成「吸附后的目标跨度」（预览与提交共用同一套计算，
   * 保证「预览看到的尺寸 = 松手落到数据里的尺寸」）：
   *   1. 位移 ÷ 单元格尺寸 → 期望跨度（相对拖动前的矩形）；
   *   2. screenSaverSnapCardSize 吸附到最近的合法尺寸（尺寸矩阵，见 CardCatalog）；
   *   3. 越界处理：起点往回拉，保证整张卡仍在网格内。
   */
  private targetSpanFor(cardId: string, offsetX: number, offsetY: number): ScreensaverGridPos | undefined {
    const card = screenSaverAppModel.cardById(cardId);
    if (card === undefined || this.gridW <= 0) {
      return undefined;
    }
    const wanted = this.wantedSpan(offsetX, offsetY);
    const entry = screenSaverSnapCardSize(card.cardType, wanted.colSpan, wanted.rowSpan,
      Math.min(4, this.gridColumns()), Math.min(6, this.gridRows()));
    const colStart = Math.max(0, Math.min(this.resizeOriginColStart, this.gridColumns() - entry.colSpan));
    const rowStart = Math.max(0, Math.min(this.resizeOriginRowStart, this.gridRows() - entry.rowSpan));
    const pos: ScreensaverGridPos = {
      colStart: colStart,
      rowStart: rowStart,
      colSpan: entry.colSpan,
      rowSpan: entry.rowSpan
    };
    return pos;
  }

  /**
   * 松手提交拉伸：
   * - 预览非法（与其它卡片重叠/越界）→ 回滚到拖动前的矩形 + toast；
   * - 尺寸没变（含被吸附回原尺寸的情况）→ 只复位预览，必要时提示吸附结果；
   * - 尺寸变了且合法 → 保留预览结果并落盘，发生过吸附时明确提示。
   */
  private commitResize(cardId: string): void {
    const offsetX = this.resizeOffsetX;
    const offsetY = this.resizeOffsetY;
    const snapped = this.resizeSnapped;
    const invalid = this.resizeInvalid;
    const originColStart = this.resizeOriginColStart;
    const originRowStart = this.resizeOriginRowStart;
    const originColSpan = this.resizeOriginColSpan;
    const originRowSpan = this.resizeOriginRowSpan;
    this.resizeCardId = '';
    this.resizeOffsetX = 0;
    this.resizeOffsetY = 0;
    this.resizeLabel = '';
    this.resizeSnapped = false;
    this.resizeInvalid = false;
    // 与拖动共用同一个「手势刚结束」时间戳：防止缩放松手后补发的 click 把设置面板点开
    this.gestureCommitAtMs = Date.now();
    const target = this.targetSpanFor(cardId, offsetX, offsetY);
    if (target === undefined) {
      ScreenSaverLogger.info('resize commit: no target');
      return;
    }
    // 关键诊断日志（变更项 3 的回归证据）：把位移、期望跨度、吸附结果一起记下来，
    // 这样「手势是否到达缩放逻辑 / 位移是否被错误换算」都能从日志直接判读。
    const wanted = this.wantedSpan(offsetX, offsetY);
    ScreenSaverLogger.info(`resize commit: ${cardId} offset=${Math.round(offsetX)},${Math.round(offsetY)} ` +
      `wanted=${wanted.colSpan}x${wanted.rowSpan} target=${target.colSpan}x${target.rowSpan} snapped=${snapped} ` +
      `invalid=${invalid}`);
    if (invalid) {
      screenSaverAppModel.endCardRectPreview(cardId, originColStart, originRowStart, originColSpan, originRowSpan,
        false);
      ScreenSaverLogger.info(`resize commit: rollback ${cardId}`);
      this.toast('尺寸不可用：与其它卡片重叠或越界，已恢复原尺寸');
      return;
    }
    const unchanged = target.colSpan === originColSpan && target.rowSpan === originRowSpan;
    screenSaverAppModel.endCardRectPreview(cardId, originColStart, originRowStart, originColSpan, originRowSpan, true);
    ScreenSaverLogger.info(`resize commit: ${cardId} -> ${target.colSpan}x${target.rowSpan} snapped=${snapped}`);
    if (unchanged) {
      if (snapped) {
        this.toast(`已吸附到 ${target.colSpan}×${target.rowSpan}（与当前尺寸一致）`);
      }
      return;
    }
    if (snapped) {
      this.toast(`已吸附到 ${target.colSpan}×${target.rowSpan}`);
    }
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

  // ==================== 触摸事件分发 ====================

  /**
   * 卡片本体触摸（编辑态的「点击 / 拖动」区分，缺陷 1 修复的核心）。
   *
   * 关键规则：**按下（Down）阶段绝不修改选中态**。
   * 旧实现里 Down 直接 beginDrag → selectCard，导致后续 onClick 里
   * `card.id === selectedCardId` 恒成立，单击任意卡片都会直接打开
   * 「被点那张卡片」的设置面板，而「仅选中」分支成为死代码。
   *
   * 现在：Down 只登记候选卡片与起点；Move 首次超过阈值才进入拖动并选中；
   * Up/Cancel 未超阈值时什么都不做——点击语义完全交给 onClick。
   */
  private onCellTouch(card: ScreensaverCardInstance, event: TouchEvent): void {
    if (!this.editMode) {
      return;
    }
    // 悬浮卡走独立的拖动逻辑（自由移动、无网格吸附与碰撞校验）
    if (card.floating) {
      this.onFloatTouch(card, event);
      return;
    }
    const touch = event.touches[0];
    if (touch === undefined) {
      return;
    }
    // vp 坐标直接用（TouchObject.windowX/windowY 官方单位 = vp，见触摸事件文档）；
    // 旧实现多做了 px2vp，把位移压缩了约 1/屏幕密度，导致「拖了却几乎不动」。
    const x = touch.windowX;
    const y = touch.windowY;
    if (event.type === TouchType.Down) {
      this.pendingTouchCardId = card.id;
      this.touchStartX = x;
      this.touchStartY = y;
      return;
    }
    if (event.type === TouchType.Move) {
      const offsetX = x - this.touchStartX;
      const offsetY = y - this.touchStartY;
      // 还没进入拖动：位移超过阈值才算「拖动意图」，此时才选中该卡片
      if (this.pendingTouchCardId === card.id && this.dragCardId.length === 0 &&
        (Math.abs(offsetX) > SCREEN_SAVER_METRICS.snapThresholdVp ||
          Math.abs(offsetY) > SCREEN_SAVER_METRICS.snapThresholdVp)) {
        this.beginDrag(card.id);
      }
      if (this.dragCardId === card.id) {
        this.updateDrag(card.id, offsetX, offsetY);
      }
      return;
    }
    if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      if (this.dragCardId === card.id) {
        // 松手时以 Up 自身的坐标为准再更新一次位移：
        // 部分设备/注入工具只在 Move 里给出部分位移，最后一个位置在 Up 事件里，
        // 不补这一次就会出现「拖了一格却原地不动」。
        if (event.type === TouchType.Up) {
          this.updateDrag(card.id, x - this.touchStartX, y - this.touchStartY);
        }
        this.commitDrag(card.id);
      }
      this.pendingTouchCardId = '';
    }
  }

  /**
   * 右下角拉伸手柄触摸（编辑态的改尺寸）。
   * stopPropagation：手柄事件不冒泡给卡片的拖动逻辑。
   * 流程与 onCellTouch 对称：Down 起手 → Move 预览 → Up 提交。
   */
  private onHandleTouch(card: ScreensaverCardInstance, event: TouchEvent): void {
    if (!this.editMode) {
      return;
    }
    event.stopPropagation();
    const touch = event.touches[0];
    if (touch === undefined) {
      return;
    }
    // 单位同 onCellTouch：windowX/windowY 已是 vp，直接使用（变更项 3 的根因修复）。
    const x = touch.windowX;
    const y = touch.windowY;
    if (event.type === TouchType.Down) {
      this.resizeTouchStartX = x;
      this.resizeTouchStartY = y;
      this.beginResize(card.id);
    } else if (event.type === TouchType.Move) {
      if (this.resizeCardId === card.id) {
        this.updateResize(card.id, x - this.resizeTouchStartX, y - this.resizeTouchStartY);
      }
    } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      if (this.resizeCardId === card.id) {
        // 松手以 Up 坐标为准（理由同 onCellTouch：最后一段位移可能在 Up 事件里）
        if (event.type === TouchType.Up) {
          this.updateResize(card.id, x - this.resizeTouchStartX, y - this.resizeTouchStartY);
        }
        this.commitResize(card.id);
      }
    }
  }

  // ==================== UI 构建 ====================

  /**
   * 空态：一张卡片都没有时，显示兜底时钟 + 操作引导。
   * 兜底时钟同样享受防烧屏位移。
   */
  @Builder
  emptyState() {
    Column({ space: 10 }) {
      Column() {
        ScreensaverClockCard({
          card: this.fallbackCard,
          cardMode: 'play',
          cardTone: this.inkTone,
          cardHalo: this.inkHalo
        })
      }
      .width('100%')
      .height(158)
      .translate({
        x: this.burnInX(this.fallbackCard),
        y: this.burnInY(this.fallbackCard)
      })
      Text('长按进入编辑模式 · 进「屏保设置」添加卡片')
        .fontSize(12)
        .fontColor(SCREEN_SAVER_COLORS.textSecondary)
        .padding({ left: 14, right: 14, top: 7, bottom: 7 })
        .borderRadius(14)
        .backgroundColor(SCREEN_SAVER_COLORS.canvasChipBg)
    }
    .width('100%')
    .height('100%')
    .padding({ left: 16, right: 16 })
    .justifyContent(FlexAlign.Center)
    .onClick((): void => {
      this.handleScreenTap();
    })
  }

  /**
   * 编辑态网格线覆盖层：4×8 半透明描边格子。
   * hitTestBehavior(None)：纯装饰，不拦截任何触摸。
   * 与卡片层共用同一个垂直偏移（gridOffsetY），保证网格线和卡片永远对齐。
   */
  /** 编辑网格线的行下标（竖屏 8 行 / 横屏 4 行）。 */
  private gridRowIndexes(): number[] {
    const result: number[] = [];
    for (let index = 0; index < this.gridRows(); index++) {
      result.push(index);
    }
    return result;
  }

  /** 编辑网格线的列下标（竖屏 4 列 / 横屏 8 列）。 */
  private gridColumnIndexes(): number[] {
    const result: number[] = [];
    for (let index = 0; index < this.gridColumns(); index++) {
      result.push(index);
    }
    return result;
  }

  @Builder
  gridOverlay() {
    Column() {
      ForEach(this.gridRowIndexes(), (rowIndex: number) => {
        Row() {
          ForEach(this.gridColumnIndexes(), (colIndex: number) => {
            Column()
              .width('100%')
              .height('100%')
              .border({ width: 0.5, color: '#24FFFFFF' })
              .layoutWeight(1)
              .hitTestBehavior(HitTestMode.None)
          }, (colIndex: number): string => `grid_c_${rowIndex}_${colIndex}`)
        }
        .width('100%')
        .layoutWeight(1)
        .hitTestBehavior(HitTestMode.None)
      }, (rowIndex: number): string => `grid_r_${rowIndex}`)
    }
    .width('100%')
    .height('100%')
    // 与卡片内容层使用同一安全区内边距，保证横屏网格线与卡片严格对齐。
    .padding({
      left: this.safeInsets.left,
      right: this.safeInsets.right,
      top: this.safeInsets.top,
      bottom: this.safeInsets.bottom
    })
    .opacity(0.6)
    .translate({ y: this.gridOffsetY() })
    .hitTestBehavior(HitTestMode.None)
  }

  /**
   * 编辑态顶栏：取消（回滚快照）/ 标题 / 完成（保留改动）。
   * hitTestBehavior(None) 让空白区域把触摸透传给下面的网格。
   */
  @Builder
  editTopBar() {
    Row() {
      Text('取消')
        .fontSize(15)
        .fontColor('#CCCCCC')
        .padding({ left: 16, right: 12, top: 12, bottom: 12 })
        .onClick((): void => {
          this.exitEditMode(true);
        })
      Blank()
      Text('编辑布局')
        .fontSize(15)
        .fontColor(SCREEN_SAVER_COLORS.textPrimary)
      Blank()
      Text('完成')
        .fontSize(15)
        .fontColor(SCREEN_SAVER_COLORS.accent)
        .padding({ left: 12, right: 16, top: 12, bottom: 12 })
        .onClick((): void => {
          this.exitEditMode(false);
        })
    }
    .width('100%')
    .padding({ top: 8 })
    .hitTestBehavior(HitTestMode.None)
  }

  /**
   * 编辑态底栏：「屏保设置」+「卡片设置」（作用于当前选中卡片）。
   * 添加卡片统一收口到「屏保设置」页，编辑页底栏不再重复提供入口。
   *
   * 「卡片设置」是缺陷 1 验收路径上的显式入口：面板内容始终来自
   * selectedCardId 对应的那张卡片，不依赖「卡片被点开」这一隐式动作。
   */
  @Builder
  editBottomBar() {
    Row({ space: 8 }) {
      // 方向设置页入口：卡片开关、内容设置、添加/删除都在那里统一管理。
      Column() {
        Text('屏保设置')
          .fontSize(13)
          .fontColor(SCREEN_SAVER_COLORS.white)
          .padding({ left: 18, right: 18, top: 7, bottom: 7 })
          .borderRadius(16)
          .backgroundColor(SCREEN_SAVER_COLORS.accentStrong)
      }
      .constraintSize({ minHeight: 40 })
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .onClick((): void => {
        this.openModeSettings();
      })
      // 选中态决定可用性：没选中时置灰并提示，而不是静默无反应
      Column() {
        Text('卡片设置')
          .fontSize(13)
          .fontColor(this.selectedCardId.length > 0 ? SCREEN_SAVER_COLORS.white : '#6E6E73')
          .padding({ left: 18, right: 18, top: 7, bottom: 7 })
          .borderRadius(16)
          .backgroundColor(this.selectedCardId.length > 0 ?
          SCREEN_SAVER_COLORS.accentStrong : SCREEN_SAVER_COLORS.divider)
      }
      .constraintSize({ minHeight: 40 })
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .opacity(this.selectedCardId.length > 0 ? 1 : 0.6)
      .onClick((): void => {
        this.openSettingsForSelected();
      })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 10, bottom: 16 })
    .hitTestBehavior(HitTestMode.None)
  }

  /**
   * 设置面板内容：按 sheetKind 挂载对应面板组件。
   * 每个面板都传 card（面板直接改 card 字段 + save）和两个回调。
   */
  @Builder
  sheetContent() {
    Column() {
      if (this.sheetKind === 'clock') {
        ScreenSaverClockSettingsPanel({
          card: this.sheetCard(),
          onDone: (): void => {
            this.closeSheet();
          },
          onDelete: (): void => {
            this.removeSheetCard();
            this.closeSheet();
          }
        })
      } else if (this.sheetKind === 'photo') {
        ScreenSaverPhotoSettingsPanel({
          card: this.sheetCard(),
          onDone: (): void => {
            this.closeSheet();
          },
          onDelete: (): void => {
            this.removeSheetCard();
            this.closeSheet();
          }
        })
      } else if (this.sheetKind === 'video') {
        ScreenSaverVideoSettingsPanel({
          card: this.sheetCard(),
          onDone: (): void => {
            this.closeSheet();
          },
          onDelete: (): void => {
            this.removeSheetCard();
            this.closeSheet();
          }
        })
      } else if (this.sheetKind === 'git') {
        ScreenSaverGitSettingsPanel({
          card: this.sheetCard(),
          onDone: (): void => {
            this.closeSheet();
          },
          onDelete: (): void => {
            this.removeSheetCard();
            this.closeSheet();
          }
        })
      } else if (this.sheetKind === 'weather') {
        ScreenSaverWeatherSettingsPanel({
          card: this.sheetCard(),
          onDone: (): void => {
            this.closeSheet();
          },
          onDelete: (): void => {
            this.removeSheetCard();
            this.closeSheet();
          }
        })
      } else if (this.sheetKind === 'entry') {
        ScreenSaverEntrySettingsPanel({
          card: this.sheetCard(),
          onDone: (): void => {
            this.closeSheet();
          },
          onDelete: (): void => {
            this.removeSheetCard();
            this.closeSheet();
          }
        })
      } else if (this.sheetKind === 'quotes') {
        ScreenSaverQuotesSettingsPanel({
          card: this.sheetCard(),
          onDone: (): void => {
            this.closeSheet();
          },
          onDelete: (): void => {
            this.removeSheetCard();
            this.closeSheet();
          }
        })
      } else if (this.sheetKind === 'countdown') {
        ScreenSaverCountdownSettingsPanel({
          card: this.sheetCard(),
          onDone: (): void => {
            this.closeSheet();
          },
          onDelete: (): void => {
            this.removeSheetCard();
            this.closeSheet();
          }
        })
      } else if (this.sheetKind === 'todo') {
        ScreenSaverTodoSettingsPanel({
          card: this.sheetCard(),
          onDone: (): void => {
            this.closeSheet();
          },
          onDelete: (): void => {
            this.removeSheetCard();
            this.closeSheet();
          }
        })
      }
    }
    .width('100%')
    .height('100%')
  }

  /** 取设置面板对应的卡片实例（找不到给个空实例兜底）。 */
  private sheetCard(): ScreensaverCardInstance {
    const card = screenSaverAppModel.cardById(this.sheetCardId);
    return card !== undefined ? card : new ScreensaverCardInstance();
  }

  /**
   * 单张卡片单元格（Stack 多层叠加）：
   *   底层：停用占位（虚线框 + 类型名）或真正的卡片组件 CardHost；
   *   编辑层：选中描边 + × 删除角标、非法拖动红边、拉伸尺寸标签；
   *   手柄层：右下角拉伸手柄（40vp 热区，28vp 可见圆点）。
   * 外层容器负责：圆角裁剪、编辑态缩放 0.96、拖动 offset/zIndex、
   * 防烧屏 translate、点击/长按/触摸手势。
   */
  /**
   * 该卡片单元格的**圆角裁剪策略**（变更项 1/2 的逐类说明）。
   *
   * 变更项 1 已确认：所有卡片的「卡面底色块 + 1vp 描边」统一移除（全透明），
   * 原先由卡面/描边承担的「圆角裁剪」按下表处理：
   *   · 相册卡：容器不裁剪圆角（0）——内容由渲染层按真实比例放进
   *     「紧贴内容」的圆角容器（圆角 = cardRadius 10vp），
   *     未铺满时圆角落在画面四角，铺满时与卡片圆角一致（已确认方案）；
   *   · 视频卡：容器同样不裁剪（0），封面帧/播放画面走与相册一致的圆角容器；
   *   · 其余卡（时钟/天气/入口/Git）：保留 cardRadius 圆角裁剪作为溢出保护，
   *     无背景色后该裁剪在静止态不可见（文字与图形都在内边距以内）。
   * 另外所有卡片都保留 `.clip(true)`：即使圆形裁剪为 0，
   * 内容仍被限制在卡片边界内，不会因去边框而溢出。
   */
  /** 播放态是否显示卡片细边框（全局设置，默认关闭 = 透明边框）。 */
  private showCardBorder(): boolean {
    return !this.editMode && screenSaverAppModel.layout.settings.showCardBorder;
  }

  private cardClipRadius(card: ScreensaverCardInstance): number {
    // 视频卡与其他卡片使用同一个圆角设置；相册仍按内容自身定形。
    if (card.cardType === 'photo') {
      return 0;
    }
    return SCREEN_SAVER_METRICS.cardRadius;
  }

  /** 当前墨色档的调色板（停用占位等页面级卡片文字与卡片内部同一来源）。 */
  private inkPalette(): ScreensaverCardPalette {
    return screenSaverCardPalette(this.inkTone);
  }

  @Builder
  cardCell(card: ScreensaverCardInstance, index: number, allowHandle: boolean) {
    Stack() {
      // ---------- 底层：停用占位 或 真卡片 ----------
      if (!card.enabled) {
        Column({ space: 4 }) {
          Text(screenSaverCardTypeName(card.cardType))
            .fontSize(13)
            .fontColor(this.inkPalette().textSecondary)
          Text('已停用')
            .fontSize(11)
            .fontColor(this.inkPalette().textTertiary)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        // 虚线框只在编辑态显示（编辑辅助元素；屏保展示态保持纯净无框线）。
        .border({
          width: this.editMode ? 1 : 0,
          color: '#33FFFFFF',
          radius: SCREEN_SAVER_METRICS.cardRadius,
          style: BorderStyle.Dashed
        })
      } else {
        ScreensaverCardHost({
          card: card,
          cardMode: this.editMode ? 'edit' : 'play',
          cardActive: this.pageActive && !this.editMode,
          cardTone: this.inkTone,
          cardHalo: this.inkHalo,
          showOverflowHint: this.editMode,
          onRequestConfig: (): void => {
            // 编辑态：卡片内按钮（视频重选 / Git 重试）打开该卡内容面板；
            // 播放态：统一进入当前方向设置页配置内容。
            if (this.editMode) {
              this.openSheetForCard(card.id, card.cardType);
            } else {
              this.openModeSettings();
            }
          }
        })
      }
      // ---------- 编辑层 ----------
      if (this.editMode) {
        // 选中态：白色描边 + 右上角 × 删除角标（28vp 圆钮，40vp 热区）
        if (card.id === this.selectedCardId) {
          Column()
            .width('100%')
            .height('100%')
            .border({ width: 2, color: SCREEN_SAVER_COLORS.accent, radius: SCREEN_SAVER_METRICS.cardRadius })
          // 角标定位：Stack 子节点上的 .align() 在本 SDK 实测不生效（元素会被居中），
          // 且用「满尺寸容器 + HitTestMode.None」包一层会把子节点也挡掉触摸；
          // 因此改用绝对定位：position 把左上角放到父容器右上角，markAnchor 再按自身
          // 尺寸回移，等效于「钉在右上角」，同时不额外引入一层容器。
          Column() {
            Column() {
              Text('×')
                .fontSize(16)
                .fontColor('#F2F2F2')
                .fontWeight(FontWeight.Medium)
            }
            .width(28)
            .height(28)
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
            .borderRadius(14)
            .backgroundColor('#000000')
          }
          .width(40)
          .height(40)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          // 角标位置：普通（网格）卡片在右上角；悬浮卡在右下角——悬浮卡没有
          // 缩放手柄（尺寸走设置面板），右下角是空的，而且能避开编辑顶栏的
          // 「完成」按钮（悬浮钟默认就停在屏幕上方，右上角会与顶栏抢点击）。
          .position({ x: '100%', y: allowHandle ? '0%' : '100%' })
          .markAnchor({ x: '100%', y: allowHandle ? '0%' : '100%' })
          .offset({ x: -2, y: allowHandle ? 8 : -8 })
          .onTouch((event: TouchEvent): void => {
            // 吃掉触摸，避免触发下面的卡片拖动
            event.stopPropagation();
          })
          .onClick((): void => {
            this.confirmRemoveCard(card.id);
          })
        }
        // 拖动非法：整卡红边警示
        if (card.id === this.dragCardId && this.dragInvalid) {
          Column()
            .width('100%')
            .height('100%')
            .border({ width: 2, color: SCREEN_SAVER_COLORS.danger, radius: SCREEN_SAVER_METRICS.cardRadius })
        }
        // 拉伸预览与其它卡片重叠/越界：同样用红边警示（松手会被拒绝并回到原尺寸）
        if (card.id === this.resizeCardId && this.resizeInvalid) {
          Column()
            .width('100%')
            .height('100%')
            .border({ width: 2, color: SCREEN_SAVER_COLORS.danger, radius: SCREEN_SAVER_METRICS.cardRadius })
        }
        // 拉伸中：右上角实时尺寸标签（绝对定位到 TopEnd 内侧）
        if (card.id === this.resizeCardId && this.resizeLabel.length > 0) {
          Text(this.resizeLabel)
            .fontSize(12)
            .fontColor(SCREEN_SAVER_COLORS.white)
            .padding({ left: 8, right: 8, top: 2, bottom: 2 })
            .borderRadius(6)
            .backgroundColor(SCREEN_SAVER_COLORS.accentStrong)
            .position({ x: '100%', y: '0%' })
            .markAnchor({ x: '100%', y: '0%' })
            .offset({ x: -6, y: 6 })
            .hitTestBehavior(HitTestMode.None)
        }
      }
      // ---------- 拉伸手柄（两层重叠：透明热区 + 可见圆点） ----------
      // 手柄钉在右下角：position + markAnchor 绝对定位（不引入中间容器，
      // 避免容器挡掉子节点的触摸测试）；热区与视觉圆点重叠在同一角。
      // 悬浮卡不显示缩放手柄（它不占网格，尺寸由设置面板的尺寸胶囊决定）。
      if (this.editMode && allowHandle) {
        // 热区层：接收触摸（44vp，好按）
        Column()
          .width(SCREEN_SAVER_METRICS.handleHitSize)
          .height(SCREEN_SAVER_METRICS.handleHitSize)
          .position({ x: '100%', y: '100%' })
          .markAnchor({ x: '100%', y: '100%' })
          .onClick((): void => {
            // 点手柄只做「选中 + 准备缩放」。缩放松手后的补发 click 由
            // gestureCommitAtMs 的 300ms 屏蔽窗拦掉，不会顺带把设置面板点开。
            this.selectCard(card.id);
          })
          .onTouch((event: TouchEvent): void => {
            this.onHandleTouch(card, event);
          })
        // 视觉层：28vp 圆点（纯显示）。
        // 关键：圆点自身也必须 HitTestMode.None——否则它作为最上层节点会先被
        // 命中却无人处理，触摸直接冒泡给卡片本体（拖动），热区永远收不到事件。
        Column() {
          Column()
            .width(SCREEN_SAVER_METRICS.handleVisualSize)
            .height(SCREEN_SAVER_METRICS.handleVisualSize)
            .borderRadius(8)
            .backgroundColor(SCREEN_SAVER_COLORS.accent)
            .hitTestBehavior(HitTestMode.None)
        }
        .width(SCREEN_SAVER_METRICS.handleHitSize)
        .height(SCREEN_SAVER_METRICS.handleHitSize)
        .justifyContent(FlexAlign.End)
        .alignItems(HorizontalAlign.End)
        .hitTestBehavior(HitTestMode.None)
        .padding({ right: 8, bottom: 8 })
        .position({ x: '100%', y: '100%' })
        .markAnchor({ x: '100%', y: '100%' })
      }
    }
    .width('100%')
    .height('100%')
    // 变更项 1/3.1：所有卡片统一「无卡面底色、无描边、无阴影/发光/遮罩」。
    // 圆角裁剪策略见 cardClipRadius（相册/视频不裁剪，内容自行定形；其余保留作溢出保护）。
    .borderRadius(this.cardClipRadius(card))
    .border({
      width: this.showCardBorder() ? 1 : 0,
      color: this.inkPalette().cardBorder,
      radius: this.cardClipRadius(card)
    })
    .backgroundColor(Color.Transparent)
    .clip(true)
    // 播放态：卡片自身 Transparent，触摸透传给整页（点击唤胶囊）；
    // 编辑态：Default，卡片自己接触摸（拖动/选中）。
    .hitTestBehavior(this.editMode ? HitTestMode.Default : HitTestMode.Transparent)
    // 编辑入场时整体缩到 0.96，营造「进入编辑」的层次感
    .scale({
      x: this.editMode && this.editProgress > 0 ? 0.96 : 1,
      y: this.editMode && this.editProgress > 0 ? 0.96 : 1
    })
    // 拖动位移实时跟随手指
    .offset({
      x: card.id === this.dragCardId ? this.dragOffsetX : 0,
      y: card.id === this.dragCardId ? this.dragOffsetY : 0
    })
    // 拖动中的卡片浮到最上层
    .zIndex(card.id === this.dragCardId ? 20 : index)
    // 防烧屏位移（仅播放态的时钟卡片生效）
    .translate({
      x: this.burnInX(card),
      y: this.burnInY(card)
    })
    // 编辑态点击逻辑：未选中→仅选中；已选中→打开「这张卡片」的设置；
    // 播放态→交给统一的 handlePlayModeCardTap（变更项 2/3 的唯一拦截点）。
    // 拖动松手后 300ms 内的 click 直接忽略（系统可能在拖动后补发 click）。
    .onClick((): void => {
      if (this.editMode) {
        if (Date.now() - this.gestureCommitAtMs < 300) {
          return;
        }
        if (card.id === this.selectedCardId) {
          this.openSheetForCard(card.id, card.cardType);
        } else {
          this.selectCard(card.id);
        }
      } else {
        this.handlePlayModeCardTap(card);
      }
    })
    // 播放态长按卡片进入编辑模式，并选中被长按的卡片
    .gesture(
      LongPressGesture({ repeat: false, duration: SCREEN_SAVER_METRICS.longPressMs })
        .onAction((): void => {
          this.longPressAtMs = Date.now();
          if (!this.editMode) {
            this.enterEditMode();
            this.selectCard(card.id);
          }
        })
    )
    // 触摸交给拖动逻辑（编辑态才真正生效）
    .onTouch((event: TouchEvent): void => {
      this.onCellTouch(card, event);
    })
  }

  /**
   * 「单卡片垂直居中」（全局设置 singleCardCentered）是否生效：
   * 只有 1 张网格卡片、没有悬浮卡时才生效。
   * 注意：**编辑态与屏保展示态用同一判据**（不再按模式区分），
   * 这是变更项 1 的关键——旧实现只在屏保展示态下移，导致进入屏保后卡片整体位移。
   */
  private singleCardCenteredActive(): boolean {
    return this.gridEntries().length === 1 &&
      this.floatingEntries().length === 0 &&
      screenSaverAppModel.layout.settings.singleCardCentered;
  }

  /**
   * 内容层垂直偏移（vp）——**全页面唯一的一处位移策略**（变更项 1 修复点）。
   *
   * 历史问题：旧实现给屏保展示态的网格单独加了「剩余空行折半下移」的
   * translate（playCenterOffsetY），编辑态恒为 0，悬浮层又是第三套坐标，
   * 于是「进入屏保后网格卡片整体下移、悬浮时钟不动」。
   *
   * 现在：默认偏移恒为 0（卡片位置 = 网格坐标 × 单元格尺寸，与模式无关）；
   * 只有用户显式打开「单卡片垂直居中」且布局确实只有一张卡时，才按
   * 剩余空行折半下移——这个偏移**编辑态与屏保态完全一致**，
   * 因此进出编辑态不会产生任何位移。
   */
  private gridOffsetY(): number {
    if (!this.singleCardCenteredActive() || this.gridH <= 0) {
      return 0;
    }
    const card = this.gridEntries()[0].card;
    let usedRows = card.rowStart + card.rowSpan;
    if (this.resizeCardId === card.id) {
      // 拉伸预览期间卡片跨度在变：用拖动前的行数作为基准，
      // 避免「调尺寸时整块画布跟着上下跳」。
      usedRows = this.resizeOriginRowStart + this.resizeOriginRowSpan;
    }
    const rowOffset = screenSaverCenteredRowOffset(0, usedRows, this.gridRows());
    return screenSaverRowOffsetToVp(rowOffset, this.gridMetrics());
  }

  /**
   * 网格列数：编辑态固定 4 列（编辑视图跨设备一致），播放态按断点。
   */
  private gridColumns(): number {
    if (this.mode === ScreenSaverOrientation.Landscape) {
      return SCREEN_SAVER_LANDSCAPE_GRID_COLS;
    }
    return this.editMode ? SCREEN_SAVER_GRID_COLS : this.columns;
  }

  /**
   * 网格行数：横屏固定 2 行；竖屏编辑态固定 8 行、播放态按断点。
   */
  private gridRows(): number {
    if (this.mode === ScreenSaverOrientation.Landscape) {
      return SCREEN_SAVER_LANDSCAPE_GRID_ROWS;
    }
    return this.editMode ? SCREEN_SAVER_GRID_ROWS : this.rows;
  }

  /**
   * 屏保整体背景层（变更项 7）：
   *   1. 色值：直接铺一层纯色（默认纯黑）；
   *   2. 图片：用户自选图片的**离屏模糊结果**（已缓存），Cover 铺满；
   * 它永远是 Stack 的第一个子节点（最底层），不参与任何卡片定位，
   * 因此切换背景不会引起卡片重排或位移；也不拦截触摸（HitTestMode.None），
   * 保证「点空白唤出退出胶囊」的手势不被背景层吃掉。
   */
  @Builder
  backgroundLayer() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.canvasColor())
        .hitTestBehavior(HitTestMode.None)
      if (this.canvasPixel !== undefined) {
        Image(this.canvasPixel)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .hitTestBehavior(HitTestMode.None)
      }
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.None)
  }

  /** 背景色：设置里的值；未设置时退回默认纯黑。 */
  private canvasColor(): string {
    const color = screenSaverAppModel.layout.settings.canvasColor;
    return color.length > 0 ? color : SCREEN_SAVER_DEFAULT_CANVAS_COLOR;
  }

  /**
   * 页面主体（Stack 分层）：
   *   背景层：屏保整体背景（变更项 7，永远在最底层，不参与卡片定位）；
   *   内容层：空态 / 标准网格（卡片按网格坐标渲染，编辑态与屏保态同一坐标基准）；
   *   悬浮层：悬浮卡片（不占网格，绝对定位）；
   *   编辑层：网格线 + 顶栏底栏（仅编辑态）；
   *   胶囊层：「退出屏保」（仅播放态胶囊可见时）。
   * 根节点挂：长按进编辑、点击唤胶囊、整页透明度、bindSheet 设置面板。
   */
  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.Top }) {
        if (this.lockMode === 'cards') {
        // ---------- 背景层（变更项 7）：整体背景永远在卡片与悬浮时钟之下 ----------
        this.backgroundLayer()

        // ---------- 内容层（外层负责进场缩放） ----------
        Column() {
          if (this.cards().length === 0) {
            this.emptyState()
          } else {
            // 标准网格布局：GridItem 按 colStart/rowStart/colSpan/rowSpan 定位。
            // 居中偏移（如启用「单卡居中」）通过 gridOffsetY 统一施加，
            // 编辑态与屏保态取值相同 —— 不再有「只有屏保态下移」的特判。
            Column() {
              Grid() {
                ForEach(this.gridEntries(), (entry: ScreensaverGridEntry) => {
                  GridItem() {
                    this.cardCell(entry.card, entry.index, true)
                  }
                  .rowStart(this.renderSpanOf(entry.index, entry.card).rowStart)
                  .rowEnd(this.renderSpanOf(entry.index, entry.card).rowStart +
                    this.renderSpanOf(entry.index, entry.card).rowSpan - 1)
                  .columnStart(this.renderSpanOf(entry.index, entry.card).colStart)
                  .columnEnd(this.renderSpanOf(entry.index, entry.card).colStart +
                    this.renderSpanOf(entry.index, entry.card).colSpan - 1)
                  .hitTestBehavior(this.editMode ? HitTestMode.Default : HitTestMode.Transparent)
                }, (entry: ScreensaverGridEntry): string => entry.card.id)
              }
              .columnsTemplate(this.templateOf(this.gridColumns()))
              .rowsTemplate(this.templateOf(this.gridRows()))
              // 宽屏编辑态网格限宽 480：编辑视图不至于铺满大屏
              .width(this.editMode && this.isWide ? SCREEN_SAVER_EDIT_MAX_WIDTH : '100%')
              .height('100%')
              // 统一的内容层垂直偏移（默认 0；仅「单卡居中」设置开启时非 0）
              .translate({ y: this.gridOffsetY() })
              .onClick((): void => {
                this.handleScreenTap();
              })
              // 量出网格实际尺寸：拖动/拉伸的格子换算全靠它
              .onAreaChange((oldArea: Area, newArea: Area): void => {
                this.gridW = typeof newArea.width === 'number' ? newArea.width : 0;
                this.gridH = typeof newArea.height === 'number' ? newArea.height : 0;
              })
            }
            .width('100%')
            .height('100%')
            .alignItems(HorizontalAlign.Center)
          }
        }
        .width('100%')
        .height('100%')
        // 安全区：横屏刘海 / 底部导航指示条不遮挡卡片（背景层不受影响）
        .padding({
          left: this.safeInsets.left,
          right: this.safeInsets.right,
          top: this.safeInsets.top,
          bottom: this.safeInsets.bottom
        })
        // 缺陷 2 转场：进入屏保时卡片层从 0.98 轻微放大到 1（一次性，非常驻）
        .scale({ x: this.cardLayerScale, y: this.cardLayerScale })

        // ---------- 悬浮层（需求 B）：不占网格、层级高于所有网格卡片 ----------
        // 每个悬浮卡单独定位（不用满尺寸容器，避免容器挡住下层的网格卡触摸）；
        // 播放态 HitTestMode.None → 完全点击穿透，保证「点任意处唤出退出胶囊」不被截断。
        ForEach(this.floatingEntries(), (entry: ScreensaverGridEntry) => {
          Column() {
            this.cardCell(entry.card, entry.index, false)
          }
          .width(this.floatRect(entry.card).width)
          .height(this.floatRect(entry.card).height)
          .position({ x: this.floatRect(entry.card).x, y: this.floatRect(entry.card).y })
          .zIndex(this.floatDragCardId === entry.card.id ? SCREEN_SAVER_FLOAT_Z_DRAGGING :
          SCREEN_SAVER_FLOAT_Z_BASE + entry.index)
          .hitTestBehavior(this.editMode ? HitTestMode.Default : HitTestMode.None)
        }, (entry: ScreensaverGridEntry): string => entry.card.id)

        // ---------- 编辑层：网格线 + 顶底栏 ----------
        // zIndex 抬到悬浮层之上（见 SCREEN_SAVER_EDIT_CHROME_Z 注释）。
        if (this.editMode) {
          this.gridOverlay()
          Column() {
            this.editTopBar()
            this.editBottomBar()
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.SpaceBetween)
          .hitTestBehavior(HitTestMode.None)
          .zIndex(SCREEN_SAVER_EDIT_CHROME_Z)
          // 调试入口：无传感器环境（模拟器）验证固定锁屏；仅编辑态可见。
          Column() {
            Text('调试：进入固定锁屏')
              .fontSize(10)
              .fontColor(SCREEN_SAVER_COLORS.textSecondary)
              .padding({ left: 12, right: 12, top: 6, bottom: 6 })
              .borderRadius(12)
              .backgroundColor('#66000000')
              .hitTestBehavior(HitTestMode.BLOCK_HIERARCHY)
              .onClick((): void => {
                this.exitEditMode(false);
                this.switchLockMode('gallery');
              })
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.End)
          .alignItems(HorizontalAlign.Center)
          .padding({ bottom: 84 })
          .hitTestBehavior(HitTestMode.None)
          .zIndex(SCREEN_SAVER_EDIT_CHROME_Z + 1)
        }
        } else {
          // ---------- 固定主题锁屏（gallery）：整体替换内容区，不与卡片叠加 ----------
          ScreensaverGallery({
            themeIndex: this.galleryThemeIndex,
            active: this.pageActive
            // 固定屏保互动已全部注释：点击不再唤出胶囊 / 触发主题特效
            // onScreenTap: (): void => {
            //   this.handleScreenTap();
            // }
          })
        }

        // ---------- 胶囊层：退出屏保 ----------
        if (this.capsuleVisible && !this.editMode) {
          Column() {
            Text('退出屏保')
              .fontSize(14)
              .fontColor('#E6E6E6')
              .padding({ left: 20, right: 20, top: 10, bottom: 10 })
              .borderRadius(SCREEN_SAVER_METRICS.capsuleHeight / 2)
              .backgroundColor('#66000000')
              .onClick((): void => {
                this.exitScreensaver();
              })
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.End)
          .alignItems(HorizontalAlign.Center)
          .padding({ bottom: 80 + this.safeInsets.bottom })
          .zIndex(SCREEN_SAVER_EDIT_CHROME_Z)
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(SCREEN_SAVER_COLORS.canvasBg)
      // 整页长按 600ms：任意空白处进入编辑模式（卡片级长按另有一条）。
      // 手指移动超过长按阈值时系统会取消长按，卡片内滚动不会误触发。
      .gesture(
        LongPressGesture({ repeat: false, duration: SCREEN_SAVER_METRICS.longPressMs })
          .onAction((): void => {
            this.longPressAtMs = Date.now();
            if (this.lockMode === 'gallery') {
              // 固定屏保互动已全部注释：长按不再进入当前方向设置页
              // this.openModeSettings();
              return;
            }
            if (!this.editMode) {
              this.enterEditMode();
            }
          })
      )
      .onClick((): void => {
        this.handleScreenTap();
      })
      // 进出场动画 + 模式切换淡入的透明度（都只跑一次，静止态恒为 1）
      .opacity(this.displayOpacity * this.modeSwitchOpacity)
      // 设置面板（编辑态双击卡片弹出）
      .bindSheet(this.sheetVisible, this.sheetContent(), {
        height: 452,
        dragBar: true,
        showClose: false,
        backgroundColor: '#141417',
        onDisappear: (): void => {
          this.clearSheetTarget();
        }
      })
    }
    .hideTitleBar(true)
    .backgroundColor(SCREEN_SAVER_COLORS.canvasBg)
    // 页面生命周期：被方向设置页遮住 / 重新可见时成对停启定时器与轮询。
    .onShown((): void => {
      this.onPageShown();
    })
    .onHidden((): void => {
      this.onPageHidden();
    })
    /**
     * 系统返回键：
     * 编辑态 → 先退出编辑（保留改动）；
     * 播放态 → 退出屏保。
     */
    .onBackPressed((): boolean => {
      if (this.editMode) {
        this.exitEditMode(false);
        return true;
      }
      this.exitScreensaver();
      return true;
    })
  }
}
