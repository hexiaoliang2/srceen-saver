import {
  ScreenSaverChip,
  ScreenSaverDeleteCardRow,
  ScreenSaverSheetHeader,
  ScreenSaverToggleRow,
} from '../../common/SheetParts';
import { SCREEN_SAVER_COLORS } from '../../common/ScreenSaverStyle';
import { ScreenSaverLogger } from '../../common/Logger';
import { screenSaverAppModel } from '../../model/AppModel';
import { ScreensaverQuotesCard } from '../../cards/QuotesCardView';
import {
  SCREEN_SAVER_QUOTES_MAX_SYMBOLS,
  screenSaverQuotesChartEligible,
  ScreensaverCardInstance,
  ScreensaverQuoteSymbol,
} from '../../model/ConfigModels';
import {
  screenSaverNormalizeStoredQuote,
  screenSaverParseQuoteInput,
  screenSaverQuoteMarketLabel,
  screenSaverValidateQuoteCode
} from '../../model/QuoteSymbols';
import { screenSaverRequestQuotesRefresh } from '../../model/QuotesViewModel';
import { screenSaverFormatStamp } from '../../common/DateFormats';

@ComponentV2
export struct ScreenSaverQuotesSettingsPanel {
  @Param card: ScreensaverCardInstance = new ScreensaverCardInstance();
  @Event onDone: () => void = (): void => {};
  @Event onDelete: () => void = (): void => {};

  /** 6 位代码输入草稿（只接受数字；回车/添加即入列表）。 */
  @Local codeDraft: string = '';
  @Local statusText: string = '';
  @Local draftError: string = '';

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

  /** 已保存的标的里是否已有同一 query（旧格式先归一化再比较）。 */
  private isDuplicate(symbol: ScreensaverQuoteSymbol): boolean {
    for (const query of this.card.quotes.symbols) {
      const existing = screenSaverNormalizeStoredQuote(query);
      if (existing !== undefined && existing.query === symbol.query) {
        return true;
      }
    }
    return false;
  }

  /** 输入过程校验：位数/非数字/市场/重复各给明确文案。 */
  private validateDraft(): string {
    const value = this.codeDraft.trim();
    if (value.length === 0) {
      return '';
    }
    const error = screenSaverValidateQuoteCode(value);
    if (error.length > 0) {
      return error;
    }
    const parsed = screenSaverParseQuoteInput(value);
    if (parsed.ok && this.isDuplicate(parsed.symbol)) {
      return '该代码已添加';
    }
    return '';
  }

  private onCodeChanged(value: string): void {
    this.codeDraft = value;
    this.draftError = this.validateDraft();
    this.statusText = this.draftError;
  }

  /**
   * 添加当前草稿。
   * allowEmpty=true 用于面板「完成」：没输入时直接放行；
   * showToast=true 用于显式点「添加」/「立即刷新」。
   */
  private addSymbol(showToast: boolean, allowEmpty: boolean): boolean {
    const raw = this.codeDraft.trim();
    if (raw.length === 0) {
      if (allowEmpty) {
        return true;
      }
      this.draftError = '请输入 6 位数字';
      this.statusText = this.draftError;
      if (showToast) {
        this.toast(this.statusText);
      }
      return false;
    }
    const parsed = screenSaverParseQuoteInput(raw);
    if (!parsed.ok) {
      this.draftError = parsed.error;
      this.statusText = this.draftError;
      if (showToast) {
        this.toast(this.statusText);
      }
      return false;
    }
    if (this.isDuplicate(parsed.symbol)) {
      this.draftError = '该代码已添加';
      this.statusText = this.draftError;
      if (showToast) {
        this.toast(this.statusText);
      }
      return false;
    }
    if (this.card.quotes.symbols.length >= SCREEN_SAVER_QUOTES_MAX_SYMBOLS) {
      this.draftError = `最多 ${SCREEN_SAVER_QUOTES_MAX_SYMBOLS} 个标的`;
      this.statusText = this.draftError;
      if (showToast) {
        this.toast(this.statusText);
      }
      return false;
    }
    this.card.quotes.symbols = this.card.quotes.symbols.concat([parsed.symbol.query]);
    screenSaverAppModel.save();
    const label = `${screenSaverQuoteMarketLabel(parsed.symbol.market)} ${parsed.symbol.code}`;
    this.codeDraft = '';
    this.draftError = '';
    this.statusText = `已添加 ${label}`;
    if (showToast) {
      this.toast(this.statusText);
    }
    screenSaverRequestQuotesRefresh();
    return true;
  }

