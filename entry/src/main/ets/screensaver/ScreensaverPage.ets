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
import { batteryInfo } from '@kit.BasicServicesKit';
import { ScreenSaverLogger } from '../common/Logger';
import { screenSaverWindowController } from '../common/WindowController';
import { screenSaverVibration } from '../common/VibrationHelper';
import { ScreensaverCardHost } from '../cards/CardHost';
import { screenSaverAppModel } from '../model/AppModel';
import { screenSaverGitViewModel } from '../model/GitViewModel';
import { SCREEN_SAVER_COLORS, SCREEN_SAVER_METRICS } from '../common/ScreenSaverStyle';
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
import { screenSaverCardTypeName } from '../cards/CardCatalog';
import { ScreenSaverClockSettingsPanel } from './sheets/ClockSettingsSheet';
import { ScreenSaverPhotoSettingsPanel } from './sheets/PhotoSettingsSheet';
import { ScreenSaverVideoSettingsPanel } from './sheets/VideoSettingsSheet';
import { ScreenSaverGitSettingsPanel } from './sheets/GitSettingsSheet';
import {
  SCREEN_SAVER_GRID_COLS,
  SCREEN_SAVER_GRID_ROWS,
  SheetKind,
  ScreensaverCardInstance,
  ScreensaverGridPos
} from '../model/ConfigModels';

