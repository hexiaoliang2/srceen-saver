/**
 * 首页屏保预览（本轮新增）
 *
 * 只读当前方向的布局与背景设置，用“迷你网格 + 卡片类型标签”示意
 * 屏保实际长相；不挂载真实卡片组件，因此不会触发行情/天气请求，
 * 也不会有任何定时器或动画。
 */

import { SCREEN_SAVER_COLORS } from '../common/ScreenSaverStyle';
import { screenSaverCardTypeName } from '../cards/CardCatalog';
import { screenSaverAppModel } from '../model/AppModel';
import {
  SCREEN_SAVER_GRID_COLS,
  SCREEN_SAVER_GRID_ROWS,
  SCREEN_SAVER_LANDSCAPE_GRID_COLS,
  SCREEN_SAVER_LANDSCAPE_GRID_ROWS,
  ScreenSaverOrientation,
  ScreensaverCardInstance,
  ScreensaverCardType
} from '../model/ConfigModels';

@ComponentV2
export struct ScreenSaverHomePreview {
  @Param mode: ScreenSaverOrientation = ScreenSaverOrientation.Portrait;
  @Param dataTick: number = 0;

  private isPortrait(): boolean {
    return this.mode === ScreenSaverOrientation.Portrait;
  }

  private gridCols(): number {
    return this.isPortrait() ? SCREEN_SAVER_GRID_COLS : SCREEN_SAVER_LANDSCAPE_GRID_COLS;
  }

  private gridRows(): number {
    return this.isPortrait() ? SCREEN_SAVER_GRID_ROWS : SCREEN_SAVER_LANDSCAPE_GRID_ROWS;
  }

  /** 只展示启用卡片；dataTick 参与读取，确保从设置页返回后刷新。 */
  private cards(): ScreensaverCardInstance[] {
    const layout = screenSaverAppModel.layoutForMode(this.mode);
    const revision = layout.cardsRevision;
    if (revision < 0 || this.dataTick < 0) {
      return [];
    }
    const result: ScreensaverCardInstance[] = [];
    for (const card of layout.cards) {
      if (card.enabled) {
        result.push(card);
      }
    }
    return result;
  }

  private template(count: number): string {
    let text = '';
    for (let i = 0; i < count; i++) {
      text += i === 0 ? '1fr' : ' 1fr';
    }
    return text;
  }

  private labelOf(card: ScreensaverCardInstance): string {
    let name = screenSaverCardTypeName(card.cardType);
    if (card.cardType === 'entry' && card.entry.displayName.length > 0) {
      // 入口卡用用户配置的名称（如「微信」），比类型名更接近屏保实际内容。
      name = card.entry.displayName;
    }
    if (card.colSpan * card.rowSpan <= 1) {
      return name.substring(0, 1);
    }
    if (card.colSpan <= 1) {
      return name.substring(0, 2);
    }
    return name;
  }

  /** 卡片类型强调色：仅用于预览标签/细边，不参与真实屏保。 */
  private accentOf(type: ScreensaverCardType): string {
    if (type === 'weather') {
      return '#7DB8FF';
    }
    if (type === 'quotes') {
      return '#4CD97B';
    }
    if (type === 'countdown') {
      return '#D96A4A';
    }
    if (type === 'entry') {
      return '#B39DFF';
    }
    if (type === 'photo') {
      return '#FFC46B';
    }
    if (type === 'video') {
      return '#FF8B84';
    }
    if (type === 'git') {
      return '#A9B4C0';
    }
    if (type === 'todo') {
      return '#F2B75E';
    }
    return '#F2F2F2';
  }

  @Builder
  miniCard(card: ScreensaverCardInstance) {
    Stack({ alignContent: Alignment.Center }) {
      Text(this.labelOf(card))
        .fontSize(10)
        .fontColor(this.accentOf(card.cardType))
        .fontWeight(FontWeight.Medium)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Clip })
        .padding({ left: 2, right: 2 })
    }
    .width('100%')
    .height('100%')
    .borderRadius(4)
    .backgroundColor('#1FFFFFFF')
    .border({ width: 1, color: '#33FFFFFF' })
  }

  @Builder
  previewSurface() {
    Stack({ alignContent: Alignment.TopStart }) {
      // 背景色始终垫底；有背景图时再覆盖图片（失败时仍能看到底色）。
      Row()
        .width('100%')
        .height('100%')
        .backgroundColor(screenSaverAppModel.layout.settings.canvasColor)
      if (screenSaverAppModel.layout.settings.canvasImageUri.length > 0) {
        Image(screenSaverAppModel.layout.settings.canvasImageUri)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
      }
      // 压暗，保证浅色背景/背景图上预览标签仍可读。
      Row()
        .width('100%')
        .height('100%')
        .backgroundColor('#66000000')

      if (this.cards().length === 0) {
        Column({ space: 4 }) {
          Text('--:--')
            .fontSize(22)
            .fontColor('#D8D8D8')
            .fontWeight(FontWeight.Medium)
          Text('暂无卡片')
            .fontSize(10)
            .fontColor('#A8A8AE')
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else {
        Grid() {
          ForEach(this.cards(), (card: ScreensaverCardInstance) => {
            GridItem() {
              this.miniCard(card)
            }
            .rowStart(card.rowStart)
            .rowEnd(card.rowStart + card.rowSpan - 1)
            .columnStart(card.colStart)
            .columnEnd(card.colStart + card.colSpan - 1)
          }, (card: ScreensaverCardInstance): string => card.id)
        }
        .columnsTemplate(this.template(this.gridCols()))
        .rowsTemplate(this.template(this.gridRows()))
        .columnsGap(2)
        .rowsGap(2)
        .padding(4)
        .width('100%')
        .height('100%')
      }
    }
    .width('100%')
    .height('100%')
  }

  build() {
    Column({ space: 6 }) {
      if (this.isPortrait()) {
        Row() {
          Stack() {
            this.previewSurface()
          }
          .width(156)
          .height(312)
          .borderRadius(22)
          .clip(true)
          .border({ width: 2, color: '#3A3A40' })
          .backgroundColor('#111114')
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
      } else {
        Stack() {
          this.previewSurface()
        }
        .width('100%')
        .height(188)
        .borderRadius(18)
        .clip(true)
        .border({ width: 2, color: '#3A3A40' })
        .backgroundColor('#111114')
      }

      Row() {
        Text(this.isPortrait() ? '竖屏预览' : '横屏预览')
          .fontSize(10)
          .fontColor(SCREEN_SAVER_COLORS.textTertiary)
      }
      .width(this.isPortrait() ? 156 : '100%')
      .justifyContent(FlexAlign.Start)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .hitTestBehavior(HitTestMode.None)
  }
}
