/**
 * =============================================================================
 * 应用入口 Ability（EntryAbility.ets）
 * =============================================================================
 *
 * 【这个文件是干什么的】
 * 应用的生命周期入口（UIAbility），App 进程创建 → 加载窗口 → 前后台切换
 * 的所有「时机」都在这里处理。真正的业务在别的模块，这里只做接线和调度。
 *
 * 【启动时做了三件关键事】
 *   1. onCreate：把 Context 交给 AppModel（之后它才能读写偏好存储），
 *      异步加载已保存的布局，加载完按设置应用字号缩放；
 *   2. onWindowStageCreate：加载首页 pages/Index，并强制深色模式
 *      （屏保应用定位就是深色省电，不给浅色模式）；
 *   3. onForeground/onBackground：通知全局心跳（Ticker）应用是否可见——
 *      退到后台时心跳暂停，省电；回前台自动恢复。
 *
 * 【为什么用全局单例 Ticker 而不是每页自己 setInterval】
 * 全局唯一心跳源，前后台切换只改一个标志，所有依赖它的时钟/轮播卡片
 * 一起停或一起走，不会出现后台偷跑、多份定时器打架的问题。
 * =============================================================================
 */

import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { screenSaverTicker } from '../common/Ticker';
import { screenSaverApplyFontScale } from '../common/FontScale';
import { screenSaverAppModel } from '../model/AppModel';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  /**
   * 应用创建：
   * - attachContext：AppModel 拿到 Context（后面 save/load 都靠它）；
   * - load：从偏好存储读出布局（异步），完成后按设置应用字号缩放
   *   （「字号跟随系统」开关在启动时就要生效）。
   */
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
    screenSaverAppModel.attachContext(this.context);
    void screenSaverAppModel.load().then((): void => {
      screenSaverApplyFontScale(this.context, screenSaverAppModel.layout.settings.fontFollowSystem);
    });
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  /**
   * 窗口创建：
   * - 加载首页 pages/Index（路由入口，见 main_pages.json）；
   * - 强制深色模式：屏保应用始终深色（省电 + 氛围感），不随系统切浅色。
   */
  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');
    });

    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  /** 回到前台：恢复全局心跳（时钟/轮播重新走表）。 */
  onForeground(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
    screenSaverTicker.setAppActive(true);
  }

  /** 退到后台：暂停全局心跳（定时刷新全部停止，省电）。 */
  onBackground(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
    screenSaverTicker.setAppActive(false);
  }
}