const FALLBACK_CARD_ID: string = 'fallback_clock';
/** 宽屏（折叠屏/平板）编辑态下网格的最大宽度，保证编辑视图不会太宽。 */
const SCREEN_SAVER_EDIT_MAX_WIDTH: number = 480;
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

  // ============ 状态标志（@Local：组件内响应式） ============
  /** 整页透明度：进出场动画用（0 透明 → 1 完全显示）。 */
  @Local displayOpacity: number = 0;
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

  // ============ 拖动状态 ============
  /** 正在拖动的卡片 id（'' = 没在拖）。 */
  @Local dragCardId: string = '';
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
  /** 拉伸时显示的尺寸标签（如「4×2」）。 */
  @Local resizeLabel: string = '';

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

  // ============ 非响应式私有字段 ============
  /** 胶囊自动隐藏定时器 id（-1 = 无定时器）。 */
  private capsuleTimer: number = -1;
  /** 防烧屏定时器 id。 */
  private burnInTimer: number = -1;
  /** 低电量轮询定时器 id。 */
  private batteryTimer: number = -1;
  /** 防烧屏偏移表当前步进（0~4 循环）。 */
  private burnInStep: number = 0;
  /** 网格实际渲染宽度（vp，onAreaChange 回调里更新，拖动换算用）。 */
  private gridW: number = 0;
  /** 网格实际渲染高度（vp）。 */
  private gridH: number = 0;
  /** 拖动手势起点坐标（vp）。 */
  private touchStartX: number = 0;
  private touchStartY: number = 0;
  /** 拉伸手势起点坐标（vp）。 */
  private resizeTouchStartX: number = 0;
  private resizeTouchStartY: number = 0;
  /** 编辑模式快照（JSON 文本），「取消」时回滚。 */
  private editSnapshotText: string = '';
  /** 宽屏重排后的卡片位置表（与 layout.cards 下标一一对应）。 */
  private widePositions: ScreensaverGridPos[] = [];
  /** 断点观察者（监听窗口宽度变化切换网格规格）。 */
  private breakpointObserver: ScreenSaverBreakpointObserver = new ScreenSaverBreakpointObserver();

  /**
   * 页面出现：
   * 1. 进入「屏保窗口模式」：保持亮屏 + 沉浸式全屏（按设置决定 keepScreenOn）；
   * 2. 启动断点监听；
   * 3. 进场淡入动画（减弱动效时直接显示，不播动画）；
   * 4. Git 卡片先显示本地缓存（hydrate），避免白等网络；
   * 5. 启动防烧屏定时器和低电量轮询。
   */
  aboutToAppear(): void {
    const context = this.getUIContext().getHostContext();
    if (context !== undefined) {
      void screenSaverWindowController.enter(context, screenSaverAppModel.layout.settings.keepScreenOn);
    }
    this.breakpointObserver.start(
      (condition: string): mediaquery.MediaQueryListener => this.getUIContext().getMediaQuery().matchMediaSync(condition),
      (value: ScreenSaverBreakpoint): void => {
        this.onBreakpointChanged(value);
      });
    // 进场动画：opacity 0 → 1（motionDuration 会按「减弱动效」设置压缩时长，0 则跳过）
    const enterMs = screenSaverMotionDuration(SCREEN_SAVER_MOTION_ENTER_MS);
    if (enterMs <= 0) {
      this.displayOpacity = 1;
    } else {
      this.getUIContext().animateTo({
        duration: enterMs,
        curve: Curve.EaseOut
      }, (): void => {
        this.displayOpacity = 1;
      });
    }
    screenSaverGitViewModel.hydrateFromCache();
    this.startBurnInTimer();
    this.startBatteryWatch();
  }

  /**
   * 页面消失（退出屏保）：
   * 清掉所有定时器 → 退出屏保窗口模式 → 强制把未落盘的改动刷盘。
   */
  aboutToDisappear(): void {
    this.stopCapsuleTimer();
    this.stopBurnInTimer();
    this.stopBatteryWatch();
    this.breakpointObserver.stop();
    this.pageActive = false;
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
    this.isWide = value.isWide;
    if (value.isWide) {
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
    if (!this.editMode && this.isWide && index < this.widePositions.length) {
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
   * 进入编辑模式：
   * 震动反馈 → 存布局快照（供「取消」回滚）→ 播放入场过渡。
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
   */
  private handleScreenTap(): void {
    ScreenSaverLogger.info(`screen tap, editMode=${this.editMode}, capsule=${this.capsuleVisible}`);
    if (this.editMode) {
      return;
    }
    if (this.capsuleVisible) {
      this.hideCapsuleWithFade();
    } else {
      this.showCapsule();
    }
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
   * 为选中卡片打开指定类型的设置面板（未选中先提示）。
   */
  private openSheetForSelected(kind: SheetKind): void {
    if (this.selectedCardId.length === 0) {
      this.toast('请先选择一张卡片');
      return;
    }
    this.sheetCardId = this.selectedCardId;
    this.sheetKind = kind;
    this.sheetVisible = true;
  }

  /**
   * 按选中卡片的类型打开对应设置面板（类型由卡片自身决定）。
   */
  private openSettingsForSelected(): void {
    const card = screenSaverAppModel.cardById(this.selectedCardId);
    if (card === undefined) {
      this.toast('请先选择一张卡片');
      return;
    }
    this.openSheetForSelected(card.cardType);
  }

  /** 关闭设置面板。 */
  private closeSheet(): void {
    this.sheetVisible = false;
    this.sheetKind = 'none';
  }

  /** 直接移除选中卡片（设置面板里的「删除」入口，无确认——面板本身已是明确操作）。 */
  private removeSelected(): void {
    if (this.selectedCardId.length === 0) {
      return;
    }
    screenSaverAppModel.removeCard(this.selectedCardId);
    this.selectedCardId = '';
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

  /** 跳转卡片库页面（编辑态点「＋ 添加卡片」）。 */
  private addCardViaLibrary(): void {
    this.navStack.pushPathByName('library', '');
  }

  // ==================== 拖动（移动卡片）====================

  /** 开始拖动：记录卡片 id，清零位移，顺带选中它。 */
  private beginDrag(cardId: string): void {
    ScreenSaverLogger.info(`begin drag ${cardId}`);
    this.dragCardId = cardId;
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
   * 位移 ÷ 单元格尺寸 = 格子增量（四舍五入到最近的格），
   * 再 clamp 到网格边界内。
   */
  private targetSlot(card: ScreensaverCardInstance, offsetX: number, offsetY: number): ScreensaverGridPos {
    const cellWidth = this.gridW / SCREEN_SAVER_GRID_COLS;
    const cellHeight = this.cellHeight();
    const deltaCol = Math.round(offsetX / cellWidth);
    const deltaRow = Math.round(offsetY / cellHeight);
    let colStart = card.colStart + deltaCol;
    let rowStart = card.rowStart + deltaRow;
    colStart = Math.max(0, Math.min(colStart, SCREEN_SAVER_GRID_COLS - card.colSpan));
    rowStart = Math.max(0, Math.min(rowStart, SCREEN_SAVER_GRID_ROWS - card.rowSpan));
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

  /** 单元格高度（vp）；网格还没量出来时返回 1 防止除零。 */
  private cellHeight(): number {
    if (this.gridH <= 0) {
      return 1;
    }
    return this.gridH / SCREEN_SAVER_GRID_ROWS;
  }

  // ==================== 拉伸（改尺寸）====================

  /** 开始拉伸：记录卡片 id，显示当前尺寸标签，顺带选中它。 */
  private beginResize(cardId: string): void {
    ScreenSaverLogger.info(`begin resize ${cardId}`);
    this.resizeCardId = cardId;
    this.resizeOffsetX = 0;
    this.resizeOffsetY = 0;
    this.selectCard(cardId);
    const card = screenSaverAppModel.cardById(cardId);
    if (card !== undefined) {
      this.resizeLabel = `${card.colSpan}×${card.rowSpan}`;
    }
  }

  /** 拉伸中：实时更新尺寸标签（如「4×2」→「4×3」）。 */
  private updateResize(cardId: string, offsetX: number, offsetY: number): void {
    if (this.resizeCardId !== cardId) {
      return;
    }
    this.resizeOffsetX = offsetX;
    this.resizeOffsetY = offsetY;
    const preview = this.targetSpan(offsetX, offsetY);
    if (preview !== undefined) {
      this.resizeLabel = `${preview.colSpan}×${preview.rowSpan}`;
    }
  }

  /**
   * 把拉伸位移换算成预览尺寸（colSpan/rowSpan）：
   * 起点固定，位移 ÷ 单元格尺寸 = 跨格增量，clamp 到 [1, 边界]。
   */
  private targetSpan(offsetX: number, offsetY: number): ScreensaverGridPos | undefined {
    const card = screenSaverAppModel.cardById(this.resizeCardId);
    if (card === undefined || this.gridW <= 0) {
      return undefined;
    }
    const cellWidth = this.gridW / SCREEN_SAVER_GRID_COLS;
    const cellHeight = this.cellHeight();
    const deltaCols = Math.round(offsetX / cellWidth);
    const deltaRows = Math.round(offsetY / cellHeight);
    let colSpan = card.colSpan + deltaCols;
    let rowSpan = card.rowSpan + deltaRows;
    colSpan = Math.max(1, Math.min(colSpan, SCREEN_SAVER_GRID_COLS - card.colStart));
    rowSpan = Math.max(1, Math.min(rowSpan, SCREEN_SAVER_GRID_ROWS - card.rowStart));
    const pos: ScreensaverGridPos = {
      colStart: card.colStart,
      rowStart: card.rowStart,
      colSpan: colSpan,
      rowSpan: rowSpan
    };
    return pos;
  }

  /**
   * 松手提交拉伸：尺寸没变就什么都不做；
   * 变了则 resizeCardTo（带碰撞/最小尺寸校验），失败 toast 原因。
   */
  private commitResize(cardId: string): void {
    const offsetX = this.resizeOffsetX;
    const offsetY = this.resizeOffsetY;
    this.resizeCardId = '';
    this.resizeOffsetX = 0;
    this.resizeOffsetY = 0;
    this.resizeLabel = '';
    const target = this.targetSpanFor(cardId, offsetX, offsetY);
    if (target === undefined) {
      ScreenSaverLogger.info('resize commit: no target');
      return;
    }
    const card = screenSaverAppModel.cardById(cardId);
    if (card === undefined) {
      return;
    }
    if (target.colSpan === card.colSpan && target.rowSpan === card.rowSpan) {
      ScreenSaverLogger.info(`resize commit: unchanged ${card.colSpan}x${card.rowSpan}`);
      return;
    }
    const resized = screenSaverAppModel.resizeCardTo(cardId, target.colSpan, target.rowSpan);
    ScreenSaverLogger.info(`resize commit: ${card.cardType} -> ${target.colSpan}x${target.rowSpan} ok=${resized}`);
    if (!resized) {
      this.toast('尺寸不可用：已到最小/最大格数或与其它卡片重叠');
    }
  }

  /** commitResize 用的尺寸换算（此时 resizeCardId 已被清空，改按参数取卡片）。 */
  private targetSpanFor(cardId: string, offsetX: number, offsetY: number): ScreensaverGridPos | undefined {
    const card = screenSaverAppModel.cardById(cardId);
    if (card === undefined || this.gridW <= 0) {
      return undefined;
    }
    const cellWidth = this.gridW / SCREEN_SAVER_GRID_COLS;
    const cellHeight = this.cellHeight();
    const deltaCols = Math.round(offsetX / cellWidth);
    const deltaRows = Math.round(offsetY / cellHeight);
    let colSpan = card.colSpan + deltaCols;
    let rowSpan = card.rowSpan + deltaRows;
    colSpan = Math.max(1, Math.min(colSpan, SCREEN_SAVER_GRID_COLS - card.colStart));
    rowSpan = Math.max(1, Math.min(rowSpan, SCREEN_SAVER_GRID_ROWS - card.rowStart));
    const pos: ScreensaverGridPos = {
      colStart: card.colStart,
      rowStart: card.rowStart,
      colSpan: colSpan,
      rowSpan: rowSpan
    };
    return pos;
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
   * 卡片本体触摸（编辑态的拖动）：
   * Down 记起点并 beginDrag；Move 更新位移；
   * Up/Cancel 提交（commitDrag）。
   * 播放态完全忽略（返回，让点击透传给页面）。
   */
  private onCellTouch(card: ScreensaverCardInstance, event: TouchEvent): void {
    if (!this.editMode) {
      return;
    }
    const touch = event.touches[0];
    if (touch === undefined) {
      return;
    }
    // px2vp：物理像素转视觉像素（手势计算统一用 vp）
    const x = px2vp(touch.windowX);
    const y = px2vp(touch.windowY);
    if (event.type === TouchType.Down) {
      this.touchStartX = x;
      this.touchStartY = y;
      this.beginDrag(card.id);
    } else if (event.type === TouchType.Move) {
      if (this.dragCardId === card.id) {
        this.updateDrag(card.id, x - this.touchStartX, y - this.touchStartY);
      }
    } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      if (this.dragCardId === card.id) {
        this.commitDrag(card.id);
      }
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
    const x = px2vp(touch.windowX);
    const y = px2vp(touch.windowY);
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
        ScreensaverClockCard({ card: this.fallbackCard, cardMode: 'play' })
      }
      .width('100%')
      .height(158)
      .translate({
        x: this.burnInX(this.fallbackCard),
        y: this.burnInY(this.fallbackCard)
      })
      Text('长按进入编辑模式 · 再点「＋ 添加卡片」')
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
   */
  @Builder
  gridOverlay() {
    Column() {
      ForEach([0, 1, 2, 3, 4, 5, 6, 7], (rowIndex: number) => {
        Row() {
          ForEach([0, 1, 2, 3], (colIndex: number) => {
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
    .opacity(0.6)
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
   * 编辑态底栏：「＋ 添加卡片」（跳卡片库）+ 操作提示文案。
   */
  @Builder
  editBottomBar() {
    Row() {
      Column() {
        Text('＋ 添加卡片')
          .fontSize(13)
          .fontColor(SCREEN_SAVER_COLORS.white)
          .padding({ left: 18, right: 18, top: 7, bottom: 7 })
          .borderRadius(16)
          .backgroundColor(SCREEN_SAVER_COLORS.accent)
      }
      .constraintSize({ minHeight: 40 })
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .onClick((): void => {
        this.addCardViaLibrary();
      })
      Blank()
      if (this.cards().length > 0) {
        Text('长按拖动 · 单击配置')
          .fontSize(11)
          .fontColor(SCREEN_SAVER_COLORS.textTertiary)
      }
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
            this.removeSelected();
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
            this.removeSelected();
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
            this.removeSelected();
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
            this.removeSelected();
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
  @Builder
  cardCell(card: ScreensaverCardInstance, index: number) {
    Stack() {
      // ---------- 底层：停用占位 或 真卡片 ----------
      if (!card.enabled) {
        Column({ space: 4 }) {
          Text(screenSaverCardTypeName(card.cardType))
            .fontSize(13)
            .fontColor(SCREEN_SAVER_COLORS.textSecondary)
          Text('已停用')
            .fontSize(11)
            .fontColor(SCREEN_SAVER_COLORS.textTertiary)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .border({
          width: 1,
          color: '#33FFFFFF',
          radius: 8,
          style: BorderStyle.Dashed
        })
      } else {
        ScreensaverCardHost({
          card: card,
          cardMode: this.editMode ? 'edit' : 'play',
          cardActive: this.pageActive && !this.editMode,
          onRequestConfig: (): void => {
            // 卡片内部「点我配置」按钮 → 选中并打开对应设置面板
            this.selectCard(card.id);
            this.openSettingsForSelected();
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
            .border({ width: 2, color: SCREEN_SAVER_COLORS.accent, radius: 8 })
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
          .align(Alignment.TopEnd)
          .margin({ right: 2, top: 8 })
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
            .border({ width: 2, color: SCREEN_SAVER_COLORS.danger, radius: 8 })
        }
        // 拉伸中：右上角实时尺寸标签
        if (card.id === this.resizeCardId && this.resizeLabel.length > 0) {
          Text(this.resizeLabel)
            .fontSize(12)
            .fontColor(SCREEN_SAVER_COLORS.white)
            .padding({ left: 8, right: 8, top: 2, bottom: 2 })
            .borderRadius(6)
            .backgroundColor(SCREEN_SAVER_COLORS.accentStrong)
            .align(Alignment.TopEnd)
        }
      }
      // ---------- 拉伸手柄（两层：透明热区 + 可见圆点） ----------
      if (this.editMode) {
        // 热区层：接收触摸（40vp，好按）
        Column()
          .width(SCREEN_SAVER_METRICS.handleHitSize)
          .height(SCREEN_SAVER_METRICS.handleHitSize)
          .align(Alignment.BottomEnd)
          .onClick((): void => {
            this.selectCard(card.id);
          })
          .onTouch((event: TouchEvent): void => {
            this.onHandleTouch(card, event);
          })
        // 视觉层：28vp 圆点（不响应触摸，纯显示）
        Column() {
          Column()
            .width(SCREEN_SAVER_METRICS.handleVisualSize)
            .height(SCREEN_SAVER_METRICS.handleVisualSize)
            .borderRadius(8)
            .backgroundColor(SCREEN_SAVER_COLORS.accent)
        }
        .width(SCREEN_SAVER_METRICS.handleHitSize)
        .height(SCREEN_SAVER_METRICS.handleHitSize)
        .align(Alignment.BottomEnd)
        .justifyContent(FlexAlign.End)
        .hitTestBehavior(HitTestMode.None)
        .padding({ right: 8, bottom: 8 })
      }
    }
    .width('100%')
    .height('100%')
    .borderRadius(8)
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
    // 编辑态点击逻辑：已选中→打开设置；未选中→选中；
    // 播放态→当整页点击处理（唤胶囊）
    .onClick((): void => {
      if (this.editMode) {
        if (card.id === this.selectedCardId) {
          this.openSettingsForSelected();
        } else {
          this.selectCard(card.id);
        }
      } else {
        this.handleScreenTap();
      }
    })
    // 播放态长按卡片也能进编辑（与整页长按互为补充）
    .gesture(
      LongPressGesture({ repeat: false, duration: SCREEN_SAVER_METRICS.longPressMs })
        .onAction((): void => {
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
   * 「单卡片居中」是否生效：
   * 播放态 + 只有 1 张卡片 + 设置开关打开。
   */
  private singleCardCenteredActive(): boolean {
    return !this.editMode && this.cards().length === 1 &&
      screenSaverAppModel.layout.settings.singleCardCentered;
  }

  /**
   * 网格列数：编辑态固定 4 列（编辑视图跨设备一致），播放态按断点。
   */
  private gridColumns(): number {
    return this.editMode ? SCREEN_SAVER_GRID_COLS : this.columns;
  }

  /**
   * 网格行数：编辑态固定 8 行，播放态按断点。
   */
  private gridRows(): number {
    return this.editMode ? SCREEN_SAVER_GRID_ROWS : this.rows;
  }

  /**
   * 播放态网格整体下移量（vp）：
   * 卡片没占满网格时，把剩余的空行分一半到顶部——
   * 让内容整体居于屏幕中部而不是贴顶。
   * 编辑态/多卡片占满时不下移。
   */
  private playCenterOffsetY(): number {
    if (this.editMode || this.gridH <= 0) {
      return 0;
    }
    const cards = this.cards();
    if (cards.length <= 1) {
      return 0;
    }
    let usedRows = 0;
    for (let index = 0; index < cards.length; index++) {
      const pos = this.positionOf(index, cards[index]);
      usedRows = Math.max(usedRows, pos.rowStart + pos.rowSpan);
    }
    const freeRows = this.gridRows() - usedRows;
    if (freeRows <= 0) {
      return 0;
    }
    return freeRows / 2 * (this.gridH / this.gridRows());
  }

  /**
   * 页面主体（Stack 分层）：
   *   内容层：空态 / 单卡居中 / 标准网格（三选一）；
   *   编辑层：网格线 + 顶栏底栏（仅编辑态）；
   *   胶囊层：「退出屏保」（仅播放态胶囊可见时）。
   * 根节点挂：长按进编辑、点击唤胶囊、整页透明度、bindSheet 设置面板。
   */
  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.Top }) {
        // ---------- 内容层（三选一） ----------
        if (this.cards().length === 0) {
          this.emptyState()
        } else if (this.singleCardCenteredActive()) {
          // 单卡片居中：脱离 Grid，直接按比例居中摆放
          Column() {
            Column() {
              this.cardCell(this.cards()[0], 0)
            }
            .width(`${Math.min(100, this.cards()[0].colSpan / SCREEN_SAVER_GRID_COLS * 100)}%`)
            .height(`${Math.min(100, this.cards()[0].rowSpan / SCREEN_SAVER_GRID_ROWS * 100)}%`)
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        } else {
          // 标准网格布局：GridItem 按 colStart/rowStart/colSpan/rowSpan 定位
          Column() {
            Grid() {
              ForEach(this.cards(), (card: ScreensaverCardInstance, index: number) => {
                GridItem() {
                  this.cardCell(card, index)
                }
                .rowStart(this.positionOf(index, card).rowStart)
                .rowEnd(this.positionOf(index, card).rowStart + this.positionOf(index, card).rowSpan - 1)
                .columnStart(this.positionOf(index, card).colStart)
                .columnEnd(this.positionOf(index, card).colStart + this.positionOf(index, card).colSpan - 1)
                .hitTestBehavior(this.editMode ? HitTestMode.Default : HitTestMode.Transparent)
              }, (card: ScreensaverCardInstance): string => card.id)
            }
            .columnsTemplate(this.templateOf(this.gridColumns()))
            .rowsTemplate(this.templateOf(this.gridRows()))
            // 宽屏编辑态网格限宽 480：编辑视图不至于铺满大屏
            .width(this.editMode && this.isWide ? SCREEN_SAVER_EDIT_MAX_WIDTH : '100%')
            .height('100%')
            // 播放态内容整体下移（居中观感）
            .translate({ y: this.playCenterOffsetY() })
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

        // ---------- 编辑层：网格线 + 顶底栏 ----------
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
          .padding({ bottom: 80 })
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(SCREEN_SAVER_COLORS.canvasBg)
      // 整页长按：任意空白处也能进编辑模式
      .gesture(
        LongPressGesture({ repeat: false, duration: SCREEN_SAVER_METRICS.longPressMs })
          .onAction((): void => {
            if (!this.editMode) {
              this.enterEditMode();
            }
          })
      )
      .onClick((): void => {
        this.handleScreenTap();
      })
      // 进出场动画的透明度
      .opacity(this.displayOpacity)
      // 设置面板（编辑态双击卡片弹出）
      .bindSheet(this.sheetVisible, this.sheetContent(), {
        height: 452,
        dragBar: true,
        showClose: false,
        backgroundColor: '#141417',
        onDisappear: (): void => {
          this.closeSheet();
        }
      })
    }
    .hideTitleBar(true)
    .backgroundColor(SCREEN_SAVER_COLORS.canvasBg)
    /**
     * 系统返回键：
     * 编辑态 → 先退出编辑（保留改动）；
     * 播放态 → 退出屏保。
     * 两种情况都返回 true（拦截系统默认行为）。
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
