/**
 * =============================================================================
 * 应用入口卡片设置面板（EntrySettingsSheet.ets，需求 A）
 * =============================================================================
 *
 * 目标类型三选一：
 *   · 网页链接：用户填名称 + 链接（历史数据默认落在这一档）；
 *   · 第三方应用：只能从内置 6 个预设里选，先 canOpenLink 判断是否可拉起；
 *   · 系统应用：只能从内置 5 个预设里选，显式 Want 拉起，可选备用链接。
 *
 * 【合规边界】
 *   · 不读取、不枚举已安装应用列表；第三方可用性只回答清单内 scheme 是否可处理；
 *   · 不上传任何数据；图标只存应用沙箱；
 *   · 系统应用按产品确认不做预安装检测，拉起失败由卡片进入失效态并提示重选。
 * =============================================================================
 */

import { common } from '@kit.AbilityKit';
import {
  ScreenSaverChip,
  ScreenSaverDeleteCardRow,
  ScreenSaverSheetHeader,
} from '../../common/SheetParts';
import { SCREEN_SAVER_COLORS } from '../../common/ScreenSaverStyle';
import { ScreenSaverLogger } from '../../common/Logger';
import { screenSaverImportEntryIcon, screenSaverRemoveEntryIcon } from '../../common/EntryIconStore';
import { screenSaverAppModel } from '../../model/AppModel';
import { ScreensaverEntryCard } from '../../cards/EntryCardView';
import {
  screenSaverPresetApps,
  screenSaverPresetAppById,
  screenSaverPresetAppSelectable,
  ScreensaverPresetApp
} from '../../model/EntryPresets';
import {
  SCREEN_SAVER_ENTRY_DATA_VERSION,
  ScreensaverCardInstance,
  ScreensaverEntryTargetType,
} from '../../model/ConfigModels';

@ComponentV2
export struct ScreenSaverEntrySettingsPanel {
  @Param card: ScreensaverCardInstance = new ScreensaverCardInstance();
  @Event onDone: () => void = (): void => {};
  @Event onDelete: () => void = (): void => {};

  /** 当前类型（与 card.entry.targetType 同步；@Local 驱动列表切换）。 */
  @Local typeDraft: ScreensaverEntryTargetType = 'url';
  /** 第三方可用性：与 thirdparty 预设清单下标一一对应。 */
  @Local thirdPartyAvailable: boolean[] = [];
  /** 输入草稿（点「完成」/回车时才写回卡片，避免每敲一个字符就落盘）。 */
  @Local nameDraft: string = '';
  @Local linkDraft: string = '';
  @Local subtitleDraft: string = '';
  @Local iconStatusText: string = '';
  @Local iconBusy: boolean = false;
  /** 选图看门狗：系统选择器异常不返回时，30s 后恢复按钮可点，避免卡在「处理中」。 */
  private iconPickToken: number = 0;
  private iconWatchdog: number = -1;

  aboutToAppear(): void {
    this.typeDraft = this.card.entry.targetType;
    this.nameDraft = this.card.entry.displayName;
    this.linkDraft = this.card.entry.link;
    this.subtitleDraft = this.card.entry.subtitle;
    this.refreshThirdPartyAvailability();
  }

  aboutToDisappear(): void {
    if (this.iconWatchdog >= 0) {
      clearTimeout(this.iconWatchdog);
      this.iconWatchdog = -1;
    }
  }

  /** 探测清单内第三方应用是否可拉起（canOpenLink；不枚举应用列表）。 */
  private refreshThirdPartyAvailability(): void {
    const apps = screenSaverPresetApps('thirdparty');
    const availability: boolean[] = [];
    for (const app of apps) {
      availability.push(screenSaverPresetAppSelectable(app));
    }
    this.thirdPartyAvailable = availability;
  }

  /** 面板标题：带实例标识，便于核对面板归属哪张卡片。 */
  private panelTitle(): string {
    return `${screenSaverAppModel.cardInstanceTitle(this.card)} · 设置`;
  }

