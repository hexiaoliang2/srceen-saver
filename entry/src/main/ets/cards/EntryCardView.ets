/**
 * =============================================================================
 * 应用入口卡片视图（EntryCardView.ets）
 * =============================================================================
 *
 * 【本轮改造】
 *   1. 内容组（图标 + 名称 + 副标题）锚点固定为卡片内容区的几何中心：
 *      整组用 Column / Row + justifyContent(Center) + alignItems(Center)，
 *      不使用任何条件 top 偏移或条件 padding。
 *   2. 1×1 / 2×1 / 1×2 三档都显示「图标 + 名称（1 行）+ 副标题（1 行）」，
 *      各自省略号截断、不折行；1×1 名称 14fp、副标题 10fp（硬性下限）。
 *   3. ≥2×2 不再渲染「打开」按钮；播放态由屏保页把整卡点击分发到
 *      AppLinkLauncher（热区 = 整卡）。卡片自身提供按下态反馈（透明度/缩放，
 *      非动画常驻）。
 *   4. 自定义图标：entry.iconUri 指向沙箱文件；文件丢失/解码失败时
 *      onError 或启动校验会回退到「名称首字」中性图标，不空白不崩溃。
 *
 * 【图标尺寸比例】
 *   图标直径 = clamp(内容区短边 × 0.34, 28, 120)vp；1×1 额外放宽到 0.42
 *   （仍低于建议上限 45%），因为 1×1 只有图标+两行文字，图标太小会显得空。
 *   实际比例随 onAreaChange 实测（见交付文档逐档表）。
 * =============================================================================
 */

import { ScreenSaverLogger } from '../common/Logger';
import { screenSaverCardPalette, screenSaverTextShadow, ScreensaverCardPalette } from '../common/CardTheme';
import { SCREEN_SAVER_FONT } from '../common/CardTypography';
import { screenSaverEntryIconUsable } from '../common/EntryIconStore';
import { screenSaverPresetAppById, ScreensaverPresetApp } from '../model/EntryPresets';
import { ScreensaverCardInstance, ScreensaverCardMode, ScreensaverInkTone } from '../model/ConfigModels';

@ComponentV2
export struct ScreensaverEntryCard {
  @Param card: ScreensaverCardInstance = new ScreensaverCardInstance();
  @Param cardMode: ScreensaverCardMode = 'play';
  @Param cardTone: ScreensaverInkTone = 'light';
  @Param cardHalo: boolean = false;

  /** 自定义图标文件不可读/解码失败 → 回退中性图标。 */
  @Local private iconBroken: boolean = false;
  /** 按下态（非按钮式反馈；不是常驻动画）。 */
  @Local private pressed: boolean = false;
  /** 内容区实测尺寸（去掉内边距后的 vp）。 */
  @Local private contentW: number = 0;
  @Local private contentH: number = 0;
  /** 内容组（图标+名称+副标题）实测包围盒，用于交付文档的占比实测。 */
  @Local private groupW: number = 0;
  @Local private groupH: number = 0;
  private lastRatioLog: string = '';

  private palette(): ScreensaverCardPalette {
    return screenSaverCardPalette(this.cardTone);
  }

  private textShadow(): ShadowOptions {
    return screenSaverTextShadow(this.cardHalo, this.palette().halo);
  }

  aboutToAppear(): void {
    const uri = this.card.entry.iconUri;
    this.iconBroken = uri.length > 0 && !screenSaverEntryIconUsable(uri);
    if (this.iconBroken) {
      ScreenSaverLogger.warn(`entry icon unusable, fallback to initial: ${uri}`);
    }
  }

  /** 换图标后重新尝试渲染（新文件正常时不再走兜底）。 */
  @Monitor('card.entry.iconUri')
  onIconUriChanged(): void {
    const uri = this.card.entry.iconUri;
    this.iconBroken = uri.length > 0 && !screenSaverEntryIconUsable(uri);
  }

  /** 1 列宽：竖向排列（1×1 / 1×2 / 1×3 / 1×4）。 */
  private vertical(): boolean {
    return this.card.colSpan <= 1;
  }

  /** 1×1 专用（最小可用字号 + 最小间距）。 */
  private oneByOne(): boolean {
    return this.card.colSpan <= 1 && this.card.rowSpan <= 1;
  }

  /** 宽扁条（2×1/3×1/4×1）。 */
  private wideFlat(): boolean {
    return this.card.rowSpan <= 1 && this.card.colSpan >= 2;
  }

  /** 预设应用（thirdparty / system）；url 或数据损坏时返回 undefined。 */
  private preset(): ScreensaverPresetApp | undefined {
    if (this.card.entry.targetType === 'url') {
      return undefined;
    }
    return screenSaverPresetAppById(this.card.entry.presetId);
  }

