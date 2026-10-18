/**
 * =============================================================================
 * 应用首页（Index.ets）
 * =============================================================================
 *
 * 【这个文件是干什么的】
 * 应用入口页面，由两部分组成：
 *   1. ScreenSaverConsole：首页控制台——两个一键开启按钮（竖屏 / 横屏）
 *      + 全局设置入口；
 *   2. Index（@Entry）：注册到路由表里的页面，搭 Navigation 导航框架。
 *
 * 【本轮变化（横屏模式）】
 *   - 首页移除「我的卡片」列表、启停开关与添加卡片入口；
 *     卡片增删/排序/尺寸/内容配置全部迁到方向设置页
 *     （屏保页长按 600ms 进入，或首页预检失败时跳转）。
 *   - 「开启屏保」拆成「开启竖屏屏保 / 开启横屏屏保」。
 *   - 进入屏保前先做预检：空布局 / 越界布局 → 提示并跳方向设置页；
 *     通过后先切窗口方向，切向失败留在首页。
 *
 * 【导航架构】
 *   Navigation + NavPathStack：
 *     screensaver  → 屏保播放页（参数带 mode）
 *     modeSettings → 方向设置页（参数带 mode）
 *     settings     → 全局设置页
 *     guide        → 新手引导页
 * =============================================================================
 */

import { common } from '@kit.AbilityKit';
import { ScreenSaverLogger } from '../common/Logger';
import { SCREEN_SAVER_COLORS } from '../common/ScreenSaverStyle';
import { screenSaverWindowController } from '../common/WindowController';
import { screenSaverAppModel } from '../model/AppModel';
import { ScreenSaverPlayPage } from '../screensaver/ScreensaverPage';
import { ScreenSaverModeSettingsPage } from '../screensaver/ModeSettingsPage';
import { ScreenSaverSettingsPage } from '../screensaver/SettingsPage';
import { ScreenSaverGuidePage } from '../screensaver/GuidePage';
import {
  ScreensaverLaunchParam,
  ScreenSaverModeSettingsParam,
  ScreenSaverOrientation,
  screenSaverOrientationLabel
} from '../model/ConfigModels';

/**
 * 首页控制台：一键开启（竖屏 / 横屏）+ 全局设置。
 */
@ComponentV2
struct ScreenSaverConsole {
  @Param navStack: NavPathStack = new NavPathStack();
  /**
   * 外部刷新信号：数据加载完成 / 从设置页返回首页时自增，
   * 强制重新计算两个方向的卡片数量（卡片数组的原地增删不一定会触发观察）。
   */
  @Param dataTick: number = 0;
  /** 切换方向是异步的：防重复点击，避免连续 push 两个屏保页。 */
  @Local starting: boolean = false;

