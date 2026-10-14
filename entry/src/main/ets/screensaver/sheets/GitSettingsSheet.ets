/**
 * =============================================================================
 * Git 卡片设置面板（GitSettingsSheet.ets）
 * =============================================================================
 *
 * 【这个文件是干什么的】
 * Git 卡片的设置抽屉：用户名、GitHub 访问 token（仅存本机）、
 * 周数、配色（绿/蓝/灰）、断网缓存开关、立即刷新、删除卡片。
 *
 * 【token 的安全设计】
 * - 输入框用 InputType.Password 遮盖显示；
 * - 保存后立即清空输入框（tokenDraft = ''），界面不再回显；
 * - 只存本机（AppModel.setGitToken），不上传、不写入布局文件；
 * - 保存后立刻触发一次数据刷新，让用户马上验证 token 是否有效；
 * - 提供「清除」按钮一键抹掉本机 token。
 *
 * 【用户名的保存时机】
 * 用户名是草稿态（usernameDraft），点「完成」时才 applyUsername() 写回
 * 卡片并持久化——避免每敲一个字符就落盘一次。
 *
 * 【断网缓存】
 * 打开后离线时以灰阶展示上次拉到的数据（GitViewModel 的三重防护之一）。
 * =============================================================================
 */

import {
  ScreenSaverChip,
  ScreenSaverDeleteCardRow,
  ScreenSaverSheetHeader,
  ScreenSaverSizePresetRow,
  ScreenSaverToggleRow,
  screenSaverResizeFeedbackText
} from '../../common/SheetParts';
import { SCREEN_SAVER_COLORS } from '../../common/ScreenSaverStyle';
import { ScreenSaverLogger } from '../../common/Logger';
import { screenSaverAppModel } from '../../model/AppModel';
import { screenSaverGitViewModel } from '../../model/GitViewModel';
import { screenSaverSizePresets } from '../../cards/CardCatalog';
import { ScreensaverGitCard } from '../../cards/GitCardView';
import {
  SCREEN_SAVER_GIT_WEEK_OPTIONS,
  ScreensaverCardInstance,
  ScreensaverSizePreset
} from '../../model/ConfigModels';

interface PaletteOption {
  value: string;
  label: string;
}

/** 贡献格子配色方案（green 是 GitHub 经典绿）。 */
const PALETTE_OPTIONS: PaletteOption[] = [
  { value: 'green', label: '绿' },
  { value: 'blue', label: '蓝' },
  { value: 'gray', label: '灰' }
];

@ComponentV2
export struct ScreenSaverGitSettingsPanel {
  @Param card: ScreensaverCardInstance = new ScreensaverCardInstance();
  @Event onDone: () => void = (): void => {};
  @Event onDelete: () => void = (): void => {};

  /** 用户名输入草稿（点完成才写回卡片）。 */
  @Local usernameDraft: string = '';
  /** token 输入草稿（保存后即清空，不回显）。 */
  @Local tokenDraft: string = '';
  /** token 区域下方的小字提示（如「已保存 token（仅本机）」）。 */
  @Local tokenSavedHint: string = '';

  aboutToAppear(): void {
    // 打开面板时：用户名填入草稿；本机已有 token 则只提示、不回显内容
    this.usernameDraft = this.card.git.username;
    if (screenSaverAppModel.hasGitToken()) {
      this.tokenSavedHint = '已保存 token（仅本机）';
    }
  }

  /**
   * 保存 token：
   * 非空校验 → 存本机（AppModel）→ 清空输入框 → 立刻刷新一次数据，
   * 让用户马上知道 token 好不好使。
   */
  private saveToken(): void {
    const value = this.tokenDraft.trim();
    if (value.length === 0) {
      this.tokenSavedHint = '请输入 token';
      return;
    }
    screenSaverAppModel.setGitToken(value);
    this.tokenDraft = '';
    this.tokenSavedHint = '已保存 token（仅本机）';
    void screenSaverGitViewModel.refresh(this.card.git.username, this.card.git.offlineCache);
  }

  /** 清除本机 token（数据仍可公开访问的用户名可继续免 token 使用）。 */
  private clearToken(): void {
    screenSaverAppModel.setGitToken('');
    this.tokenSavedHint = '已清除本机 token';
  }