  /** 预设应用但还没选目标（或历史数据损坏）。 */
  private presetMissing(): boolean {
    return this.card.entry.targetType !== 'url' && this.card.entry.presetId.length === 0;
  }

  private displayName(): string {
    if (this.presetMissing()) {
      return '未选择应用';
    }
    const name = this.card.entry.displayName.trim();
    if (name.length > 0) {
      return name;
    }
    const preset = this.preset();
    if (preset !== undefined) {
      return preset.name;
    }
    return this.card.entry.targetType === 'url' ? '未配置入口' : '未选择应用';
  }

  private initial(): string {
    const name = this.displayName();
    return name.length > 0 ? name.substring(0, 1) : '—';
  }

  /** 副标题：四种状态各自给诚实的文案（保证所有档位都有一行副标题）。 */
  private subtitleText(): string {
    if (this.card.entry.targetType !== 'url' && this.card.entry.invalid) {
      // 1×1 只有一行 10fp 副标题：截短保证「应用不可用」完整可见。
      return this.oneByOne() ? '应用不可用' : '应用不可用 · 请重选';
    }
    const subtitle = this.card.entry.subtitle.trim();
    if (subtitle.length > 0) {
      return subtitle;
    }
    if (this.presetMissing()) {
      return '点击设置 · 选择应用';
    }
    const preset = this.preset();
    if (preset !== undefined) {
      return preset.subtitle;
    }
    return this.card.entry.link.trim().length > 0 ? '点击打开' : '未配置链接';
  }

  /** 失效态的副标题用提示色；其他状态保持三级文字色。 */
  private subtitleColor(): string {
    if (this.card.entry.targetType !== 'url' && this.card.entry.invalid) {
      return this.palette().entryInvalid;
    }
    return this.palette().textTertiary;
  }

  /** 名称字号：1×1 用 L5；2×1/1×2 用 L4；宽扁 3×1+ 用 L3；≥2×2 用 L1。 */
  private nameFont(): number {
    if (this.oneByOne()) {
      return SCREEN_SAVER_FONT.L5;
    }
    if (this.wideFlat()) {
      return this.card.colSpan >= 3 ? SCREEN_SAVER_FONT.L3 : SCREEN_SAVER_FONT.L4;
    }
    if (this.vertical()) {
      return SCREEN_SAVER_FONT.L4;
    }
    return SCREEN_SAVER_FONT.L1;
  }

  /** 副标题字号：1×1 用 10fp 下限；其余按可用档位。 */
  private subtitleFont(): number {
    if (this.oneByOne()) {
      return SCREEN_SAVER_FONT.L7;
    }
    if (this.vertical() || this.wideFlat()) {
      return SCREEN_SAVER_FONT.L6;
    }
    return SCREEN_SAVER_FONT.L4;
  }

  private textGap(): number {
    return this.oneByOne() ? 1 : 2;
  }

  private paddingSize(): number {
    return this.oneByOne() ? 4 : 6;
  }

  /** 内容区短边（实测优先；未量到时按 90vp 单元格估算）。 */
  private shortSide(): number {
    const fallbackW = this.card.colSpan * 90 - this.paddingSize() * 2;
    const fallbackH = this.card.rowSpan * 90 - this.paddingSize() * 2;
    const width = this.contentW > 0 ? this.contentW : Math.max(40, fallbackW);
    const height = this.contentH > 0 ? this.contentH : Math.max(40, fallbackH);
    return Math.min(width, height);
  }

  /** 图标直径：1×1 用短边 42%（≤45%），其余 34%；夹在 28~120vp。 */
  private iconSize(): number {
    const ratio = this.oneByOne() ? 0.42 : 0.34;
    const raw = Math.round(this.shortSide() * ratio);
    if (raw < 28) {
      return 28;
    }
    if (raw > 120) {
      return 120;
    }
    return raw;
  }

  private hasCustomIcon(): boolean {
    return this.card.entry.iconUri.length > 0 && !this.iconBroken;
  }

  /** 记录内容组包围盒 / 内容区面积（交付文档 §2.2 的实测值来源）。 */
  private refreshGroupRatio(width: number, height: number): void {
    this.groupW = width;
    this.groupH = height;
    if (this.contentW <= 0 || this.contentH <= 0 || width <= 0 || height <= 0) {
      return;
    }
    const ratio = Math.round((width * height) / (this.contentW * this.contentH) * 1000) / 10;
    const key = `${this.card.colSpan}x${this.card.rowSpan}|${Math.round(width)}x${Math.round(height)}|${ratio}`;
    if (key === this.lastRatioLog) {
      return;
    }
    this.lastRatioLog = key;
    ScreenSaverLogger.info(`entry group ratio ${this.card.colSpan}x${this.card.rowSpan}: ` +
      `group=${Math.round(width)}x${Math.round(height)} content=${Math.round(this.contentW)}x` +
      `${Math.round(this.contentH)} ratio=${ratio}% icon=${this.iconSize()}`);
  }

