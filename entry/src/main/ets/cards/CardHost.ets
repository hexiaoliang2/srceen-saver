/**
 * =============================================================================
 * 卡片分发器（CardHost.ets）
 * =============================================================================
 *
 * 【这个文件是干什么的】
 * 根据 cardType 把一张卡片实例「分发」给对应的具体视图组件渲染：
 * photo → ScreensaverPhotoCard、video → ScreensaverVideoCard、
 * git → ScreensaverGitCard、其它（含 clock）→ ScreensaverClockCard。
 *
 * 【为什么需要这层转发】
 * 屏保页（ScreensaverPage）的网格里每个格子只放一个 ScreensaverCardHost，
 * 不需要关心里面是哪种卡片。新增卡片类型时，屏保页一行代码都不用改，
 * 只改这里的映射——这就是「分发层」解耦的价值。
 *
 * 【参数说明】
 * card      卡片数据实例；
 * cardMode  'edit'（编辑态，显示边框/手柄等辅助元素）或 'play'（播放态）；
 * cardActive 是否激活（屏保在前台才轮播/请求网络，后台时暂停省电）；
 * onRequestConfig 用户点「配置」按钮时冒泡给上层的回调（转发给具体卡片）。
 * =============================================================================
 */

import { ScreensaverClockCard } from './ClockCardView';
import { ScreensaverPhotoCard } from './PhotoCardView';
import { ScreensaverVideoCard } from './VideoCardView';
import { ScreensaverGitCard } from './GitCardView';
import { ScreensaverWeatherCard } from './WeatherCardView';
import { ScreensaverEntryCard } from './EntryCardView';
import { ScreensaverCardInstance, ScreensaverCardMode, ScreensaverInkTone } from '../model/ConfigModels';

@ComponentV2
export struct ScreensaverCardHost {
  @Param card: ScreensaverCardInstance = new ScreensaverCardInstance();
  @Param cardMode: ScreensaverCardMode = 'play';
  @Param cardActive: boolean = true;
  /**
   * 卡片皮肤（变更项 3.2/3.3）：文字/图标墨色档 + 投影兜底开关。
   * 屏保页按「整体背景明度」统一解析后下发（同一来源）；不改默认值时
   * 卡片保持浅色观感（设置面板、首页预览等深色容器场景直接用默认）。
   */
  @Param cardTone: ScreensaverInkTone = 'light';
  @Param cardHalo: boolean = false;
  @Event onRequestConfig: () => void = (): void => {};

  build() {
    // 按类型分发到具体卡片视图；所有参数原样透传。
    // 内容密度不在这里透传：各卡片视图自己按 card.colSpan/rowSpan 查尺寸矩阵，
    // 避免 @Builder 多参数按值传递在 ForEach 复用时「传了但不刷新」的坑。
    if (this.card.cardType === 'photo') {
      ScreensaverPhotoCard({
        card: this.card,
        cardMode: this.cardMode,
        cardActive: this.cardActive,
        cardTone: this.cardTone,
        cardHalo: this.cardHalo
      })
    } else if (this.card.cardType === 'video') {
      ScreensaverVideoCard({
        card: this.card,
        cardMode: this.cardMode,
        cardActive: this.cardActive,
        cardTone: this.cardTone,
        cardHalo: this.cardHalo,
        onRequestConfig: (): void => {
          this.onRequestConfig();
        }
      })
    } else if (this.card.cardType === 'git') {
      ScreensaverGitCard({
        card: this.card,
        cardMode: this.cardMode,
        cardActive: this.cardActive,
        cardTone: this.cardTone,
        cardHalo: this.cardHalo,
        onRequestConfig: (): void => {
          this.onRequestConfig();
        }
      })
    } else if (this.card.cardType === 'weather') {
      ScreensaverWeatherCard({
        card: this.card,
        cardMode: this.cardMode,
        cardActive: this.cardActive,
        cardTone: this.cardTone,
        cardHalo: this.cardHalo,
        onRequestConfig: (): void => {
          this.onRequestConfig();
        }
      })
    } else if (this.card.cardType === 'entry') {
      ScreensaverEntryCard({
        card: this.card,
        cardMode: this.cardMode,
        cardTone: this.cardTone,
        cardHalo: this.cardHalo
      })
    } else {
      // 默认（含 'clock'）：时钟卡片不需要 active/onRequestConfig 参数
      ScreensaverClockCard({
        card: this.card,
        cardMode: this.cardMode,
        cardTone: this.cardTone,
        cardHalo: this.cardHalo
      })
    }
  }
}
