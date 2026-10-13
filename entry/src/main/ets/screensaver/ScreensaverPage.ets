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
const SCREEN_SAVER_EDIT_MAX_WIDTH: number = 480;
const SCREEN_SAVER_BURN_IN_INTERVAL_MS: number = 15 * 60 * 1000;
const SCREEN_SAVER_BATTERY_POLL_MS: number = 60 * 1000;
const SCREEN_SAVER_LOW_BATTERY_SOC: number = 20;
const SCREEN_SAVER_BURN_IN_OFFSETS: number[][] = [[0, 0], [5, -3], [-3, 5], [-5, -3], [3, 5]];

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

  @Local displayOpacity: number = 0;
  @Local capsuleVisible: boolean = false;
  @Local editMode: boolean = false;
  @Local editProgress: number = 0;
  @Local selectedCardId: string = '';
  @Local sheetVisible: boolean = false;
  @Local sheetKind: SheetKind = 'none';
  @Local sheetCardId: string = '';
  @Local dragCardId: string = '';
  @Local dragOffsetX: number = 0;
  @Local dragOffsetY: number = 0;
  @Local dragInvalid: boolean = false;
  @Local resizeCardId: string = '';
  @Local resizeOffsetX: number = 0;
  @Local resizeOffsetY: number = 0;
  @Local resizeLabel: string = '';
  @Local columns: number = SCREEN_SAVER_GRID_COLS;
  @Local rows: number = SCREEN_SAVER_GRID_ROWS;
  @Local isWide: boolean = false;
  @Local pageActive: boolean = true;
  @Local fallbackCard: ScreensaverCardInstance = buildFallbackCard();
  @Local burnInShiftX: number = 0;
  @Local burnInShiftY: number = 0;

  private capsuleTimer: number = -1;
  private burnInTimer: number = -1;
  private batteryTimer: number = -1;
  private burnInStep: number = 0;
  private gridW: number = 0;
  private gridH: number = 0;
  private touchStartX: number = 0;
  private touchStartY: number = 0;
  private resizeTouchStartX: number = 0;
  private resizeTouchStartY: number = 0;
  private editSnapshotText: string = '';
  private widePositions: ScreensaverGridPos[] = [];
  private breakpointObserver: ScreenSaverBreakpointObserver = new ScreenSaverBreakpointObserver();

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

  private cards(): ScreensaverCardInstance[] {
    return screenSaverAppModel.layout.cards;
  }

  private cardAt(index: number): ScreensaverCardInstance {
    return screenSaverAppModel.layout.cards[index];
  }

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

  private templateOf(count: number): string {
    let text = '';
    for (let index = 0; index < count; index++) {
      text = index === 0 ? '1fr' : `${text} 1fr`;
    }
    return text;
  }

  private enterEditMode(): void {
    if (this.editMode) {
      return;
    }
    ScreenSaverLogger.info('enter edit mode');
    screenSaverVibration.longPressFeedback();
    this.editSnapshotText = screenSaverAppModel.snapshotCards();
    this.editMode = true;
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

  private hideCapsule(): void {
    this.stopCapsuleTimer();
    this.capsuleVisible = false;
  }

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

  private stopCapsuleTimer(): void {
    if (this.capsuleTimer >= 0) {
      clearTimeout(this.capsuleTimer);
      this.capsuleTimer = -1;
    }
  }

  private startBurnInTimer(): void {
    this.burnInTimer = setInterval((): void => {
      this.burnInStep = (this.burnInStep + 1) % SCREEN_SAVER_BURN_IN_OFFSETS.length;
      const offset = SCREEN_SAVER_BURN_IN_OFFSETS[this.burnInStep];
      this.burnInShiftX = offset[0];
      this.burnInShiftY = offset[1];
    }, SCREEN_SAVER_BURN_IN_INTERVAL_MS);
  }

  private stopBurnInTimer(): void {
    if (this.burnInTimer >= 0) {
      clearInterval(this.burnInTimer);
      this.burnInTimer = -1;
    }
    this.burnInShiftX = 0;
    this.burnInShiftY = 0;
  }

  private burnInX(card: ScreensaverCardInstance): number {
    if (this.editMode || card.cardType !== 'clock') {
      return 0;
    }
    return this.burnInShiftX;
  }

  private burnInY(card: ScreensaverCardInstance): number {
    if (this.editMode || card.cardType !== 'clock') {
      return 0;
    }
    return this.burnInShiftY;
  }

  private startBatteryWatch(): void {
    this.checkBattery();
    this.batteryTimer = setInterval((): void => {
      this.checkBattery();
    }, SCREEN_SAVER_BATTERY_POLL_MS);
  }

  private stopBatteryWatch(): void {
    if (this.batteryTimer >= 0) {
      clearInterval(this.batteryTimer);
      this.batteryTimer = -1;
    }
  }

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

  private exitScreensaver(): void {
    const duration = screenSaverMotionDuration(SCREEN_SAVER_MOTION_EXIT_MS);
    ScreenSaverLogger.info('exit screensaver');
    this.hideCapsule();
    if (duration <= 0) {
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

  private selectCard(cardId: string): void {
    this.selectedCardId = cardId;
  }

  private openSheetForSelected(kind: SheetKind): void {
    if (this.selectedCardId.length === 0) {
      this.toast('请先选择一张卡片');
      return;
    }
    this.sheetCardId = this.selectedCardId;
    this.sheetKind = kind;
    this.sheetVisible = true;
  }

  private openSettingsForSelected(): void {
    const card = screenSaverAppModel.cardById(this.selectedCardId);
    if (card === undefined) {
      this.toast('请先选择一张卡片');
      return;
    }
    this.openSheetForSelected(card.cardType);
  }

  private closeSheet(): void {
    this.sheetVisible = false;
    this.sheetKind = 'none';
  }

  private removeSelected(): void {
    if (this.selectedCardId.length === 0) {
      return;
    }
    screenSaverAppModel.removeCard(this.selectedCardId);
    this.selectedCardId = '';
  }

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

  private addCardViaLibrary(): void {
    this.navStack.pushPathByName('library', '');
  }

  private beginDrag(cardId: string): void {
    ScreenSaverLogger.info(`begin drag ${cardId}`);
    this.dragCardId = cardId;
    this.dragOffsetX = 0;
    this.dragOffsetY = 0;
    this.dragInvalid = false;
    this.selectCard(cardId);
  }

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

  private resetDragOffsets(): void {
    this.dragOffsetX = 0;
    this.dragOffsetY = 0;
  }

  private cellHeight(): number {
    if (this.gridH <= 0) {
      return 1;
    }
    return this.gridH / SCREEN_SAVER_GRID_ROWS;
  }

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

  private toast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message, duration: 1500 });
    } catch (err) {
      const error = err as Error;
      ScreenSaverLogger.warn(`toast failed: ${error.message}`);
    }
  }

  private onCellTouch(card: ScreensaverCardInstance, event: TouchEvent): void {
    if (!this.editMode) {
      return;
    }
    const touch = event.touches[0];
    if (touch === undefined) {
      return;
    }
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

  private sheetCard(): ScreensaverCardInstance {
    const card = screenSaverAppModel.cardById(this.sheetCardId);
    return card !== undefined ? card : new ScreensaverCardInstance();
  }

  @Builder
  cardCell(card: ScreensaverCardInstance, index: number) {
    Stack() {
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
            this.selectCard(card.id);
            this.openSettingsForSelected();
          }
        })
      }
      if (this.editMode) {
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
            event.stopPropagation();
          })
          .onClick((): void => {
            this.confirmRemoveCard(card.id);
          })
        }
        if (card.id === this.dragCardId && this.dragInvalid) {
          Column()
            .width('100%')
            .height('100%')
            .border({ width: 2, color: SCREEN_SAVER_COLORS.danger, radius: 8 })
        }
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
      if (this.editMode) {
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
    .hitTestBehavior(this.editMode ? HitTestMode.Default : HitTestMode.Transparent)
    .scale({
      x: this.editMode && this.editProgress > 0 ? 0.96 : 1,
      y: this.editMode && this.editProgress > 0 ? 0.96 : 1
    })
    .offset({
      x: card.id === this.dragCardId ? this.dragOffsetX : 0,
      y: card.id === this.dragCardId ? this.dragOffsetY : 0
    })
    .zIndex(card.id === this.dragCardId ? 20 : index)
    .translate({
      x: this.burnInX(card),
      y: this.burnInY(card)
    })
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
    .gesture(
      LongPressGesture({ repeat: false, duration: SCREEN_SAVER_METRICS.longPressMs })
        .onAction((): void => {
          if (!this.editMode) {
            this.enterEditMode();
            this.selectCard(card.id);
          }
        })
    )
    .onTouch((event: TouchEvent): void => {
      this.onCellTouch(card, event);
    })
  }

  private singleCardCenteredActive(): boolean {
    return !this.editMode && this.cards().length === 1 &&
      screenSaverAppModel.layout.settings.singleCardCentered;
  }

  private gridColumns(): number {
    return this.editMode ? SCREEN_SAVER_GRID_COLS : this.columns;
  }

  private gridRows(): number {
    return this.editMode ? SCREEN_SAVER_GRID_ROWS : this.rows;
  }

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

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.Top }) {
        if (this.cards().length === 0) {
          this.emptyState()
        } else if (this.singleCardCenteredActive()) {
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
            .width(this.editMode && this.isWide ? SCREEN_SAVER_EDIT_MAX_WIDTH : '100%')
            .height('100%')
            .translate({ y: this.playCenterOffsetY() })
            .onClick((): void => {
              this.handleScreenTap();
            })
            .onAreaChange((oldArea: Area, newArea: Area): void => {
              this.gridW = typeof newArea.width === 'number' ? newArea.width : 0;
              this.gridH = typeof newArea.height === 'number' ? newArea.height : 0;
            })
          }
          .width('100%')
          .height('100%')
          .alignItems(HorizontalAlign.Center)
        }

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
      .opacity(this.displayOpacity)
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
