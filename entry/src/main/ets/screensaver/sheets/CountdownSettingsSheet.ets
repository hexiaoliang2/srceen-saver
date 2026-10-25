import {
  ScreenSaverChip,
  ScreenSaverDeleteCardRow,
  ScreenSaverSheetHeader,
  ScreenSaverToggleRow,
} from '../../common/SheetParts';
import { SCREEN_SAVER_COLORS } from '../../common/ScreenSaverStyle';
import { ScreenSaverLogger } from '../../common/Logger';
import { screenSaverAppModel, screenSaverGenerateId } from '../../model/AppModel';
import { ScreensaverCountdownCard } from '../../cards/CountdownCardView';
import {
  ScreensaverCardInstance,
  ScreensaverCustomCountdown,
} from '../../model/ConfigModels';
import {
  screenSaverDateFromKey,
  screenSaverMonthDayChineseLabel
} from '../../common/DateFormats';
import { screenSaverHolidayStore, ScreensaverHolidayStore } from '../../model/CountdownViewModel';

@ComponentV2
export struct ScreenSaverCountdownSettingsPanel {
  @Param card: ScreensaverCardInstance = new ScreensaverCardInstance();
  @Event onDone: () => void = (): void => {};
  @Event onDelete: () => void = (): void => {};

  @Local draftName: string = '';
  @Local draftDate: string = '';
  @Local draftYearly: boolean = false;
  @Local editingId: string = '';
  @Local statusText: string = '';
  @Local previewToken: number = 0;
  @Local private saving: boolean = false;
  @Local private holidayStore: ScreensaverHolidayStore = screenSaverHolidayStore;

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

  /** 来源切换：在线/自动时允许立即拉一次（用户明确操作）。 */
  private selectSource(source: string): void {
    if (source === 'auto' || source === 'online' || source === 'custom') {
      this.card.countdown.source = source;
      screenSaverAppModel.save();
      if (source !== 'custom') {
        void this.holidayStore.ensureCoverage(false);
      }
    }
  }

  private refreshOnline(): void {
    if (this.card.countdown.source === 'custom') {
      this.statusText = '当前为“仅自定义”，不会请求在线数据';
      return;
    }
    this.statusText = '刷新中…';
    void this.holidayStore.ensureCoverage(true);
  }

  /**
   * 新增/更新自定义倒数日。
   * 关键修复（缺陷「编辑后保存失败」）：
   *   1. 编辑按原 id 替换，不新增记录；
   *   2. 保存后 await flush()，确认真正落盘才清空表单；
   *   3. 落盘失败回滚内存并明确提示，不用 try-catch 吞掉；
   *   4. previewToken++ 强制刷新同面板内的预览（V2 嵌套数组观察兜底）。
   */
  private async saveCustom(): Promise<void> {
    if (this.saving) {
      return;
    }
    const name = this.draftName.trim();
    const date = this.draftDate.trim();
    if (name.length === 0) {
      this.statusText = '请填写名称';
      this.toast(this.statusText);
      return;
    }
    if (name.length > 30) {
      this.statusText = '名称最多 30 字';
      this.toast(this.statusText);
      return;
    }
    if (screenSaverDateFromKey(date) === undefined) {
      this.statusText = '日期格式应为 YYYY-MM-DD';
      this.toast(this.statusText);
      return;
    }
    const wasEditing = this.editingId.length > 0;
    const previous = this.card.countdown.customItems;
    let next: ScreensaverCustomCountdown[] = [];
    if (wasEditing) {
      let found = false;
      for (const item of previous) {
        if (item.id === this.editingId) {
          const updated: ScreensaverCustomCountdown = {
            id: item.id,
            name: name,
            date: date,
            yearly: this.draftYearly
          };
          next.push(updated);
          found = true;
        } else {
          next.push(item);
        }
      }
      if (!found) {
        this.statusText = '记录不存在，请取消编辑后重试';
        this.toast(this.statusText);
        return;
      }
    } else {
      if (previous.length >= 30) {
        this.statusText = '最多 30 个自定义倒数日';
        this.toast(this.statusText);
        return;
      }
      const item: ScreensaverCustomCountdown = {
        id: screenSaverGenerateId('cd'),
        name: name,
        date: date,
        yearly: this.draftYearly
      };
      next = previous.concat([item]);
    }
    this.saving = true;
    this.card.countdown.customItems = next;
    this.previewToken = this.previewToken + 1;
    this.statusText = '保存中…';
    const saved = await screenSaverAppModel.flush();
    this.saving = false;
    if (!saved) {
      this.card.countdown.customItems = previous;
      this.previewToken = this.previewToken + 1;
      this.statusText = '保存失败，请重试';
      this.toast(this.statusText);
      return;
    }
    this.editingId = '';
    this.draftName = '';
    this.draftDate = '';
    this.draftYearly = false;
    this.statusText = wasEditing ? '已更新' : '已添加';
    this.toast(this.statusText);
  }