  /**
   * 文字列最大宽度：
   *   竖向布局 = 内容区宽度；横向布局 = 内容区宽度 - 图标 - 间距。
   * 用 constraintSize 限制文字，而不是 layoutWeight——layoutWeight 会把
   * 文字列撑满剩余宽度，图标就被推到左侧，内容组不再整体居中。
   */
  private textMaxWidth(): number {
    const fallbackW = this.card.colSpan * 90 - this.paddingSize() * 2;
    const width = this.contentW > 0 ? this.contentW : Math.max(40, fallbackW);
    if (this.vertical()) {
      return width;
    }
    const gap = this.wideFlat() ? 8 : 12;
    return Math.max(40, width - this.iconSize() - gap);
  }

  /** 中性图标：圆角方块 + 名称首字（自定义图标失效时的唯一兜底）。 */
  @Builder
  neutralIcon(size: number) {
    Column() {
      Text(this.initial())
        .fontSize(Math.max(SCREEN_SAVER_FONT.L7, Math.round(size * 0.42)))
        .fontColor(this.palette().iconInitial)
        .fontWeight(FontWeight.Medium)
        .maxLines(1)
    }
    .width(size)
    .height(size)
    .borderRadius(size * 0.24)
    .backgroundColor(this.palette().iconTints[this.iconPaletteIndex()])
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  /** 由名称稳定派生色相（同一名称永远同一颜色）。 */
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

  @Builder
  iconView() {
    if (this.hasCustomIcon()) {
      Image(this.card.entry.iconUri)
        .width(this.iconSize())
        .height(this.iconSize())
        .objectFit(ImageFit.Cover)
        .borderRadius(this.iconSize() * 0.24)
        .onError((): void => {
          this.iconBroken = true;
          ScreenSaverLogger.warn(`entry custom icon render failed: ${this.card.entry.iconUri}`);
        })
    } else {
      this.neutralIcon(this.iconSize())
    }
  }

  @Builder
  titleColumn() {
    Column({ space: this.textGap() }) {
      Text(this.displayName())
        .fontSize(this.nameFont())
        .fontColor(this.oneByOne() || this.wideFlat() ? this.palette().textSecondary :
        this.palette().textPrimary)
        .fontWeight(FontWeight.Medium)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(this.vertical() ? TextAlign.Center : TextAlign.Start)
        .textShadow(this.textShadow())
      Text(this.subtitleText())
        .fontSize(this.subtitleFont())
        .fontColor(this.subtitleColor())
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(this.vertical() ? TextAlign.Center : TextAlign.Start)
        .textShadow(this.textShadow())
    }
    .alignItems(this.vertical() ? HorizontalAlign.Center : HorizontalAlign.Start)
    .constraintSize({ maxWidth: this.textMaxWidth() })
  }

  build() {
    Column() {
      if (this.vertical()) {
        Column({ space: this.oneByOne() ? 2 : 6 }) {
          this.iconView()
          this.titleColumn()
        }
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .onAreaChange((oldArea: Area, newArea: Area): void => {
          const width = typeof newArea.width === 'number' ? newArea.width : 0;
          const height = typeof newArea.height === 'number' ? newArea.height : 0;
          this.refreshGroupRatio(width, height);
        })
      } else {
        Row({ space: this.wideFlat() ? 8 : 12 }) {
          this.iconView()
          this.titleColumn()
        }
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .onAreaChange((oldArea: Area, newArea: Area): void => {
          const width = typeof newArea.width === 'number' ? newArea.width : 0;
          const height = typeof newArea.height === 'number' ? newArea.height : 0;
          this.refreshGroupRatio(width, height);
        })
      }
    }
    .width('100%')
    .height('100%')
    .padding(this.paddingSize())
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .opacity(this.pressed ? 0.62 : 1)
    .scale({
      x: this.pressed ? 0.97 : 1,
      y: this.pressed ? 0.97 : 1
    })
    .onAreaChange((oldArea: Area, newArea: Area): void => {
      const width = typeof newArea.width === 'number' ? newArea.width : 0;
      const height = typeof newArea.height === 'number' ? newArea.height : 0;
      this.contentW = Math.max(0, width - this.paddingSize() * 2);
      this.contentH = Math.max(0, height - this.paddingSize() * 2);
    })
    .onTouch((event: TouchEvent): void => {
      if (event.type === TouchType.Down) {
        this.pressed = true;
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.pressed = false;
      }
    })
  }
}
