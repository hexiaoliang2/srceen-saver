/**
 * =============================================================================
 * 应用入口卡片视图（EntryCardView.ets，需求 A）
 * =============================================================================
 *
 * 【这个文件是干什么的】
 * 一个「只做跳转」的卡片：显示用户自己填写的名称/副标题，点击时用官方
 * `UIAbilityContext.openLink` 打开用户填写的链接。
 *
 * 【为什么是「空壳卡片」而不是内容卡片】
 * QQ音乐 / 抖音 / 小红书等第三方内容没有面向三方应用的公开内容接口，
 * 抓取/逆向都违反平台协议（详见 docs/card-feasibility.md）。因此这里
 * 只实现「跳转」这一被官方文档支持的合法能力：
 *   - 不内置任何第三方名称、图标、链接（全部由用户填写）；
 *   - 不展示、不缓存任何第三方内容。
 *
 * 【打开失败怎么办】
 * openLink 抛错（未安装目标应用、链接不可用、scheme 未在 querySchemes 中声明等）
 * 时统一给降级文案，绝不静默失败。
 * =============================================================================
 */

import { common } from '@kit.AbilityKit';
import { ScreenSaverLogger } from '../common/Logger';
import { screenSaverOpenLink } from '../common/AppLinkLauncher';
import { screenSaverResolveDensity } from './CardCatalog';
import { ScreensaverCardDensity, ScreensaverCardInstance, ScreensaverCardMode } from '../model/ConfigModels';

@ComponentV2
export struct ScreensaverEntryCard {
  @Param card: ScreensaverCardInstance = new ScreensaverCardInstance();
  @Param cardMode: ScreensaverCardMode = 'play';

  /** 当前尺寸对应的内容密度档（尺寸矩阵查表）。 */
  private density(): ScreensaverCardDensity {
    return screenSaverResolveDensity(this.card.cardType, this.card.colSpan, this.card.rowSpan);
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

  /** 名称首字（极简档用，1×1 放不下完整名称）。 */
  private initial(): string {
    const name = this.card.entry.displayName;
    if (name.length === 0) {
      return '—';
    }
    return name.substring(0, 1);
  }

  /**
   * 打开链接：与「屏保态单击卡片」「设置面板测试打开」共用同一个
   * AppLinkLauncher 实现（变更项 2 要求覆盖该卡片的所有点击路径）。
   */
  private async openTarget(): Promise<void> {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext | undefined;
    if (context === undefined) {
      this.toast('无法获取应用上下文');
      return;
    }
    const result = await screenSaverOpenLink(context, this.card.entry.link);
    if (!result.ok) {
      this.toast(result.reason);
    }
  }

  /** 点击「打开」按钮才跳转（按钮自带 onClick，点它不会连带触发卡片选中）。 */
  private handleTap(): void {
    if (this.cardMode !== 'edit') {
      return;
    }
    void this.openTarget();
  }

  build() {
    Column({ space: 2 }) {
      if (this.card.entry.displayName.length === 0) {
        Text(this.density() === 'minimal' ? '入口' : '未配置入口')
          .fontSize(this.density() === 'minimal' ? 10 : 12)
          .fontColor('#8C8C8C')
          .maxLines(1)
      } else if (this.density() === 'minimal') {
        // 1×1：只放首字（放不下按钮，跳转请在更大的尺寸或设置面板里操作）
        Text(this.initial())
          .fontSize(22)
          .fontColor('#F2F2F2')
          .fontWeight(FontWeight.Medium)
          .maxLines(1)
      } else {
        Text(this.card.entry.displayName)
          .fontSize(this.density() === 'compact' ? 13 : 15)
          .fontColor('#F2F2F2')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.card.entry.subtitle.length > 0) {
          Text(this.card.entry.subtitle)
            .fontSize(11)
            .fontColor('#8C8C8C')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        // 编辑态才显示「打开」：播放态保持屏保纯净（触摸穿透）。
        // 注意：这里刻意不用「整卡可点」——整卡的 onClick 会吞掉卡片的
        // 「单击选中」，与编辑态选中模型冲突（缺陷 1 的同一类问题）。
        if (this.cardMode === 'edit') {
          Text('打开')
            .fontSize(11)
            .fontColor('#4A9EFF')
            .padding({ left: 12, right: 12, top: 4, bottom: 4 })
            .borderRadius(6)
            .backgroundColor('#26262B')
            .margin({ top: 4 })
            .onClick((): void => {
              this.handleTap();
            })
        }
      }
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .padding({ left: 8, right: 8, top: 6, bottom: 6 })
  }
}
