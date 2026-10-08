import { SCREEN_SAVER_CARD_CATALOG } from '../cards/CardCatalog';
import { ScreenSaverCardHost } from '../cards/CardHost';
import { ScreenSaverGlowButton } from '../common/GlowButton';
import { ScreenSaverLogger } from '../common/Logger';
import { screenSaverAppModel } from '../model/AppModel';
import {
  SCREEN_SAVER_GRID_COLS,
  SCREEN_SAVER_GRID_ROWS,
  ScreenSaverCardInstance,
  ScreenSaverCardMeta,
  ScreenSaverEditorPanelMode,
  ScreenSaverLaunchParam,
  ScreenSaverPageConfig
} from '../model/ConfigModels';
import { ScreenSaverClockSettingsPanel } from './sheets/ClockSettingsSheet';
import { ScreenSaverPhotoSettingsPanel } from './sheets/PhotoSettingsSheet';

const SCREEN_SAVER_DRAG_TRIGGER_DISTANCE: number = 10;

@ComponentV2
export struct ScreenSaverEditorPage {
  @Param navStack: NavPathStack = new NavPathStack();
  @Param pageIndex: number = 0;

  @Local selectedCardId: string = '';
  @Local panelMode: ScreenSaverEditorPanelMode = 'none';
  @Local dragCardId: string = '';
  @Local dragOffsetX: number = 0;
  @Local dragOffsetY: number = 0;
  @Local pinchCardId: string = '';
  @Local pinchScale: number = 1;

  private gridW: number = 0;
  private gridH: number = 0;

  private currentPage(): ScreenSaverPageConfig {
    return screenSaverAppModel.appConfig.pages[this.pageIndex];
  }

  private selectedCardOrDefault(): ScreenSaverCardInstance {
    const card = this.currentPage().cards.find((item: ScreenSaverCardInstance): boolean =>
    item.id === this.selectedCardId);
    return card !== undefined ? card : new ScreenSaverCardInstance();
  }

  private selectCard(cardId: string): void {
    this.selectedCardId = cardId;
    this.panelMode = 'ops';
  }

  private closePanel(): void {
    this.selectedCardId = '';
    this.panelMode = 'none';
  }

  private deleteSelected(): void {
    screenSaverAppModel.removeCard(this.pageIndex, this.selectedCardId);
    this.closePanel();
  }

  private moveSelected(deltaCol: number, deltaRow: number): void {
    const moved = screenSaverAppModel.moveCard(this.pageIndex, this.selectedCardId, deltaCol, deltaRow);
    if (!moved) {
      this.toast('该方向已到边界或与其它卡片重叠');
    }
  }

  private resizeSelected(deltaColSpan: number, deltaRowSpan: number): void {
    const resized = screenSaverAppModel.resizeCard(this.pageIndex, this.selectedCardId, deltaColSpan, deltaRowSpan);
    if (!resized) {
      this.toast('尺寸不可用：已到边界或与其它卡片重叠');
    }
  }

  private addCard(meta: ScreenSaverCardMeta): void {
    const added = screenSaverAppModel.addCard(this.pageIndex, meta.cardType, meta.defaultColSpan, meta.defaultRowSpan);
    if (!added) {
      this.toast('没有足够空位，请先删除或缩小已有卡片');
      return;
    }
    this.panelMode = 'none';
  }

  private openSettingsPanel(): void {
    const card = this.selectedCardOrDefault();
    if (card.cardType === 'photo') {
      this.panelMode = 'photo';
    } else {
      this.panelMode = 'clock';
    }
  }

  private beginDrag(cardId: string): void {
    this.dragCardId = cardId;
    this.dragOffsetX = 0;
    this.dragOffsetY = 0;
    this.selectCard(cardId);
  }

  private updateDrag(cardId: string, offsetX: number, offsetY: number): void {
    if (this.dragCardId !== cardId) {
      return;
    }
    this.dragOffsetX = offsetX;
    this.dragOffsetY = offsetY;
  }

  private commitDrag(cardId: string): void {
    const offsetX = this.dragOffsetX;
    const offsetY = this.dragOffsetY;
    this.dragOffsetX = 0;
    this.dragOffsetY = 0;
    this.dragCardId = '';
    if (this.gridW <= 0 || this.gridH <= 0) {
      return;
    }
    const cellWidth = this.gridW / SCREEN_SAVER_GRID_COLS;
    const cellHeight = this.gridH / SCREEN_SAVER_GRID_ROWS;
    const deltaCol = Math.round(offsetX / cellWidth);
    const deltaRow = Math.round(offsetY / cellHeight);
    if (deltaCol === 0 && deltaRow === 0) {
      return;
    }
    const moved = screenSaverAppModel.moveCard(this.pageIndex, cardId, deltaCol, deltaRow);
    if (!moved) {
      this.toast('目标位置不可用（越界或与其它卡片重叠）');
    }
  }

  private beginPinch(cardId: string): void {
    this.pinchCardId = cardId;
    this.pinchScale = 1;
    this.selectCard(cardId);
  }