  private editCustom(item: ScreensaverCustomCountdown): void {
    this.editingId = item.id;
    this.draftName = item.name;
    this.draftDate = item.date;
    this.draftYearly = item.yearly;
    this.statusText = '编辑中';
  }

  private async deleteCustom(itemId: string): Promise<void> {
    const previous = this.card.countdown.customItems;
    const next: ScreensaverCustomCountdown[] = [];
    for (const item of previous) {
      if (item.id !== itemId) {
        next.push(item);
      }
    }
    this.card.countdown.customItems = next;
    this.previewToken = this.previewToken + 1;
    if (this.editingId === itemId) {
      this.editingId = '';
      this.draftName = '';
      this.draftDate = '';
      this.draftYearly = false;
    }
    const saved = await screenSaverAppModel.flush();
    if (!saved) {
      this.card.countdown.customItems = previous;
      this.previewToken = this.previewToken + 1;
      this.statusText = '删除失败，请重试';
      this.toast(this.statusText);
      return;
    }
    this.statusText = '已删除';
  }

  private dataReadTime(): string {
    const text = this.holidayStore.dataReadTimeText();
    return text.length > 0 ? `数据读取时间：${text}` : '尚未读取在线数据';
  }

  /** 当前真正生效的来源（不是用户选的模式，而是实际降级结果）。 */
  private effectiveSourceText(): string {
    if (this.card.countdown.source === 'custom') {
      return '当前生效来源：仅自定义（不请求在线数据）';
    }
    if (this.holidayStore.state === 'error') {
      return '当前生效来源：自定义（在线假期不可用，已降级）';
    }
    if (this.holidayStore.state === 'offline') {
      return '当前生效来源：在线缓存 + 自定义（在线刷新失败）';
    }
    if (this.holidayStore.state === 'idle' || this.holidayStore.state === 'loading') {
      return '当前生效来源：正在加载在线假期…';
    }
    return this.card.countdown.source === 'online' ?
      '当前生效来源：在线假期（来源 B）' :
      '当前生效来源：在线假期（来源 B）+ 自定义（来源 C）';
  }

  /** 刷新状态：结合 Store 的实时 state，避免“刷新中…”永远不结束。 */
  private refreshStatusText(): string {
    if (this.statusText === '刷新中…') {
      if (this.holidayStore.state === 'success') {
        return '在线数据已更新';
      }
      if (this.holidayStore.state === 'offline') {
        return '在线请求失败，正在显示缓存';
      }
      if (this.holidayStore.state === 'error') {
        return '在线数据暂不可用';
      }
      return '刷新中…';
    }
    return this.statusText;
  }