  private removeSymbol(query: string): void {
    const next: string[] = [];
    for (const item of this.card.quotes.symbols) {
      if (item !== query) {
        next.push(item);
      }
    }
    this.card.quotes.symbols = next;
    screenSaverAppModel.save();
    this.statusText = '已移除';
    screenSaverRequestQuotesRefresh();
  }

  /** 旧数据展示：无法归一化时原样显示，仍允许删除。 */
  private symbolLabel(query: string): string {
    const symbol = screenSaverNormalizeStoredQuote(query);
    if (symbol === undefined) {
      return query;
    }
    const market = screenSaverQuoteMarketLabel(symbol.market);
    return market.length > 0 ? `${market} ${symbol.code}` : symbol.code;
  }

  private refreshNow(): void {
    if (this.codeDraft.trim().length > 0) {
      if (!this.addSymbol(false, false)) {
        return;
      }
    }
    if (this.card.quotes.symbols.length === 0) {
      this.statusText = '请至少添加一个标的';
      this.toast(this.statusText);
      return;
    }
    this.statusText = '已发起刷新';
    screenSaverRequestQuotesRefresh();
  }

  /** 「完成」前把未提交的 6 位代码落库；非法时保持面板打开并提示。 */
  private handleDone(): void {
    if (this.codeDraft.trim().length > 0) {
      if (!this.addSymbol(true, false)) {
        return;
      }
    }
    this.onDone();
  }

  private cacheTimeText(): string {
    const cache = screenSaverAppModel.getQuotesCache(this.card.id);
    if (cache === undefined || cache.fetchedAt <= 0) {
      return '暂无缓存';
    }
    return `缓存 ${screenSaverFormatStamp(cache.fetchedAt)} · ${cache.sourceLabel}`;
  }

  @Builder
  symbolRow(query: string) {
    Row({ space: 8 }) {
      Text(this.symbolLabel(query))
        .fontSize(13)
        .fontColor(SCREEN_SAVER_COLORS.textPrimary)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
      Text('×')
        .fontSize(15)
        .fontColor(SCREEN_SAVER_COLORS.danger)
        .padding({ left: 8, right: 4, top: 4, bottom: 4 })
        .onClick((): void => {
          this.removeSymbol(query);
        })
    }
    .width('100%')
    .padding({ top: 3, bottom: 3 })
    .alignItems(VerticalAlign.Center)
  }

