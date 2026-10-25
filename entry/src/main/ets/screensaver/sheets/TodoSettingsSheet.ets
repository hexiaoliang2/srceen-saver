import {
  ScreenSaverChip,
  ScreenSaverDeleteCardRow,
  ScreenSaverSheetHeader,
  ScreenSaverSizePresetRow,
  screenSaverResizeFeedbackText
} from '../../common/SheetParts';
import { SCREEN_SAVER_COLORS } from '../../common/ScreenSaverStyle';
import { ScreenSaverLogger } from '../../common/Logger';
import { screenSaverAppModel } from '../../model/AppModel';
import { ScreensaverTodoCard } from '../../cards/TodoCardView';
import { screenSaverSizePresets } from '../../cards/CardCatalog';
import { ScreensaverCardInstance, ScreensaverSizePreset, ScreensaverTodoItem } from '../../model/ConfigModels';
import {
  screenSaverTodoAdd,
  screenSaverTodoClearDone,
  screenSaverTodoMove,
  screenSaverTodoRemove,
  screenSaverTodoSummary,
  screenSaverTodoToggle
} from '../../model/TodoViewModel';

@ComponentV2
export struct ScreenSaverTodoSettingsPanel {
  @Param card: ScreensaverCardInstance = new ScreensaverCardInstance();
  @Event onDone: () => void = (): void => {};
  @Event onDelete: () => void = (): void => {};

  @Local draft: string = '';
  @Local statusText: string = '';

  private panelTitle(): string {
    return `${screenSaverAppModel.cardInstanceTitle(this.card)} · 设置`;
  }