  /** 把草稿写回卡片并持久化（只写当前类型可见的字段）。 */
  private applyDrafts(): void {
    if (this.card.entry.targetType === 'url') {
      this.card.entry.displayName = this.nameDraft.trim();
    }
    if (this.card.entry.targetType !== 'thirdparty') {
      this.card.entry.link = this.linkDraft.trim();
    }
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

  /** 切换目标类型（保留 url 的名称/链接草稿，只清理不匹配的预设字段）。 */
  private selectType(type: ScreensaverEntryTargetType): void {
    if (type === this.card.entry.targetType) {
      return;
    }
    const currentPreset = screenSaverPresetAppById(this.card.entry.presetId);
    const keepPreset = type !== 'url' && currentPreset !== undefined && currentPreset.kind === type;
    this.card.entry.targetType = type;
    this.card.entry.version = SCREEN_SAVER_ENTRY_DATA_VERSION;
    this.card.entry.invalid = false;
    this.card.entry.lastFailureAt = 0;
    this.card.entry.failureCount = 0;
    if (!keepPreset) {
      this.card.entry.presetId = '';
      this.card.entry.scheme = '';
      this.card.entry.bundleName = '';
      this.card.entry.abilityName = '';
    }
    this.typeDraft = type;
    this.nameDraft = this.card.entry.displayName;
    this.linkDraft = this.card.entry.link;
    this.subtitleDraft = this.card.entry.subtitle;
    screenSaverAppModel.save();
  }

  /** 选中预设应用：把静态清单里的启动参数写进卡片并持久化。 */
  private selectPreset(app: ScreensaverPresetApp): void {
    this.card.entry.targetType = app.kind;
    this.card.entry.version = SCREEN_SAVER_ENTRY_DATA_VERSION;
    this.card.entry.presetId = app.id;
    this.card.entry.displayName = app.name;
    this.card.entry.subtitle = app.subtitle;
    this.card.entry.scheme = app.scheme;
    this.card.entry.bundleName = app.bundleName;
    this.card.entry.abilityName = app.abilityName;
    this.card.entry.invalid = false;
    this.card.entry.lastFailureAt = 0;
    this.card.entry.failureCount = 0;
    this.typeDraft = app.kind;
    this.nameDraft = app.name;
    this.subtitleDraft = app.subtitle;
    screenSaverAppModel.save();
    ScreenSaverLogger.info(`entry preset selected: ${app.id}`);
  }

  /** 预设行是否可选：系统应用始终可选；第三方按 canOpenLink 结果。 */
  private presetSelectable(app: ScreensaverPresetApp, index: number): boolean {
    if (app.kind === 'system') {
      return true;
    }
    return index < this.thirdPartyAvailable.length ? this.thirdPartyAvailable[index] : false;
  }

  /**
   * 选择自定义图标：系统 PhotoViewPicker（免权限）→ 格式/大小校验 →
   * 384px 方形居中裁剪 → 沙箱 PNG → 持久化 file:// 路径。
   */
  private async pickCustomIcon(): Promise<void> {
    if (this.iconBusy) {
      return;
    }
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext | undefined;
    if (context === undefined) {
      this.iconStatusText = '无法获取应用上下文';
      return;
    }
    this.applyDrafts();
    this.iconBusy = true;
    this.iconStatusText = '处理中…';
    this.iconPickToken = this.iconPickToken + 1;
    const token = this.iconPickToken;
    this.iconWatchdog = setTimeout((): void => {
      this.iconWatchdog = -1;
      if (token === this.iconPickToken && this.iconBusy) {
        this.iconBusy = false;
        this.iconStatusText = '选择已取消或超时，已保留原图标';
      }
    }, 30000);
    const previous = this.card.entry.iconUri;
    const result = await screenSaverImportEntryIcon(context.filesDir, this.card.id);
    if (this.iconWatchdog >= 0) {
      clearTimeout(this.iconWatchdog);
      this.iconWatchdog = -1;
    }
    if (token !== this.iconPickToken) {
      return;
    }
    this.iconBusy = false;
    if (!result.ok) {
      this.iconStatusText = result.reason;
      return;
    }
    this.card.entry.iconUri = result.uri;
    screenSaverAppModel.save();
    if (previous.length > 0 && previous !== result.uri) {
      screenSaverRemoveEntryIcon(previous);
    }
    this.iconStatusText = '图标已更新（重启后仍生效）';
    this.toast(this.iconStatusText);
  }

  /** 恢复默认图标（名称首字），并删除沙箱文件。 */
  private restoreDefaultIcon(): void {
    const previous = this.card.entry.iconUri;
    if (previous.length === 0) {
      this.iconStatusText = '当前已是默认图标';
      return;
    }
    this.card.entry.iconUri = '';
    screenSaverAppModel.save();
    screenSaverRemoveEntryIcon(previous);
    this.iconStatusText = '已恢复默认图标';
    this.toast(this.iconStatusText);
  }

  @Builder
  typeChip(label: string, type: ScreensaverEntryTargetType) {
    ScreenSaverChip({
      label: label,
      selected: this.typeDraft === type,
      onTap: (): void => {
        this.selectType(type);
      }
    })
  }

  @Builder
  presetRow(app: ScreensaverPresetApp, index: number) {
    Row({ space: 10 }) {
      Column() {
        Text(app.name.substring(0, 1))
          .fontSize(15)
          .fontColor(SCREEN_SAVER_COLORS.textPrimary)
          .fontWeight(FontWeight.Medium)
      }
      .width(34)
      .height(34)
      .borderRadius(9)
      .backgroundColor(SCREEN_SAVER_COLORS.divider)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)

      Column({ space: 2 }) {
        Text(app.name)
          .fontSize(14)
          .fontColor(SCREEN_SAVER_COLORS.textPrimary)
          .maxLines(1)
        Text(this.presetSelectable(app, index) ? app.subtitle : '未安装 · 暂不可选')
          .fontSize(10)
          .fontColor(SCREEN_SAVER_COLORS.textTertiary)
          .maxLines(1)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      if (this.card.entry.targetType === app.kind && this.card.entry.presetId === app.id) {
        Text('已选')
          .fontSize(12)
          .fontColor(SCREEN_SAVER_COLORS.accent)
      } else if (this.presetSelectable(app, index)) {
        Text('选择')
          .fontSize(12)
          .fontColor(SCREEN_SAVER_COLORS.accent)
      }
    }
    .width('100%')
    .padding({ left: 10, right: 10, top: 8, bottom: 8 })
    .borderRadius(10)
    .backgroundColor(this.card.entry.targetType === app.kind && this.card.entry.presetId === app.id ?
      SCREEN_SAVER_COLORS.divider : SCREEN_SAVER_COLORS.cardBg)
    .opacity(this.presetSelectable(app, index) ? 1 : 0.45)
    .onClick((): void => {
      if (!this.presetSelectable(app, index)) {
        this.toast('目标应用未安装，暂不可选');
        return;
      }
      this.selectPreset(app);
    })
  }

  /** 预设清单（thirdparty 6 个 / system 5 个）。 */
  @Builder
  presetList() {
    Column({ space: 6 }) {
      Row() {
        Text(this.typeDraft === 'thirdparty' ? '第三方应用' : '系统应用')
          .fontSize(14)
          .fontColor('#CCCCCC')
        Blank()
        Text(this.typeDraft === 'thirdparty' ? '不可用项自动置灰' : '不做预安装检测')
          .fontSize(10)
          .fontColor(SCREEN_SAVER_COLORS.textTertiary)
      }
      .width('100%')

      ForEach(this.presetApps(), (app: ScreensaverPresetApp, index: number): void => {
        this.presetRow(app, index)
      }, (app: ScreensaverPresetApp): string => `${this.typeDraft}_${app.id}`)

      if (this.typeDraft === 'thirdparty' && !this.hasSelectableThirdParty()) {
        Text('未检测到可拉起的第三方应用：清单内应用都未安装。安装后重新打开本面板即可选择。')
          .fontSize(10)
          .fontColor(SCREEN_SAVER_COLORS.textTertiary)
          .width('100%')
      }
    }
    .width('100%')
  }

  private presetApps(): ScreensaverPresetApp[] {
    return screenSaverPresetApps(this.typeDraft);
  }

  private hasSelectableThirdParty(): boolean {
    for (const available of this.thirdPartyAvailable) {
      if (available) {
        return true;
      }
    }
    return false;
  }

  /** 当前选中目标的一句话说明（预览区下方，避免用户不知道点哪个是干嘛的）。 */
  private selectionHint(): string {
    if (this.typeDraft === 'url') {
      return '按你填写的链接打开目标应用/网页；链接由你自行提供。';
    }
    if (this.card.entry.invalid) {
      return '上次拉起失败：目标可能未安装或版本不支持，请重新选择。';
    }
    if (this.card.entry.presetId.length === 0) {
      return '请从下方清单里选择一个目标应用。';
    }
    return this.typeDraft === 'thirdparty' ? '' :
      '系统应用用显式 Want 拉起；失败时会尝试下方备用链接。';
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

          // ---------- 目标类型 ----------
          Column({ space: 6 }) {
            Text('目标类型')
              .fontSize(14)
              .fontColor('#CCCCCC')
              .width('100%')
            Row({ space: 8 }) {
              this.typeChip('网页链接', 'url')
              this.typeChip('第三方应用', 'thirdparty')
              this.typeChip('系统应用', 'system')
            }
            .width('100%')
            if (this.selectionHint().length > 0) {
              Text(this.selectionHint())
                .fontSize(10)
                .fontColor(this.card.entry.invalid ? SCREEN_SAVER_COLORS.danger :
                SCREEN_SAVER_COLORS.textTertiary)
                .width('100%')
            }
          }
          .width('100%')

          // ---------- 目标配置 ----------
          if (this.typeDraft === 'url') {
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
          } else {
            this.presetList()
            if (this.typeDraft === 'system') {
              Column({ space: 6 }) {
                Text('备用链接（可选）')
                  .fontSize(12)
                  .fontColor('#CCCCCC')
                  .width('100%')
                TextInput({ text: this.linkDraft, placeholder: '系统应用拉起失败时尝试打开' })
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
            }
          }

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

          // ---------- 自定义图标（免权限选图；沙箱持久化；可恢复默认） ----------
          Column({ space: 6 }) {
            Row() {
              Text('图标')
                .fontSize(14)
                .fontColor('#CCCCCC')
              Blank()
              Text(this.iconBusy ? '处理中…' : '选择图片')
                .fontSize(13)
                .fontColor(this.iconBusy ? SCREEN_SAVER_COLORS.textTertiary : SCREEN_SAVER_COLORS.accent)
                .onClick((): void => {
                  void this.pickCustomIcon();
                })
              if (this.card.entry.iconUri.length > 0) {
                Text('恢复默认')
                  .fontSize(13)
                  .fontColor(SCREEN_SAVER_COLORS.danger)
                  .margin({ left: 12 })
                  .onClick((): void => {
                    this.restoreDefaultIcon();
                  })
              }
            }
            .width('100%')
            Text(this.iconStatusText.length > 0 ? this.iconStatusText :
              '系统图片选择器，免权限；支持 JPG / PNG / WebP，单张 ≤2MB；' +
              '按最大档位尺寸解码并方形裁剪，只存应用沙箱。')
              .fontSize(10)
              .fontColor(SCREEN_SAVER_COLORS.textTertiary)
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
          }
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