  private updatePinch(cardId: string, scale: number): void {
    if (this.pinchCardId !== cardId) {
      return;
    }
    this.pinchScale = Math.max(0.5, Math.min(3, scale));
  }

  private commitPinch(cardId: string): void {
    const scale = this.pinchScale;
    this.pinchScale = 1;
    this.pinchCardId = '';
    if (Math.abs(scale - 1) < 0.1) {
      return;
    }
    const card = this.currentPage().cards.find((item: ScreenSaverCardInstance): boolean => item.id === cardId);
    if (card === undefined) {
      return;
    }
    const targetColSpan = Math.round(card.colSpan * scale);
    const targetRowSpan = Math.round(card.rowSpan * scale);
    const resized = screenSaverAppModel.resizeCardTo(this.pageIndex, cardId, targetColSpan, targetRowSpan);
    if (!resized) {
      this.toast('缩放尺寸不可用（越界或与其它卡片重叠）');
    }
  }

  private toast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message, duration: 1500 });
    } catch (err) {
      const error = err as Error;
      ScreenSaverLogger.warn(`showToast failed: ${error.message}`);
    }
  }

  build() {
    NavDestination() {
      Column() {
        Row() {
          ScreenSaverGlowButton({
            label: '返回',
            textColor: '#CCCCCC',
            glowColor: '#4A9EFF',
            hPadding: 14,
            onTap: (): void => {
              this.navStack.pop();
            }
          })
          Text(this.currentPage().name)
            .fontSize(16)
            .fontColor('#F2F2F2')
            .margin({ left: 12 })
          Blank()
          Text('拖动卡片移动位置 · 双指捏合缩放尺寸')
            .fontSize(11)
            .fontColor('#777777')
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: 8 })

        Grid() {
          ForEach(this.currentPage().cards, (card: ScreenSaverCardInstance) => {
            GridItem() {
              Stack() {
                ScreenSaverCardHost({
                  card: card,
                  cardMode: 'edit',
                  pageIndex: this.pageIndex,
                  cardActive: true
                })
                if (card.id === this.selectedCardId) {
                  Column()
                    .width('100%')
                    .height('100%')
                    .border({ width: 2, color: '#4A9EFF', style: BorderStyle.Solid, radius: 6 })
                }
              }
              .width('100%')
              .height('100%')
              .borderRadius(6)
              .clip(true)
              .scale({
                x: card.id === this.pinchCardId ? this.pinchScale : 1,
                y: card.id === this.pinchCardId ? this.pinchScale : 1
              })
              .offset({
                x: card.id === this.dragCardId ? this.dragOffsetX : 0,
                y: card.id === this.dragCardId ? this.dragOffsetY : 0
              })
              .onClick((): void => {
                this.selectCard(card.id);
              })
              .gesture(PanGesture({ fingers: 1, distance: SCREEN_SAVER_DRAG_TRIGGER_DISTANCE })
                .onActionStart((): void => {
                  this.beginDrag(card.id);
                })
                .onActionUpdate((event: GestureEvent): void => {
                  this.updateDrag(card.id, event.offsetX, event.offsetY);
                })
                .onActionEnd((): void => {
                  this.commitDrag(card.id);
                }))
              .gesture(PinchGesture({ fingers: 2 })
                .onActionStart((): void => {
                  this.beginPinch(card.id);
                })
                .onActionUpdate((event: GestureEvent): void => {
                  this.updatePinch(card.id, event.scale);
                })
                .onActionEnd((): void => {
                  this.commitPinch(card.id);
                }))
            }
            .rowStart(card.rowStart)
            .rowEnd(card.rowStart + card.rowSpan - 1)
            .columnStart(card.colStart)
            .columnEnd(card.colStart + card.colSpan - 1)
            .zIndex(card.id === this.dragCardId ? 10 : 1)
          }, (card: ScreenSaverCardInstance): string => card.id)
        }
        .columnsTemplate('1fr 1fr 1fr 1fr')
        .rowsTemplate('1fr 1fr 1fr 1fr 1fr 1fr')
        .width('100%')
        .layoutWeight(1)
        .backgroundColor(this.currentPage().ambientColor)
        .onAreaChange((oldArea: Area, newArea: Area): void => {
          this.gridW = typeof newArea.width === 'number' ? newArea.width : 0;
          this.gridH = typeof newArea.height === 'number' ? newArea.height : 0;
        })

        Column({ space: 8 }) {
          if (this.panelMode === 'none') {
            Row() {
              Text('点击卡片进行编辑')
                .fontSize(13)
                .fontColor('#777777')
              Blank()
              ScreenSaverGlowButton({
                label: '＋ 添加卡片',
                textColor: '#FFFFFF',
                baseColor: '#3D6FBF',
                glowColor: '#5B87D9',
                hPadding: 14,
                btnHeight: 30,
                onTap: (): void => {
                  this.panelMode = 'add';
                }
              })
              ScreenSaverGlowButton({
                label: '启动预览',
                textColor: '#8AB4F8',
                glowColor: '#4A9EFF',
                hPadding: 14,
                btnHeight: 30,
                marginLeft: 8,
                onTap: (): void => {
                  const param: ScreenSaverLaunchParam = { from: 'editor' };
                  this.navStack.pushPathByName('screensaver', param);
                }
              })
            }
            .width('100%')
          } else if (this.panelMode === 'add') {
            Row() {
              Text('选择卡片类型')
                .fontSize(14)
                .fontColor('#F2F2F2')
              Blank()
              ScreenSaverGlowButton({
                label: '取消',
                textColor: '#999999',
                fontSize: 12,
                btnHeight: 26,
                hPadding: 12,
                onTap: (): void => {
                  this.panelMode = 'none';
                }
              })
            }
            .width('100%')
            ForEach(SCREEN_SAVER_CARD_CATALOG, (meta: ScreenSaverCardMeta) => {
              Row() {
                Column() {
                  Text(meta.displayName)
                    .fontSize(14)
                    .fontColor('#F2F2F2')
                  Text(meta.description)
                    .fontSize(11)
                    .fontColor('#888888')
                    .margin({ top: 2 })
                }
                .alignItems(HorizontalAlign.Start)
                Blank()
                Text('添加')
                  .fontSize(13)
                  .fontColor('#8AB4F8')
              }
              .width('100%')
              .padding(12)
              .borderRadius(8)
              .backgroundColor('#1C1C20')
              .onClick((): void => {
                this.addCard(meta);
              })
            }, (meta: ScreenSaverCardMeta): string => meta.cardType)
          } else if (this.panelMode === 'ops') {
            Row() {
              Text('卡片操作')
                .fontSize(14)
                .fontColor('#F2F2F2')
              Blank()
              ScreenSaverGlowButton({
                label: '取消选择',
                textColor: '#999999',
                fontSize: 12,
                btnHeight: 26,
                hPadding: 12,
                onTap: (): void => {
                  this.closePanel();
                }
              })
            }
            .width('100%')
            Row({ space: 8 }) {
              ScreenSaverGlowButton({
                label: '删除',
                textColor: '#E6A6A6',
                glowColor: '#E67A7A',
                weight: 1,
                btnHeight: 34,
                onTap: (): void => {
                  this.deleteSelected();
                }
              })
              ScreenSaverGlowButton({
                label: '卡片设置',
                textColor: '#FFFFFF',
                baseColor: '#3D6FBF',
                glowColor: '#5B87D9',
                weight: 1,
                btnHeight: 34,
                onTap: (): void => {
                  this.openSettingsPanel();
                }
              })
            }
            .width('100%')
            Row({ space: 8 }) {
              ScreenSaverGlowButton({
                label: '宽 －',
                textColor: '#DDDDDD',
                weight: 1,
                onTap: (): void => {
                  this.resizeSelected(-1, 0);
                }
              })
              ScreenSaverGlowButton({
                label: '宽 ＋',
                textColor: '#DDDDDD',
                weight: 1,
                onTap: (): void => {
                  this.resizeSelected(1, 0);
                }
              })
              ScreenSaverGlowButton({
                label: '高 －',
                textColor: '#DDDDDD',
                weight: 1,
                onTap: (): void => {
                  this.resizeSelected(0, -1);
                }
              })
              ScreenSaverGlowButton({
                label: '高 ＋',
                textColor: '#DDDDDD',
                weight: 1,
                onTap: (): void => {
                  this.resizeSelected(0, 1);
                }
              })
            }
            .width('100%')
            Row({ space: 8 }) {
              ScreenSaverGlowButton({
                label: '↑ 上',
                textColor: '#DDDDDD',
                weight: 1,
                onTap: (): void => {
                  this.moveSelected(0, -1);
                }
              })
              ScreenSaverGlowButton({
                label: '↓ 下',
                textColor: '#DDDDDD',
                weight: 1,
                onTap: (): void => {
                  this.moveSelected(0, 1);
                }
              })
              ScreenSaverGlowButton({
                label: '← 左',
                textColor: '#DDDDDD',
                weight: 1,
                onTap: (): void => {
                  this.moveSelected(-1, 0);
                }
              })
              ScreenSaverGlowButton({
                label: '→ 右',
                textColor: '#DDDDDD',
                weight: 1,
                onTap: (): void => {
                  this.moveSelected(1, 0);
                }
              })
            }
            .width('100%')
          } else if (this.panelMode === 'clock') {
            ScreenSaverClockSettingsPanel({
              card: this.selectedCardOrDefault(),
              onDone: (): void => {
                this.panelMode = 'ops';
              }
            })
          } else if (this.panelMode === 'photo') {
            ScreenSaverPhotoSettingsPanel({
              card: this.selectedCardOrDefault(),
              onDone: (): void => {
                this.panelMode = 'ops';
              }
            })
          }
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: 12 })
        .backgroundColor('#141417')
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#0E0E10')
    }
    .hideTitleBar(true)
    .backgroundColor('#0E0E10')
  }
}
