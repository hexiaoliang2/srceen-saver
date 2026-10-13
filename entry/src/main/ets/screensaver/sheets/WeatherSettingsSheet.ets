/**
 * =============================================================================
 * 天气卡片设置面板（WeatherSettingsSheet.ets，需求 A）
 * =============================================================================
 *
 * 城市名（手输，不申请定位权限）、联网开关（默认关）、单位（℃/℉）、
 * 手动刷新、数据源说明与署名、删除卡片。
 *
 * 【默认关闭联网】
 * 卡片默认不会发起任何网络请求，必须用户在这里显式打开。这样：
 *   - 用户对「是否联网」有明确控制；
 *   - 数据源条款风险（免费层限非商业用途）由用户知情后决定。
 * =============================================================================
 */

import {
  ScreenSaverChip,
  ScreenSaverDeleteCardRow,
  ScreenSaverSheetHeader,
  ScreenSaverToggleRow
} from '../../common/SheetParts';
import { SCREEN_SAVER_COLORS } from '../../common/ScreenSaverStyle';
import { ScreenSaverLogger } from '../../common/Logger';
import { screenSaverAppModel } from '../../model/AppModel';
import { screenSaverWeatherViewModel } from '../../model/WeatherViewModel';
import { ScreensaverWeatherCard } from '../../cards/WeatherCardView';
import { ScreensaverCardInstance } from '../../model/ConfigModels';

@ComponentV2
export struct ScreenSaverWeatherSettingsPanel {
  @Param card: ScreensaverCardInstance = new ScreensaverCardInstance();
  @Event onDone: () => void = (): void => {};
  @Event onDelete: () => void = (): void => {};

  /** 城市输入草稿（回车/完成时写回卡片）。 */
  @Local cityDraft: string = '';
  /** 状态提示（如「已刷新」）。 */
  @Local statusText: string = '';

  aboutToAppear(): void {
    this.cityDraft = this.card.weather.city;
  }

  /** 面板标题：带实例标识，便于核对面板归属哪张卡片。 */
  private panelTitle(): string {
    return `${screenSaverAppModel.cardInstanceTitle(this.card)} · 设置`;
  }

  /** 把城市草稿写回卡片（空值不生效），并清掉缓存的经纬度以便重新解析。 */
  private applyCity(): void {
    const value = this.cityDraft.trim();
    if (value.length === 0 || value === this.card.weather.city) {
      return;
    }
    this.card.weather.city = value;
    this.card.weather.latitude = 0;
    this.card.weather.longitude = 0;
    screenSaverAppModel.save();
  }

  /** 立即刷新（用户明确操作，不受节流限制）。 */
  private refreshNow(): void {
    this.applyCity();
    if (this.card.weather.city.length === 0) {
      this.statusText = '请先填写城市';
      return;
    }
    if (!this.card.weather.enabled) {
      this.statusText = '请先打开「启用天气数据」';
      return;
    }
    this.statusText = '刷新中…';
    void screenSaverWeatherViewModel.refresh(this.card.weather.city, this.card.weather.latitude,
      this.card.weather.longitude, this.card.weather.offlineCache);
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

  build() {
    Column() {
      ScreenSaverSheetHeader({
        title: this.panelTitle(),
        onDone: (): void => {
          this.applyCity();
          this.onDone();
        }
      })
      .padding({ left: 16, right: 16 })

      Scroll() {
        Column({ space: 12 }) {
          // ---------- 实时预览 ----------
          Column() {
            ScreensaverWeatherCard({
              card: this.card,
              cardMode: 'edit',
              cardActive: false,
              onRequestConfig: (): void => {
                this.toast('当前已在天气卡片配置中');
              }
            })
          }
          .width('100%')
          .height(120)
          .borderRadius(8)
          .backgroundColor(SCREEN_SAVER_COLORS.cardBg)
          .clip(true)

          // ---------- 城市 ----------
          Row() {
            Text('城市')
              .fontSize(14)
              .fontColor('#CCCCCC')
            Blank()
            TextInput({ text: this.cityDraft, placeholder: '例如：深圳' })
              .type(InputType.Normal)
              .fontSize(13)
              .fontColor(SCREEN_SAVER_COLORS.textPrimary)
              .placeholderColor(SCREEN_SAVER_COLORS.textTertiary)
              .backgroundColor(SCREEN_SAVER_COLORS.divider)
              .width(180)
              .height(36)
              .onChange((value: string): void => {
                this.cityDraft = value;
              })
              .onSubmit((): void => {
                this.applyCity();
              })
          }
          .width('100%')

          // ---------- 启用开关 ----------
          ScreenSaverToggleRow({
            label: '启用天气数据',
            tip: '默认关闭：打开后才会联网获取天气（节流 30 分钟）',
            isOn: this.card.weather.enabled,
            onChange: (value: boolean): void => {
              this.card.weather.enabled = value;
              screenSaverAppModel.save();
              if (value) {
                this.refreshNow();
              } else {
                this.statusText = '已关闭联网';
              }
            }
          })

          // ---------- 单位 ----------
          Row() {
            Text('温度单位')
              .fontSize(14)
              .fontColor('#CCCCCC')
            Blank()
            Row({ space: 8 }) {
              ScreenSaverChip({
                label: '℃',
                selected: this.card.weather.unitCelsius,
                onTap: (): void => {
                  this.card.weather.unitCelsius = true;
                  screenSaverAppModel.save();
                }
              })
              ScreenSaverChip({
                label: '℉',
                selected: !this.card.weather.unitCelsius,
                onTap: (): void => {
                  this.card.weather.unitCelsius = false;
                  screenSaverAppModel.save();
                }
              })
            }
          }
          .width('100%')

          // ---------- 刷新 ----------
          Row({ space: 8 }) {
            ScreenSaverChip({
              label: '立即刷新',
              onTap: (): void => {
                this.refreshNow();
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

          // ---------- 数据源说明（合规信息） ----------
          Text('数据源：Open-Meteo（免密钥公开接口，需署名，免费层限非商业用途）。' +
            '城市名仅用于查询天气，不申请定位权限；关闭开关后不会发起任何网络请求。')
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