  @Builder
  customRow(item: ScreensaverCustomCountdown) {
    Row({ space: 6 }) {
      Column({ space: 1 }) {
        Text(item.name)
          .fontSize(13)
          .fontColor(SCREEN_SAVER_COLORS.textPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Text(`${screenSaverMonthDayChineseLabel(item.date, true)}${item.yearly ? ' · 每年' : ' · 一次性'}`)
          .fontSize(10)
          .fontColor(SCREEN_SAVER_COLORS.textTertiary)
          .maxLines(1)
          .width('100%')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      Text('编辑')
        .fontSize(11)
        .fontColor(SCREEN_SAVER_COLORS.accent)
        .padding({ left: 6, right: 6, top: 4, bottom: 4 })
        .onClick((): void => {
          this.editCustom(item);
        })
      Text('×')
        .fontSize(15)
        .fontColor(SCREEN_SAVER_COLORS.danger)
        .padding({ left: 6, right: 2, top: 4, bottom: 4 })
        .onClick((): void => {
          void this.deleteCustom(item.id);
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
            ScreensaverCountdownCard({
              card: this.card,
              cardMode: 'edit',
              cardActive: false,
              previewToken: this.previewToken,
              onRequestConfig: (): void => {
                this.toast('当前已在倒计时卡片配置中');
              }
            })
          }
          .width('100%')
          .height(120)
          .borderRadius(8)
          .backgroundColor(SCREEN_SAVER_COLORS.cardBg)
          .clip(true)

          // ---------- 来源选择 ----------
          Column({ space: 6 }) {
            Text('数据来源')
              .fontSize(14)
              .fontColor('#CCCCCC')
              .width('100%')
            Row({ space: 8 }) {
              ScreenSaverChip({
                label: '自动',
                selected: this.card.countdown.source === 'auto',
                onTap: (): void => {
                  this.selectSource('auto');
                }
              })
              ScreenSaverChip({
                label: '仅在线',
                selected: this.card.countdown.source === 'online',
                onTap: (): void => {
                  this.selectSource('online');
                }
              })
              ScreenSaverChip({
                label: '仅自定义',
                selected: this.card.countdown.source === 'custom',
                onTap: (): void => {
                  this.selectSource('custom');
                }
              })
            }
            .width('100%')
            Text(this.effectiveSourceText())
              .fontSize(11)
              .fontColor(SCREEN_SAVER_COLORS.textPrimary)
              .width('100%')
            Text('系统日历（来源 A）：本项目取证确认只读权限无法读取系统日历 App 的日程，' +
              '已降级到在线假期（来源 B）；自定义条目（来源 C）始终可用。')
              .fontSize(10)
              .fontColor(SCREEN_SAVER_COLORS.textTertiary)
              .width('100%')
            Text('在线源仅提供已公布的法定假期与调休补班，不含节气/纪念日；' +
              '次年放假安排公布前不会出现次年条目。')
              .fontSize(10)
              .fontColor(SCREEN_SAVER_COLORS.textTertiary)
              .width('100%')
          }
          .width('100%')

          // ---------- 在线数据状态/刷新 ----------
          Row({ space: 8 }) {
            ScreenSaverChip({
              label: '刷新在线数据',
              onTap: (): void => {
                this.refreshOnline();
              }
            })
            Text(this.dataReadTime())
              .fontSize(10)
              .fontColor(SCREEN_SAVER_COLORS.textTertiary)
              .layoutWeight(1)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .width('100%')
          if (this.refreshStatusText().length > 0) {
            Text(this.refreshStatusText())
              .fontSize(11)
              .fontColor(SCREEN_SAVER_COLORS.textTertiary)
              .width('100%')
          }

          // ---------- 自定义倒数日 ----------
          Column({ space: 6 }) {
            Row() {
              Text('自定义倒数日')
                .fontSize(14)
                .fontColor('#CCCCCC')
              Blank()
              Text(`${this.card.countdown.customItems.length}/30`)
                .fontSize(10)
                .fontColor(SCREEN_SAVER_COLORS.textTertiary)
            }
            .width('100%')
            if (this.card.countdown.customItems.length === 0) {
              Text('尚未添加；添加后与在线条目同权参与最近日期竞争')
                .fontSize(10)
                .fontColor(SCREEN_SAVER_COLORS.textTertiary)
                .width('100%')
            } else {
              Column() {
                ForEach(this.card.countdown.customItems, (item: ScreensaverCustomCountdown) => {
                  this.customRow(item)
                }, (item: ScreensaverCustomCountdown): string =>
                `${item.id}-${item.name}-${item.date}-${item.yearly}`)
              }
              .width('100%')
              .padding({ left: 10, right: 10, top: 2, bottom: 2 })
              .borderRadius(8)
              .backgroundColor(SCREEN_SAVER_COLORS.bgElevated)
            }
            TextInput({ text: this.draftName, placeholder: '名称（最多 30 字）' })
              .type(InputType.Normal)
              .fontSize(13)
              .fontColor(SCREEN_SAVER_COLORS.textPrimary)
              .placeholderColor(SCREEN_SAVER_COLORS.textTertiary)
              .backgroundColor(SCREEN_SAVER_COLORS.divider)
              .height(36)
              .maxLength(30)
              .width('100%')
              .onChange((value: string): void => {
                this.draftName = value;
              })
            TextInput({ text: this.draftDate, placeholder: '日期 YYYY-MM-DD，例如 2027-01-01' })
              .type(InputType.Normal)
              .fontSize(13)
              .fontColor(SCREEN_SAVER_COLORS.textPrimary)
              .placeholderColor(SCREEN_SAVER_COLORS.textTertiary)
              .backgroundColor(SCREEN_SAVER_COLORS.divider)
              .height(36)
              .maxLength(10)
              .width('100%')
              .onChange((value: string): void => {
                this.draftDate = value;
              })
            ScreenSaverToggleRow({
              label: '每年重复',
              tip: '关闭 = 一次性倒数日；已过去的一次性日期不再显示',
              isOn: this.draftYearly,
              onChange: (value: boolean): void => {
                this.draftYearly = value;
              }
            })
            Row({ space: 8 }) {
              ScreenSaverChip({
                label: this.editingId.length > 0 ? '保存修改' : '添加倒数日',
                onTap: (): void => {
                  void this.saveCustom();
                }
              })
              if (this.editingId.length > 0) {
                ScreenSaverChip({
                  label: '取消编辑',
                  onTap: (): void => {
                    this.editingId = '';
                    this.draftName = '';
                    this.draftDate = '';
                    this.draftYearly = false;
                    this.statusText = '';
                  }
                })
              }
            }
            .width('100%')
          }
          .width('100%')

          Text('在线数据缓存用于断网兜底；同一天内重复进入屏保不重复请求。')
            .fontSize(11)
            .fontColor(SCREEN_SAVER_COLORS.textTertiary)
            .width('100%')
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
