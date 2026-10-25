/**
 * =============================================================================
 * 分时图（QuotesMinuteChart.ets）—— Canvas 自绘，无图表库、无动画
 * =============================================================================
 *
 * 内容：当日分时折线 + 昨收水平虚线 + 可选均价线。
 * 只画「数据变化」时重绘：@Monitor('revision') 与尺寸/配色变化各触发一次 draw，
 * 屏保静止态没有常驻动画。
 * 数据不足（<2 点 / 昨收非法）时由父组件显示占位文案，本组件不画残缺图形。
 * =============================================================================
 */

import { ScreensaverMinutePoint } from '../model/ConfigModels';
import { SCREEN_SAVER_FONT } from '../common/CardTypography';

@ComponentV2
export struct ScreensaverMinuteChart {
  @Param points: ScreensaverMinutePoint[] = [];
  @Param prevClose: number = 0;
  /** 数据/样式版本：父组件每次更新数据自增，触发一次静态重绘。 */
  @Param revision: number = 0;
  @Param lineColor: string = '#FF6B6B';
  @Param baselineColor: string = '#ABABAB';
  @Param averageColor: string = '#D6D6D6';
  @Param textColor: string = '#ABABAB';
  /** 数据日期（MM-DD）；非交易时段可能展示最近一个交易日，必须标出来。 */
  @Param dateLabel: string = '';

  @Local private canvasW: number = 0;
  @Local private canvasH: number = 0;

  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private context: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);

  @Monitor('revision')
  onRevisionChanged(): void {
    this.draw();
  }

  @Monitor('lineColor', 'baselineColor', 'averageColor')
  onStyleChanged(): void {
    this.draw();
  }

  private draw(): void {
    const width = this.canvasW;
    const height = this.canvasH;
    const points = this.points;
    const prevClose = this.prevClose;
    if (width <= 2 || height <= 2 || points.length < 2 || prevClose <= 0) {
      return;
    }
    this.context.clearRect(0, 0, width, height);
    let minValue = prevClose;
    let maxValue = prevClose;
    for (const point of points) {
      if (point.price < minValue) {
        minValue = point.price;
      }
      if (point.price > maxValue) {
        maxValue = point.price;
      }
    }
    // 全平盘时给一个最小跨度，否则折线会贴成一条无法辨认的直线。
    const minSpan = Math.max(prevClose * 0.002, 0.01);
    let span = maxValue - minValue;
    if (span < minSpan) {
      const center = (maxValue + minValue) / 2;
      minValue = center - minSpan / 2;
      maxValue = center + minSpan / 2;
      span = minSpan;
    }
    const padY = Math.max(2, height * 0.08);
    const plotHeight = height - padY * 2;

    // 昨收基准：水平虚线。
    this.context.setLineDash([4, 3]);
    this.context.strokeStyle = this.baselineColor;
    this.context.lineWidth = 1;
    this.context.beginPath();
    this.context.moveTo(0, this.yOf(prevClose, maxValue, span, plotHeight, padY));
    this.context.lineTo(width, this.yOf(prevClose, maxValue, span, plotHeight, padY));
    this.context.stroke();
    this.context.setLineDash([]);

    // 均价线（成交量加权价格不可得时用分钟价格累计均值，标注为「均价」）。
    this.context.strokeStyle = this.averageColor;
    this.context.lineWidth = 1;
    this.context.globalAlpha = 0.65;
    this.context.beginPath();
    let sum = 0;
    for (let index = 0; index < points.length; index++) {
      sum += points[index].price;
      const average = sum / (index + 1);
      const x = this.xOf(index, width, points.length);
      const y = this.yOf(average, maxValue, span, plotHeight, padY);
      if (index === 0) {
        this.context.moveTo(x, y);
      } else {
        this.context.lineTo(x, y);
      }
    }
    this.context.stroke();
    this.context.globalAlpha = 1;

    // 分时折线。
    this.context.strokeStyle = this.lineColor;
    this.context.lineWidth = 1.6;
    this.context.beginPath();
    for (let index = 0; index < points.length; index++) {
      const x = this.xOf(index, width, points.length);
      const y = this.yOf(points[index].price, maxValue, span, plotHeight, padY);
      if (index === 0) {
        this.context.moveTo(x, y);
      } else {
        this.context.lineTo(x, y);
      }
    }
    this.context.stroke();
  }

  private xOf(index: number, width: number, count: number): number {
    return count <= 1 ? 0 : (index / (count - 1)) * width;
  }

  private yOf(price: number, maxValue: number, span: number, plotHeight: number, padY: number): number {
    return padY + ((maxValue - price) / span) * plotHeight;
  }

  build() {
    Column({ space: 2 }) {
      Row({ space: 6 }) {
        Text(this.dateLabel.length > 0 ? `分时 · ${this.dateLabel}` : '分时')
          .fontSize(SCREEN_SAVER_FONT.L7)
          .fontColor(this.lineColor)
          .maxLines(1)
        Blank()
        Text(`昨收 ${this.prevClose.toFixed(2)}`)
          .fontSize(SCREEN_SAVER_FONT.L7)
          .fontColor(this.textColor)
          .maxLines(1)
      }
      .width('100%')

      Canvas(this.context)
        .width('100%')
        .layoutWeight(1)
        .onReady((): void => {
          this.draw();
        })
        .onAreaChange((oldArea: Area, newArea: Area): void => {
          this.canvasW = typeof newArea.width === 'number' ? newArea.width : 0;
          this.canvasH = typeof newArea.height === 'number' ? newArea.height : 0;
          this.draw();
        })
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
