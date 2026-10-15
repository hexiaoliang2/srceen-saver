/**
 * =============================================================================
 * 应用入口卡片视图（EntryCardView.ets，需求 A + 变更项 6）
 * =============================================================================
 *
 * 【这个文件是干什么的】
 * 一个「只做跳转」的卡片：显示目标 App 的名称与**自绘中性图标**，
 * 点击时用官方 `UIAbilityContext.openLink` 打开用户填写的链接。
 *
 * 【变更项 6：能不能显示目标 App 的真实图标？—— 官方结论：三方应用做不到】
 * 已核实（本地官方文档，核对日期 2026-10-14）：
 *   · 查询**其他**已安装应用的信息（名称/图标）只能走
 *     `bundleManager.getBundleInfo` / `getAllBundleInfo` / `getApplicationInfo`，
 *     这些接口需要 **ohos.permission.GET_BUNDLE_INFO_PRIVILEGED**（系统级权限），
 *     三方应用无法申请（见 FAQ「如何判断应用是否为系统应用」faqs-ability-169）。
 *   · 三方应用可用的只有 `bundleManager.getBundleInfoForSelf`（只能查自己）。
 *   · 「目标应用是否安装」官方可用 `canOpenLink` 判断，但要求目标 scheme
 *     预先声明在 module.json5 的 querySchemes 里（最多 200 个），
 *     而本卡片的链接由用户自由填写，无法预知 scheme，因此不做安装探测
 *     （FAQ「如何判断应用程序是否安装」faqs-ability-142 / faqs-package-structure-62）。
 * 因此按需求改为**降级方案**：
 *   · 图标 = 程序化绘制的**中性图标**（圆角方块 + 名称首字 + 由名称稳定派生的
 *     色相），不含任何第三方商标/图标素材，也不下载、不缓存任何第三方素材；
 *   · 未安装目标应用时：不显示错误图标、不做任何错误提示（屏保态点击失败
 *     只记日志；编辑态「打开」按钮失败才 toast），屏保态规则不变。
 *
 * 【图标加载与缓存策略（变更项 6 要求）】
 * 图标是**纯绘制**的，没有任何图片查询/解码/IO，因此不存在「每次渲染重复查询」
 * 的问题，也就不需要图片缓存；「缓存」体现为：由 displayName 稳定派生的颜色
 * 每次绘制结果完全一致（同一名称永远同一颜色）。若未来系统开放跨应用图标查询，
 * 再在 AppModel 增加 bundleName → icon 的内存 LRU 缓存（当前不可用，不做假实现）。
 *
 * 【尺寸变化时图标如何变化】
 * 图标边长随内容密度档变化：minimal 26vp / compact 34vp / full 40vp，
 * 并且整卡按 GridItem 尺寸等比缩放时图标随容器一起变化（不留固定像素）。
 *
 * 【打开失败怎么办】
 * edit 态「打开」按钮失败 → toast 降级文案（用户正在操作，需要反馈）；
 * play 态（屏保展示态）失败 → 只记日志，不弹提示（屏保态规则不变）。
 * =============================================================================
 */

import { common } from '@kit.AbilityKit';
import { ScreenSaverLogger } from '../common/Logger';
import { screenSaverOpenLink } from '../common/AppLinkLauncher';
import { screenSaverCardPalette, screenSaverTextShadow, ScreensaverCardPalette } from '../common/CardTheme';
import { screenSaverResolveDensity } from './CardCatalog';
import { ScreensaverCardDensity, ScreensaverCardInstance, ScreensaverCardMode,
  ScreensaverInkTone } from '../model/ConfigModels';

@ComponentV2
export struct ScreensaverEntryCard {
  @Param card: ScreensaverCardInstance = new ScreensaverCardInstance();
  @Param cardMode: ScreensaverCardMode = 'play';
  /**
   * 文字/图标墨色档与投影兜底开关（变更项 3.2/3.3/3.4）。
   * 由屏保页统一解析后下发（同一来源）；中性图标随档位切换深浅两套。
   */
  @Param cardTone: ScreensaverInkTone = 'light';
  @Param cardHalo: boolean = false;

  /** 当前墨色档的调色板（文字 + 图标素材版本，同一来源）。 */
  private palette(): ScreensaverCardPalette {
    return screenSaverCardPalette(this.cardTone);
  }

  /** 文字投影参数（halo 关闭时 radius=0 = 不画）。 */
  private textShadow(): ShadowOptions {
    return screenSaverTextShadow(this.cardHalo, this.palette().halo);
  }

  /** 当前尺寸对应的内容密度档（尺寸矩阵查表）。 */
  private density(): ScreensaverCardDensity {
    return screenSaverResolveDensity(this.card.cardType, this.card.colSpan, this.card.rowSpan);
  }

  /** 中性图标边长（vp）：随密度档变化。 */
  private iconSize(): number {
    if (this.density() === 'minimal') {
      return 26;
    }
    return this.density() === 'compact' ? 34 : 40;
  }