  build() {
    Column() {
      ScreenSaverSheetHeader({
        title: this.panelTitle(),
        onDone: (): void => {
          this.handleDone();
        }
      })
      .padding({ left: 16, right: 16 })

      Scroll() {
        Column({ space: 12 }) {
          // ---------- 实时预览 ----------
          Column() {
            ScreensaverQuotesCard({
              card: this.card,
              cardMode: 'edit',
              cardActive: false,
              onRequestConfig: (): void => {
                this.toast('当前已在行情卡片配置中');
              }
            })
          }
          .width('100%')
          .height(120)
          .borderRadius(8)
          .backgroundColor(SCREEN_SAVER_COLORS.cardBg)
          .clip(true)

          // ---------- 6 位代码输入 ----------
          Column({ space: 6 }) {
            Row() {
              Text('自选标的')
                .fontSize(14)
                .fontColor('#CCCCCC')
              Blank()
              Text(`${this.card.quotes.symbols.length}/${SCREEN_SAVER_QUOTES_MAX_SYMBOLS}`)
                .fontSize(11)
                .fontColor(SCREEN_SAVER_COLORS.textTertiary)
            }
            .width('100%')
            Row({ space: 8 }) {
              TextInput({ text: this.codeDraft, placeholder: '6 位代码，例如 600519' })
                .type(InputType.Number)
                .inputFilter('[0-9]', (value: string): void => {
                  this.draftError = '只能输入 6 位数字';
                  this.statusText = this.draftError;
                  this.toast(this.draftError);
                })
                .fontSize(14)
                .fontColor(SCREEN_SAVER_COLORS.textPrimary)
                .placeholderColor(SCREEN_SAVER_COLORS.textTertiary)
                .backgroundColor(SCREEN_SAVER_COLORS.divider)
                .height(40)
                .maxLength(6)
                .layoutWeight(1)
                .onChange((value: string): void => {
                  this.onCodeChanged(value);
                })
              ScreenSaverChip({
                label: '添加',
                onTap: (): void => {
                  this.addSymbol(true, false);
                }
              })
            }
            .width('100%')
            if (this.draftError.length > 0) {
              Text(this.draftError)
                .fontSize(11)
                .fontColor(SCREEN_SAVER_COLORS.danger)
                .width('100%')
            }
            Text('只接受 6 位数字：6→沪，0/3→深，4/8→北交所；' +
              '禁止 sh/sz 前缀、空格、点号；旧格式读取时自动归一化。')
              .fontSize(10)
              .fontColor(SCREEN_SAVER_COLORS.textTertiary)
              .width('100%')
          }
          .width('100%')

          // ---------- 已添加标的 ----------
          Column({ space: 4 }) {
            if (this.card.quotes.symbols.length === 0) {
              Text('尚未添加标的')
                .fontSize(11)
                .fontColor(SCREEN_SAVER_COLORS.textTertiary)
                .width('100%')
            } else {
              Column() {
                ForEach(this.card.quotes.symbols, (query: string) => {
                  this.symbolRow(query)
                }, (query: string): string => query)
              }
              .width('100%')
              .padding({ left: 10, right: 10, top: 2, bottom: 2 })
              .borderRadius(8)
              .backgroundColor(SCREEN_SAVER_COLORS.bgElevated)
            }
          }
          .width('100%')

          // ---------- 涨跌配色 ----------
          Row() {
            Text('涨跌配色')
              .fontSize(14)
              .fontColor('#CCCCCC')
            Blank()
            Row({ space: 8 }) {
              ScreenSaverChip({
                label: '红涨绿跌',
                selected: this.card.quotes.colorScheme === 'redUp',
                onTap: (): void => {
                  this.card.quotes.colorScheme = 'redUp';
                  screenSaverAppModel.save();
                }
              })
              ScreenSaverChip({
                label: '绿涨红跌',
                selected: this.card.quotes.colorScheme === 'greenUp',
                onTap: (): void => {
                  this.card.quotes.colorScheme = 'greenUp';
                  screenSaverAppModel.save();
                }
              })
            }
          }
          .width('100%')

          ScreenSaverToggleRow({
            label: '断网时显示缓存',
            tip: '请求/解析失败时显示上次成功数据，并标注离线与数据时间',
            isOn: this.card.quotes.offlineCache,
            onChange: (value: boolean): void => {
              this.card.quotes.offlineCache = value;
              screenSaverAppModel.save();
            }
          })

          // 分时图开关：只在卡片严格大于 2×2 时出现；2×2 不显示分时图。
          if (screenSaverQuotesChartEligible(this.card.colSpan, this.card.rowSpan)) {
            ScreenSaverToggleRow({
              label: '显示分时K线图',
              tip: '仅大于 2×2 的卡片显示分时缩略图；关闭后恢复多标列表。2×2 及以下不显示。',
              isOn: this.card.quotes.showMinuteChart,
              onChange: (value: boolean): void => {
                this.card.quotes.showMinuteChart = value;
                screenSaverAppModel.save();
              }
            })
          }

          // ---------- 刷新与状态 ----------
          Row({ space: 8 }) {
            ScreenSaverChip({
              label: '立即刷新',
              onTap: (): void => {
                this.refreshNow();
              }
            })
            Text('保存后自动刷新')
              .fontSize(10)
              .fontColor(SCREEN_SAVER_COLORS.textTertiary)
              .layoutWeight(1)
          }
          .width('100%')
          if (this.statusText.length > 0) {
            Text(this.statusText)
              .fontSize(11)
              .fontColor(SCREEN_SAVER_COLORS.textTertiary)
              .width('100%')
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          Text(this.cacheTimeText())
            .fontSize(10)
            .fontColor(SCREEN_SAVER_COLORS.textTertiary)
            .width('100%')

          Text('数据源：腾讯行情（qt.gtimg.cn，GBK）。行情数据仅供参考，不构成投资建议。')
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