  /**
   * 把用户名草稿写回卡片（空值不生效）。
   * 由「完成」按钮和输入框回车触发。
   */
  private applyUsername(): void {
    const value = this.usernameDraft.trim();
    if (value.length === 0) {
      return;
    }
    this.card.git.username = value;
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

  /** 面板标题：带实例标识（如「Git 贡献 · 设置」），便于核对面板归属哪张卡片。 */
  private panelTitle(): string {
    return `${screenSaverAppModel.cardInstanceTitle(this.card)} · 设置`;
  }

  /**
   * 应用尺寸矩阵里的快捷尺寸（走 AppModel.resizeCardToDetailed：吸附 + 碰撞校验
   * + 吸附/占用反馈，变更项 2 通道 A）。
   * Git 卡小于 2×2 时矩阵会降级为「数字摘要」而不是热力图。
   */
  private applySizePreset(preset: ScreensaverSizePreset): void {
    const outcome = screenSaverAppModel.resizeCardToDetailed(this.card.id, preset.colSpan, preset.rowSpan);
    const message = screenSaverResizeFeedbackText(outcome);
    if (message.length > 0) {
      this.toast(message);
    }
  }

  build() {
    Column() {
      // ---------- 顶栏 ----------
      // 点「完成」先把用户名草稿落盘再关面板，避免丢输入。
      ScreenSaverSheetHeader({
        title: this.panelTitle(),
        onDone: (): void => {
          this.applyUsername();
          this.onDone();
        }
      })
      .padding({ left: 16, right: 16 })

      Scroll() {
        Column({ space: 12 }) {
          // ---------- 实时预览 ----------
          // 预览里的「点我配置」被接管为 toast 提示（当前已在配置面板中）。
          Column() {
            ScreensaverGitCard({
              card: this.card,
              cardMode: 'edit',
              cardActive: false,
              onRequestConfig: (): void => {
                this.toast('当前已在 Git 卡片配置中');
              }
            })
          }
          .width('100%')
          .height(120)
          .borderRadius(8)
          .backgroundColor(SCREEN_SAVER_COLORS.cardBg)
          .clip(true)

          // ---------- 用户名 ----------
          Row() {
            Text('用户名')
              .fontSize(14)
              .fontColor('#CCCCCC')
            Blank()
            TextInput({ text: this.usernameDraft, placeholder: 'octocat' })
              .type(InputType.Normal)
              .fontSize(13)
              .fontColor(SCREEN_SAVER_COLORS.textPrimary)
              .placeholderColor(SCREEN_SAVER_COLORS.textTertiary)
              .backgroundColor(SCREEN_SAVER_COLORS.divider)
              .width(180)
              .height(36)
              .onChange((value: string): void => {
                this.usernameDraft = value;
              })
              .onSubmit((): void => {
                this.applyUsername();
              })
          }
          .width('100%')

          // ---------- 访问 token ----------
          // 密码框遮盖 + 保存后清空不回显 + 仅存本机。
          Column({ space: 6 }) {
            Row() {
              Text('访问 token')
                .fontSize(14)
                .fontColor('#CCCCCC')
              Blank()
              Text('仅保存在本机')
                .fontSize(11)
                .fontColor(SCREEN_SAVER_COLORS.textTertiary)
            }
            .width('100%')
            Row({ space: 8 }) {
              TextInput({ text: this.tokenDraft, placeholder: 'GitHub Personal Access Token' })
                .type(InputType.Password)
                .fontSize(13)
                .fontColor(SCREEN_SAVER_COLORS.textPrimary)
                .placeholderColor(SCREEN_SAVER_COLORS.textTertiary)
                .backgroundColor(SCREEN_SAVER_COLORS.divider)
                .layoutWeight(1)
                .height(36)
                .onChange((value: string): void => {
                  this.tokenDraft = value;
                })
              ScreenSaverChip({
                label: '保存',
                onTap: (): void => {
                  this.saveToken();
                }
              })
              ScreenSaverChip({
                label: '清除',
                onTap: (): void => {
                  this.clearToken();
                }
              })
            }
            .width('100%')
            if (this.tokenSavedHint.length > 0) {
              Text(this.tokenSavedHint)
                .fontSize(11)
                .fontColor(SCREEN_SAVER_COLORS.textTertiary)
                .width('100%')
            }
            Text('token 用于调用 GitHub GraphQL 获取贡献日历，不会写入代码或上传；断网时展示本地缓存')
              .fontSize(11)
              .fontColor(SCREEN_SAVER_COLORS.textTertiary)
              .width('100%')
          }
          .width('100%')

          // ---------- 周数 ----------
          Row() {
            Text('周数')
              .fontSize(14)
              .fontColor('#CCCCCC')
            Blank()
            Row({ space: 8 }) {
              ForEach(SCREEN_SAVER_GIT_WEEK_OPTIONS, (weeks: number) => {
                ScreenSaverChip({
                  label: `${weeks}`,
                  selected: this.card.git.weeks === weeks,
                  onTap: (): void => {
                    this.card.git.weeks = weeks;
                    screenSaverAppModel.save();
                  }
                })
              }, (weeks: number): string => `weeks_${weeks}`)
            }
          }
          .width('100%')

          // ---------- 配色 ----------
          Row() {
            Text('配色')
              .fontSize(14)
              .fontColor('#CCCCCC')
            Blank()
            Row({ space: 8 }) {
              ForEach(PALETTE_OPTIONS, (option: PaletteOption) => {
                ScreenSaverChip({
                  label: option.label,
                  selected: this.card.git.palette === option.value,
                  onTap: (): void => {
                    this.card.git.palette = option.value;
                    screenSaverAppModel.save();
                  }
                })
              }, (option: PaletteOption): string => option.value)
            }
          }
          .width('100%')

          // ---------- 尺寸 ----------
          // 预设来自尺寸矩阵；小尺寸会把热力图降级为「总提交数 + 近 7 天迷你条」。
          ScreenSaverSizePresetRow({
            presets: screenSaverSizePresets('git'),
            currentCols: this.card.colSpan,
            currentRows: this.card.rowSpan,
            onPick: (preset: ScreensaverSizePreset): void => {
              this.applySizePreset(preset);
            }
          })

          // ---------- 断网缓存 ----------
          ScreenSaverToggleRow({
            label: '断网显示缓存',
            tip: '离线时以灰阶展示上次数据',
            isOn: this.card.git.offlineCache,
            onChange: (value: boolean): void => {
              this.card.git.offlineCache = value;
              screenSaverAppModel.save();
            }
          })

          // ---------- 立即刷新 ----------
          // 刷新中按钮文字自动变化（GitViewModel.state 是 @ObservedV2）。
          ScreenSaverChip({
            label: screenSaverGitViewModel.state === 'loading' ? '刷新中…' : '立即刷新',
            onTap: (): void => {
              void screenSaverGitViewModel.refresh(this.card.git.username, this.card.git.offlineCache);
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
