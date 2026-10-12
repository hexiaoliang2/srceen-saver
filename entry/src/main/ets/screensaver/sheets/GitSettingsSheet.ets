import {
  ScreenSaverChip,
  ScreenSaverDeleteCardRow,
  ScreenSaverSheetHeader,
  ScreenSaverToggleRow
} from '../../common/SheetParts';
import { SCREEN_SAVER_COLORS } from '../../common/ScreenSaverStyle';
import { ScreenSaverLogger } from '../../common/Logger';
import { screenSaverAppModel } from '../../model/AppModel';
import { screenSaverGitViewModel } from '../../model/GitViewModel';
import { ScreensaverGitCard } from '../../cards/GitCardView';
import { SCREEN_SAVER_GIT_WEEK_OPTIONS, ScreensaverCardInstance } from '../../model/ConfigModels';

interface PaletteOption {
  value: string;
  label: string;
}

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

  @Local usernameDraft: string = '';
  @Local tokenDraft: string = '';
  @Local tokenSavedHint: string = '';

  aboutToAppear(): void {
    this.usernameDraft = this.card.git.username;
    if (screenSaverAppModel.hasGitToken()) {
      this.tokenSavedHint = '已保存 token（仅本机）';
    }
  }

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

  private clearToken(): void {
    screenSaverAppModel.setGitToken('');
    this.tokenSavedHint = '已清除本机 token';
  }

  private applyUsername(): void {
    const value = this.usernameDraft.trim();
    if (value.length === 0) {
      return;
    }
    this.card.git.username = value;
    screenSaverAppModel.save();
  }

  private toast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message, duration: 1500 });
    } catch (err) {
      const error = err as Error;
      ScreenSaverLogger.warn(`toast failed: ${error.message}`);
    }
  }

  build() {
    Column({ space: 12 }) {
      ScreenSaverSheetHeader({
        title: 'Git 卡片',
        onDone: (): void => {
          this.applyUsername();
          this.onDone();
        }
      })

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

      Row() {
        Text('数据源')
          .fontSize(14)
          .fontColor('#CCCCCC')
        Blank()
        ScreenSaverChip({
          label: 'GitHub',
          selected: true
        })
      }
      .width('100%')

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

      ScreenSaverToggleRow({
        label: '断网显示缓存',
        tip: '离线时以灰阶展示上次数据',
        isOn: this.card.git.offlineCache,
        onChange: (value: boolean): void => {
          this.card.git.offlineCache = value;
          screenSaverAppModel.save();
        }
      })

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
    .padding(16)
  }
}