  /**
   * 由名称稳定派生一个色相（0~5 档），映射到当前墨色档的 6 档中性配色。
   * 目的：同一名称永远同一颜色（这就是「缓存」），不同入口可相互区分；
   * 颜色全部是本文件/主题文件内的固定色值，不来自任何第三方素材。
   * 深浅两套由 CardTheme 统一维护：浅色档配深色背景、深色档配浅色背景，
   * 每档都满足「图标底色对背景 ≥ 3:1、首字对底色 ≥ 4.5:1」的设计目标。
   */
  private iconPaletteIndex(): number {
    const name = this.card.entry.displayName;
    if (name.length === 0) {
      return 0;
    }
    let hash = 0;
    for (let index = 0; index < name.length; index++) {
      hash = (hash * 31 + name.charCodeAt(index)) % 9973;
    }
    return hash % 6;
  }

  /** 中性图标底色（随墨色档切换深浅两套，见 CardTheme）。 */
  private iconColor(): string {
    return this.palette().iconTints[this.iconPaletteIndex()];
  }

  /** 名称首字（极简档与图标内都用，1×1 放不下完整名称）。 */
  private initial(): string {
    const name = this.card.entry.displayName;
    if (name.length === 0) {
      return '—';
    }
    return name.substring(0, 1);
  }

  /**
   * 自绘中性图标：圆角方块 + 名称首字。
   * 无外部素材、无网络请求、无解码；尺寸随密度档变化，
   * 配色随墨色档切换（可运行时着色，见 CardTheme 的说明）。
   */
  @Builder
  neutralIcon(size: number, fontSize: number) {
    Column() {
      Text(this.initial())
        .fontSize(fontSize)
        .fontColor(this.palette().iconInitial)
        .fontWeight(FontWeight.Medium)
        .maxLines(1)
    }
    .width(size)
    .height(size)
    .borderRadius(size * 0.24)
    .backgroundColor(this.iconColor())
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  /**
   * 打开链接：与「屏保态单击卡片」「设置面板测试打开」共用同一个
   * AppLinkLauncher 实现。
   * showFeedback=true（编辑态按钮）失败给 toast；false（屏保态）只记日志。
   */
  private async openTarget(showFeedback: boolean): Promise<void> {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext | undefined;
    if (context === undefined) {
      this.notifyResult(false, '无法获取应用上下文', showFeedback);
      return;
    }
    const result = await screenSaverOpenLink(context, this.card.entry.link.trim());
    if (!result.ok) {
      this.notifyResult(false, result.reason, showFeedback);
      return;
    }
    ScreenSaverLogger.info(`entry link opened: ${this.card.entry.link}`);
  }

  /** 失败反馈：编辑态 toast，屏保态只记日志（不弹失败提示）。 */
  private notifyResult(ok: boolean, reason: string, showFeedback: boolean): void {
    if (ok) {
      return;
    }
    ScreenSaverLogger.warn(`entry open failed: ${reason}`);
    if (!showFeedback) {
      return;
    }
    try {
      this.getUIContext().getPromptAction().showToast({ message: reason, duration: 1500 });
    } catch (err) {
      const error = err as Error;
      ScreenSaverLogger.warn(`toast failed: ${error.message}`);
    }
  }

  /** 编辑态「打开」按钮：只有编辑态可点（播放态跳转由屏保页统一分发）。 */
  private handleTap(): void {
    if (this.cardMode !== 'edit') {
      return;
    }
    void this.openTarget(true);
  }

  build() {
    Column({ space: 4 }) {
      if (this.card.entry.displayName.length === 0) {
        this.neutralIcon(this.iconSize(), this.density() === 'minimal' ? 13 : 16)
        Text(this.density() === 'minimal' ? '入口' : '未配置入口')
          .fontSize(this.density() === 'minimal' ? 9 : 11)
          .fontColor(this.palette().textTertiary)
          .maxLines(1)
          .textShadow(this.textShadow())
      } else if (this.density() === 'minimal') {
        // 1×1 / 2×1 / 1×2：图标 + 短名（放不下按钮，跳转走屏保态点击或大尺寸）
        this.neutralIcon(26, 13)
        Text(this.card.entry.displayName)
          .fontSize(9)
          .fontColor(this.palette().textSecondary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textShadow(this.textShadow())
      } else {
        Row({ space: 8 }) {
          this.neutralIcon(this.iconSize(), this.density() === 'compact' ? 15 : 18)
          Column({ space: 1 }) {
            Text(this.card.entry.displayName)
              .fontSize(this.density() === 'compact' ? 13 : 15)
              .fontColor(this.palette().textPrimary)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .textShadow(this.textShadow())
            if (this.card.entry.subtitle.length > 0) {
              Text(this.card.entry.subtitle)
                .fontSize(11)
                .fontColor(this.palette().textTertiary)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .textShadow(this.textShadow())
            }
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        // 编辑态才显示「打开」：播放态保持屏保纯净（触摸穿透）。
        if (this.cardMode === 'edit') {
          Text('打开')
            .fontSize(11)
            .fontColor('#4A9EFF')
            .padding({ left: 12, right: 12, top: 4, bottom: 4 })
            .borderRadius(6)
            .backgroundColor('#26262B')
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
