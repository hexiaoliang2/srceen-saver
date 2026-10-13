/**
 * =============================================================================
 * 应用入口卡片设置面板（EntrySettingsSheet.ets，需求 A）
 * =============================================================================
 *
 * 名称 / 链接 / 副标题（全部由用户填写）、测试打开、删除卡片。
 *
 * 【合规边界】
 * 面板里刻意**不预置**任何第三方名称、图标与链接：商标与链接的使用由用户
 * 自行决定，应用只提供「按你填写的链接跳转」这一能力（官方 openLink）。
 * 链接必须是目标应用/平台官方提供的形式，否则打开会失败并给出降级提示。
 * =============================================================================
 */

import { common } from '@kit.AbilityKit';
import {
  ScreenSaverChip,
  ScreenSaverDeleteCardRow,
  ScreenSaverSheetHeader
} from '../../common/SheetParts';
import { SCREEN_SAVER_COLORS } from '../../common/ScreenSaverStyle';
import { ScreenSaverLogger } from '../../common/Logger';
import { screenSaverOpenLink } from '../../common/AppLinkLauncher';
import { screenSaverAppModel } from '../../model/AppModel';
import { ScreensaverEntryCard } from '../../cards/EntryCardView';
import { ScreensaverCardInstance } from '../../model/ConfigModels';

@ComponentV2
export struct ScreenSaverEntrySettingsPanel {
  @Param card: ScreensaverCardInstance = new ScreensaverCardInstance();
  @Event onDone: () => void = (): void => {};
  @Event onDelete: () => void = (): void => {};

  /** 输入草稿（点「完成」/回车时才写回卡片，避免每敲一个字符就落盘）。 */
  @Local nameDraft: string = '';
  @Local linkDraft: string = '';
  @Local subtitleDraft: string = '';
  @Local statusText: string = '';

  aboutToAppear(): void {
    this.nameDraft = this.card.entry.displayName;
    this.linkDraft = this.card.entry.link;
    this.subtitleDraft = this.card.entry.subtitle;
  }

  /** 面板标题：带实例标识，便于核对面板归属哪张卡片。 */
  private panelTitle(): string {
    return `${screenSaverAppModel.cardInstanceTitle(this.card)} · 设置`;
  }

  /** 把草稿写回卡片并持久化。 */
  private applyDrafts(): void {
    this.card.entry.displayName = this.nameDraft.trim();
    this.card.entry.link = this.linkDraft.trim();
    this.card.entry.subtitle = this.subtitleDraft.trim();
    screenSaverAppModel.save();
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

  /**
   * 测试打开：与「屏保态单击卡片」「编辑态卡片上的打开按钮」共用同一个
   * AppLinkLauncher 实现（变更项 2 的「所有点击路径覆盖」）。
   */
  private async testOpen(): Promise<void> {
    this.applyDrafts();
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext | undefined;
    if (context === undefined) {
      this.statusText = '无法获取应用上下文';
      return;
    }
    const result = await screenSaverOpenLink(context, this.card.entry.link);
    if (result.ok) {
      this.statusText = '已发起跳转';
      return;
    }
    this.statusText = result.reason;
    this.toast(result.reason);
  }

  build() {
    Column() {
      ScreenSaverSheetHeader({
        title: this.panelTitle(),
        onDone: (): void => {
          this.applyDrafts();
          this.onDone();
        }
      })
      .padding({ left: 16, right: 16 })

      Scroll() {
        Column({ space: 12 }) {
          // ---------- 实时预览 ----------
          Column() {
            ScreensaverEntryCard({
              card: this.card,
              cardMode: 'edit'
            })
          }
          .width('100%')
          .height(120)
          .borderRadius(8)
          .backgroundColor(SCREEN_SAVER_COLORS.cardBg)
          .clip(true)

          // ---------- 名称 ----------
          Row() {
            Text('名称')
              .fontSize(14)
              .fontColor('#CCCCCC')
            Blank()
            TextInput({ text: this.nameDraft, placeholder: '要显示的名字' })
              .type(InputType.Normal)
              .fontSize(13)
              .fontColor(SCREEN_SAVER_COLORS.textPrimary)
              .placeholderColor(SCREEN_SAVER_COLORS.textTertiary)
              .backgroundColor(SCREEN_SAVER_COLORS.divider)
              .width(180)
              .height(36)
              .onChange((value: string): void => {
                this.nameDraft = value;
              })
              .onSubmit((): void => {
                this.applyDrafts();
              })
          }
          .width('100%')

          // ---------- 链接 ----------
          Column({ space: 6 }) {
            Row() {
              Text('链接')
                .fontSize(14)
                .fontColor('#CCCCCC')
              Blank()
              Text('由你填写')
                .fontSize(11)
                .fontColor(SCREEN_SAVER_COLORS.textTertiary)
            }
            .width('100%')
            TextInput({ text: this.linkDraft, placeholder: '目标应用/平台官方提供的链接' })
              .type(InputType.Normal)
              .fontSize(12)
              .fontColor(SCREEN_SAVER_COLORS.textPrimary)
              .placeholderColor(SCREEN_SAVER_COLORS.textTertiary)
              .backgroundColor(SCREEN_SAVER_COLORS.divider)
              .width('100%')
              .height(36)
              .onChange((value: string): void => {
                this.linkDraft = value;
              })
              .onSubmit((): void => {
                this.applyDrafts();
              })
          }
          .width('100%')

          // ---------- 副标题 ----------
          Row() {
            Text('副标题')
              .fontSize(14)
              .fontColor('#CCCCCC')
            Blank()
            TextInput({ text: this.subtitleDraft, placeholder: '可选' })
              .type(InputType.Normal)
              .fontSize(13)
              .fontColor(SCREEN_SAVER_COLORS.textPrimary)
              .placeholderColor(SCREEN_SAVER_COLORS.textTertiary)
              .backgroundColor(SCREEN_SAVER_COLORS.divider)
              .width(180)
              .height(36)
              .onChange((value: string): void => {
                this.subtitleDraft = value;
              })
          }
          .width('100%')

          // ---------- 测试打开 ----------
          Row({ space: 8 }) {
            ScreenSaverChip({
              label: '测试打开',
              onTap: (): void => {
                void this.testOpen();
              }
            })
            if (this.statusText.length > 0) {
              Text(this.statusText)
                .fontSize(11)
                .fontColor(SCREEN_SAVER_COLORS.textTertiary)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)
            }
          }
          .width('100%')

          // ---------- 合规说明 ----------
          Text('本卡片只做跳转：不展示、不缓存第三方内容，也不内置任何第三方名称/图标/链接。' +
            '请在编辑态点击卡片测试跳转；播放态为保持屏保纯净不响应点击。')
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