  private toast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message, duration: 1500 });
    } catch (err) {
      const error = err as Error;
      ScreenSaverLogger.warn(`toast failed: ${error.message}`);
    }
  }

  /** 新增：限长 60 字；成功清空输入；失败给明确原因。 */
  private addItem(): void {
    const error = screenSaverTodoAdd(this.card.todo, this.draft);
    if (error.length > 0) {
      this.statusText = error;
      return;
    }
    this.draft = '';
    this.statusText = '已添加';
    screenSaverAppModel.save();
  }

  /** 勾选/取消。复制一次数组，确保卡片列表的 @Monitor 能感知变化。 */
  private toggleItem(itemId: string): void {
    screenSaverTodoToggle(this.card.todo, itemId);
    this.card.todo.items = this.card.todo.items.slice();
    screenSaverAppModel.save();
    void screenSaverAppModel.flush();
  }

  private removeItem(itemId: string): void {
    screenSaverTodoRemove(this.card.todo, itemId);
    screenSaverAppModel.save();
  }

  private moveItem(itemId: string, delta: number): void {
    const moved = screenSaverTodoMove(this.card.todo, itemId, delta);
    if (!moved) {
      this.toast('已到边界');
      return;
    }
    screenSaverAppModel.save();
  }

  private clearDone(): void {
    screenSaverTodoClearDone(this.card.todo);
    screenSaverAppModel.save();
    this.statusText = '已清除完成项';
  }

  private applySizePreset(preset: ScreensaverSizePreset): void {
    const outcome = screenSaverAppModel.resizeCardToDetailed(this.card.id, preset.colSpan, preset.rowSpan);
    const message = screenSaverResizeFeedbackText(outcome);
    if (message.length > 0) {
      this.toast(message);
    }
  }

  private countText(): string {
    const summary = screenSaverTodoSummary(this.card.todo);
    return `未完成 ${summary.open} / 共 ${summary.total}`;
  }

  @Builder
  todoEditorRow(item: ScreensaverTodoItem) {
    Row({ space: 8 }) {
      Toggle({ type: ToggleType.Checkbox, isOn: item.completed })
        .selectedColor(SCREEN_SAVER_COLORS.accentStrong)
        .onChange((value: boolean): void => {
          if (value !== item.completed) {
            this.toggleItem(item.id);
          }
        })
      Text(item.text)
        .fontSize(13)
        .fontColor(item.completed ? SCREEN_SAVER_COLORS.textTertiary : SCREEN_SAVER_COLORS.textPrimary)
        .decoration({
          type: item.completed ? TextDecorationType.LineThrough : TextDecorationType.None,
          color: SCREEN_SAVER_COLORS.textTertiary
        })
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
      Text('↑')
        .fontSize(14)
        .fontColor('#AAAAAA')
        .padding({ left: 6, right: 6, top: 4, bottom: 4 })
        .onClick((): void => {
          this.moveItem(item.id, -1);
        })
      Text('↓')
        .fontSize(14)
        .fontColor('#AAAAAA')
        .padding({ left: 6, right: 6, top: 4, bottom: 4 })
        .onClick((): void => {
          this.moveItem(item.id, 1);
        })
      Text('×')
        .fontSize(15)
        .fontColor(SCREEN_SAVER_COLORS.danger)
        .padding({ left: 6, right: 2, top: 4, bottom: 4 })
        .onClick((): void => {
          this.removeItem(item.id);
        })
    }
    .width('100%')
    .padding({ top: 4, bottom: 4 })
    .alignItems(VerticalAlign.Center)
  }

  build() {
    Column() {
      ScreenSaverSheetHeader({
        title: this.panelTitle(),
        onDone: (): void => {
          this.onDone();
        }
      })
      .padding({ left: 16, right: 16 })

      Scroll() {
        Column({ space: 12 }) {
          // ---------- 实时预览 ----------
          Column() {
            ScreensaverTodoCard({
              card: this.card,
              cardMode: 'edit',
              cardActive: false,
              onRequestConfig: (): void => {
                this.toast('当前已在待办卡片配置中');
              }
            })
          }
          .width('100%')
          .height(120)
          .borderRadius(8)
          .backgroundColor(SCREEN_SAVER_COLORS.cardBg)
          .clip(true)

          // ---------- 新增 ----------
          Row({ space: 8 }) {
            TextInput({ text: this.draft, placeholder: '新增待办（最多 60 字）' })
              .type(InputType.Normal)
              .fontSize(13)
              .fontColor(SCREEN_SAVER_COLORS.textPrimary)
              .placeholderColor(SCREEN_SAVER_COLORS.textTertiary)
              .backgroundColor(SCREEN_SAVER_COLORS.divider)
              .height(36)
              .maxLength(60)
              .layoutWeight(1)
              .onChange((value: string): void => {
                this.draft = value;
              })
              .onSubmit((): void => {
                this.addItem();
              })
            ScreenSaverChip({
              label: '添加',
              onTap: (): void => {
                this.addItem();
              }
            })
          }
          .width('100%')

          Row() {
            Text(this.countText())
              .fontSize(11)
              .fontColor(SCREEN_SAVER_COLORS.textTertiary)
            Blank()
            if (this.statusText.length > 0) {
              Text(this.statusText)
                .fontSize(11)
                .fontColor(SCREEN_SAVER_COLORS.textTertiary)
                .maxLines(1)
            }
          }
          .width('100%')

          // ---------- 条目编辑 ----------
          if (this.card.todo.items.length === 0) {
            Text('暂无待办，添加第一条')
              .fontSize(12)
              .fontColor(SCREEN_SAVER_COLORS.textTertiary)
              .width('100%')
          } else {
            Column() {
              ForEach(this.card.todo.items, (item: ScreensaverTodoItem) => {
                this.todoEditorRow(item)
              }, (item: ScreensaverTodoItem): string => item.id)
            }
            .width('100%')
            .padding({ left: 10, right: 10, top: 4, bottom: 4 })
            .borderRadius(8)
            .backgroundColor(SCREEN_SAVER_COLORS.bgElevated)
          }

          Row({ space: 8 }) {
            ScreenSaverChip({
              label: '清除已完成',
              onTap: (): void => {
                this.clearDone();
              }
            })
            Text('屏保态可点圆勾选；排序/删除在此面板')
              .fontSize(10)
              .fontColor(SCREEN_SAVER_COLORS.textTertiary)
              .layoutWeight(1)
          }
          .width('100%')

          Text('零权限 · 仅本机存储 · 随卡片实例持久化（数据版本 v2）')
            .fontSize(11)
            .fontColor(SCREEN_SAVER_COLORS.textTertiary)
            .width('100%')

          ScreenSaverSizePresetRow({
            presets: screenSaverSizePresets('todo'),
            currentCols: this.card.colSpan,
            currentRows: this.card.rowSpan,
            onPick: (preset: ScreensaverSizePreset): void => {
              this.applySizePreset(preset);
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