  private toast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message, duration: 1600 });
    } catch (err) {
      const error = err as Error;
      ScreenSaverLogger.warn(`toast failed: ${error.message}`);
    }
  }

  /** 跳转当前方向设置页（首页不直接管卡片）。 */
  private openModeSettings(mode: ScreenSaverOrientation): void {
    screenSaverAppModel.setActiveOrientation(mode);
    const param: ScreenSaverModeSettingsParam = { from: 'home', mode: mode };
    this.navStack.pushPathByName('modeSettings', param);
  }

  /**
   * 开启屏保：
   *   1. 空布局 → 提示 + 跳该方向设置页（不进入）；
   *   2. 布局越界/重叠 → 提示 + 跳设置页；
   *   3. 先切窗口方向，失败留在首页；
   *   4. 通过后 push 屏保页（路由参数带 mode）。
   */
  private async startScreensaver(mode: ScreenSaverOrientation): Promise<void> {
    if (this.starting) {
      return;
    }
    const label = screenSaverOrientationLabel(mode);
    screenSaverAppModel.setActiveOrientation(mode);
    if (!screenSaverAppModel.modeHasCards(mode)) {
      this.toast(`${label}还没有卡片，请先添加`);
      this.openModeSettings(mode);
      return;
    }
    if (!screenSaverAppModel.layoutFitsMode(mode)) {
      this.toast(`${label}布局超出范围，请先调整卡片`);
      this.openModeSettings(mode);
      return;
    }
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext | undefined;
    if (context === undefined) {
      this.toast('无法获取窗口，请重试');
      return;
    }
    this.starting = true;
    const orientationOk = await screenSaverWindowController.applyOrientation(context, mode);
    this.starting = false;
    if (!orientationOk) {
      this.toast(`无法切换到${label}，请检查系统方向设置`);
      return;
    }
    const param: ScreensaverLaunchParam = { from: 'home', mode: mode };
    ScreenSaverLogger.info(`start screensaver: ${mode}`);
    this.navStack.pushPathByName('screensaver', param);
  }

  /**
   * 卡片数量文案：读取 cardsRevision 建立观察依赖。
   * 卡片数组的 push/splice 不会自动触发首页刷新，所以增删/排序时
   * AppModel 会自增该版本号，首页据此重新计算数量。
   */
  private cardCountText(mode: ScreenSaverOrientation): string {
    const layout = screenSaverAppModel.layoutForMode(mode);
    const revision = layout.cardsRevision;
    if (revision < 0 || this.dataTick < 0) {
      return '';
    }
    return `${layout.cards.length} 张卡片 · 长按屏保页可编辑`;
  }

  /**
   * 开启按钮使用「无参数 @Builder」：标题与数量文案直接写在 build 体内。
   * 多参数 @Builder 的字符串参数在组件复用时可能保持旧值（实测数量不刷新），
   * 因此这里不把数量当参数传。
   */
  @Builder
  startPortraitButton() {
    Column({ space: 3 }) {
      Text('开启竖屏屏保')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(SCREEN_SAVER_COLORS.white)
      Text(this.cardCountText(ScreenSaverOrientation.Portrait))
        .fontSize(11)
        .fontColor('#CCD8FF')
    }
    .width('100%')
    .padding({ top: 14, bottom: 14 })
    .borderRadius(26)
    .backgroundColor(SCREEN_SAVER_COLORS.accentStrong)
    .opacity(this.starting ? 0.6 : 1)
    .onClick((): void => {
      void this.startScreensaver(ScreenSaverOrientation.Portrait);
    })
  }

  @Builder
  startLandscapeButton() {
    Column({ space: 3 }) {
      Text('开启横屏屏保')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(SCREEN_SAVER_COLORS.white)
      Text(this.cardCountText(ScreenSaverOrientation.Landscape))
        .fontSize(11)
        .fontColor('#CCD8FF')
    }
    .width('100%')
    .padding({ top: 14, bottom: 14 })
    .borderRadius(26)
    .backgroundColor(SCREEN_SAVER_COLORS.accentStrong)
    .opacity(this.starting ? 0.6 : 1)
    .onClick((): void => {
      void this.startScreensaver(ScreenSaverOrientation.Landscape);
    })
  }

  build() {
    Scroll() {
      Column({ space: 14 }) {
        // ---------- 标题区 ----------
        Column({ space: 4 }) {
          Text('屏保')
            .fontSize(20)
            .fontWeight(FontWeight.Medium)
            .fontColor(SCREEN_SAVER_COLORS.textPrimary)
            .width('100%')
          Text('应用内全屏展示 · 竖屏 / 横屏独立布局')
            .fontSize(12)
            .fontColor(SCREEN_SAVER_COLORS.textTertiary)
            .width('100%')
        }
        .width('100%')

        // ---------- 一键开启（两个方向） ----------
        this.startPortraitButton()

        this.startLandscapeButton()

        Text('两个方向的卡片、布局与内容配置独立保存；背景、文字颜色、常亮为全局设置。')
          .fontSize(11)
          .fontColor(SCREEN_SAVER_COLORS.textTertiary)
          .width('100%')
          .padding({ left: 2, right: 2 })

        // ---------- 全局设置入口 ----------
        Row() {
          Text('全局设置')
            .fontSize(14)
            .fontColor('#CCCCCC')
            .layoutWeight(1)
          Text('背景 / 文字 / 常亮')
            .fontSize(11)
            .fontColor(SCREEN_SAVER_COLORS.textTertiary)
          Text('›')
            .fontSize(16)
            .fontColor(SCREEN_SAVER_COLORS.textTertiary)
            .margin({ left: 8 })
        }
        .width('100%')
        .padding(14)
        .borderRadius(10)
        .backgroundColor(SCREEN_SAVER_COLORS.bgElevated)
        .onClick((): void => {
          this.navStack.pushPathByName('settings', '');
        })

        // ---------- 版本脚注 ----------
        Text('v0.1 · 深色省电 · 静态优先')
          .fontSize(11)
          .fontColor(SCREEN_SAVER_COLORS.textTertiary)
          .margin({ top: 4, bottom: 24 })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12 })
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .align(Alignment.Top)
    .backgroundColor(SCREEN_SAVER_COLORS.bg)
  }
}

/**
 * 入口页面：搭 Navigation 导航框架。
 * 注意 aboutToAppear 里用 whenLoaded 而不是直接判断——
 * 数据还没从磁盘加载完就判断「引导是否完成」会误判（默认未完成），
 * 所以必须等 load() 完成后再决定要不要进引导页。
 */
@Entry
@ComponentV2
struct Index {
  /** 全局导航栈：所有页面的跳转都靠它。 */
  @Local navStack: NavPathStack = new NavPathStack();
  /** 首页数据版本：加载完成、返回首页时自增，刷新卡片数量文案。 */
  @Local dataTick: number = 0;

  aboutToAppear(): void {
    screenSaverAppModel.whenLoaded((): void => {
      // 布局加载完成：让首页重新计算两个方向的卡片数量。
      this.dataTick += 1;
      if (!screenSaverAppModel.isGuideDone()) {
        this.navStack.pushPathByName('guide', '');
      }
    });
  }

  /**
   * 路由映射表：pushPathByName 的名字在这里对应到页面组件。
   * 屏保页 / 方向设置页的方向取自 AppModel 的当前方向（入口已先设置），
   * 同时 pushPathByName 的参数里也携带 mode（满足「路由必须带方向」）。
   */
  @Builder
  pageMap(name: string) {
    if (name === 'screensaver') {
      ScreenSaverPlayPage({
        navStack: this.navStack,
        mode: screenSaverAppModel.getActiveOrientation()
      })
    } else if (name === 'modeSettings') {
      ScreenSaverModeSettingsPage({
        navStack: this.navStack,
        mode: screenSaverAppModel.getActiveOrientation()
      })
    } else if (name === 'settings') {
      ScreenSaverSettingsPage({ navStack: this.navStack })
    } else if (name === 'guide') {
      ScreenSaverGuidePage({ navStack: this.navStack })
    }
  }

  build() {
    Navigation(this.navStack) {
      // Navigation 的首内容区：首页控制台
      ScreenSaverConsole({ navStack: this.navStack, dataTick: this.dataTick })
    }
    // 首页自带标题，不再重复显示系统标题栏/返回箭头
    .hideTitleBar(true)
    .mode(NavigationMode.Stack)
    .navDestination(this.pageMap)
    // 从设置页/屏保页返回首页时 NavBar 重新可见：刷新卡片数量
    .onNavBarStateChange((visible: boolean): void => {
      if (visible) {
        this.dataTick += 1;
      }
    })
    .backgroundColor(SCREEN_SAVER_COLORS.bg)
  }
}
