/**
 * =============================================================================
 * 应用首页（Index.ets）
 * =============================================================================
 *
 * 【这个文件是干什么的】
 * 应用入口页面，由两部分组成：
 *   1. ScreenSaverConsole：首页主界面（控制台）——
 *      布局预览、「开启屏保」大按钮、「我的卡片」实例列表（含启停开关）、
 *      添加卡片入口、设置入口；
 *   2. Index（@Entry）：真正注册到路由表里的页面，只负责搭 Navigation
 *      导航框架，把控制台作为首页内容挂上去。
 *
 * 【为什么拆成两个 struct】
 * @Entry 页面必须是唯一的，而首页内容较复杂。拆开后：
 *   - ScreenSaverConsole 专注界面（作为 Navigation 的首页内容）；
 *   - Index 专注导航（navDestination 的路由映射 pageMap 也在这里）。
 *
 * 【导航架构（新手必读）】
 * 本应用用 Navigation + NavDestination 路由：
 *   - Index 持有全局唯一的 NavPathStack（导航栈）；
 *   - 想去哪个页面就 pushPathByName('路由名', 参数)；
 *   - pageMap 里声明每个路由名对应的页面组件：
 *       screensaver → 屏保播放页
 *       settings    → 设置页
 *       guide       → 新手引导页
 *       library     → 卡片库页
 *   - 各目标页面以 NavDestination 为根节点（见各页面文件）。
 *
 * 【首次启动逻辑】
 * 数据加载完成（whenLoaded）后检查引导标记：
 * 没完成过引导就自动 push guide 页——保证第一次打开先看到引导。
 * =============================================================================
 */

import { ScreenSaverLogger } from '../common/Logger';
import { SCREEN_SAVER_COLORS } from '../common/ScreenSaverStyle';
import { screenSaverAppModel } from '../model/AppModel';
import { ScreensaverCardHost } from '../cards/CardHost';
import { ScreenSaverPlayPage } from '../screensaver/ScreensaverPage';
import { ScreenSaverSettingsPage } from '../screensaver/SettingsPage';
import { ScreenSaverGuidePage } from '../screensaver/GuidePage';
import { ScreenSaverCardLibraryPage } from '../screensaver/CardLibraryPage';
import { ScreensaverLaunchParam, ScreensaverCardInstance } from '../model/ConfigModels';

/**
 * 首页控制台：所有卡片管理的入口界面。
 */
@ComponentV2
struct ScreenSaverConsole {
  @Param navStack: NavPathStack = new NavPathStack();

  /** 进入屏保播放页（带来源标记，方便日志追踪从哪进的）。 */
  private startScreensaver(): void {
    const param: ScreensaverLaunchParam = { from: 'home' };
    this.navStack.pushPathByName('screensaver', param);
  }

  /**
   * 卡片显示名：委托给 AppModel.cardInstanceTitle（与设置面板共用同一套
   * 命名规则），同类型有多张时自动带序号。
   */
  private cardTitle(card: ScreensaverCardInstance): string {
    return screenSaverAppModel.cardInstanceTitle(card);
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

  /**
   * 布局预览卡片：展示前 3 张卡的真实效果。
   * - 启用的卡：直接渲染真实的卡片组件（edit 模式、不激活——
   *   预览里不轮播、不请求网络，纯静态展示且省电）；
   * - 停用的卡：虚线边框占位（和屏保里的停用样式一致）；
   * - 没有卡片：引导用户点添加。
   * 时钟卡给更高的行高（56），其它卡 44——时钟是主视觉，稍微突出。
   */
  @Builder
  previewCard() {
    Column({ space: 6 }) {
      ForEach(screenSaverAppModel.layout.cards.slice(0, 3), (card: ScreensaverCardInstance) => {
        if (card.enabled) {
          Column() {
            ScreensaverCardHost({
              card: card,
              cardMode: 'edit',
              cardActive: false
            })
          }
          .width('100%')
          .height(card.cardType === 'clock' ? 56 : 44)
          .borderRadius(8)
          .backgroundColor(SCREEN_SAVER_COLORS.cardBg)
          .clip(true)
        } else {
          Row() {
            Text(`${this.cardTitle(card)} · 已停用`)
              .fontSize(11)
              .fontColor(SCREEN_SAVER_COLORS.textTertiary)
          }
          .width('100%')
          .height(card.cardType === 'clock' ? 56 : 44)
          .borderRadius(8)
          .border({
            width: 1,
            color: '#33FFFFFF',
            style: BorderStyle.Dashed
          })
          .justifyContent(FlexAlign.Center)
        }
      }, (card: ScreensaverCardInstance): string => card.id)
      if (screenSaverAppModel.layout.cards.length === 0) {
        Text('还没有卡片 · 点「＋ 添加卡片」加入')
          .fontSize(12)
          .fontColor(SCREEN_SAVER_COLORS.textTertiary)
          .height(56)
      }
      Row() {
        Text(`当前布局 · ${screenSaverAppModel.layout.cards.length} 张卡片`)
          .fontSize(11)
          .fontColor(SCREEN_SAVER_COLORS.textTertiary)
      }
      .width('100%')
    }
    .width('100%')
    .padding(12)
    .borderRadius(12)
    .backgroundColor(SCREEN_SAVER_COLORS.bgElevated)
  }

  /** 「＋ 添加卡片」入口行：跳转到卡片库页面。 */
  @Builder
  addCardRow() {
    Row() {
      Text('＋ 添加卡片')
        .fontSize(14)
        .fontColor(SCREEN_SAVER_COLORS.accent)
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .padding({ top: 13, bottom: 13 })
    .borderRadius(10)
    .backgroundColor(SCREEN_SAVER_COLORS.bgElevated)
    .onClick((): void => {
      this.navStack.pushPathByName('library', '');
    })
  }

  /**
   * 控制台主界面（自上而下）：
   *   标题区 → 布局预览 → 「开启屏保」主按钮 → 「我的卡片」列表 →
   *   添加入口 → 设置入口 → 版本脚注。
   * 整体放在 Scroll 里：卡片多时可以滚动。
   */
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
          Text('应用内全屏展示')
            .fontSize(12)
            .fontColor(SCREEN_SAVER_COLORS.textTertiary)
            .width('100%')
        }
        .width('100%')

        // ---------- 布局预览 ----------
        this.previewCard()

        // ---------- 「开启屏保」主按钮 ----------
        Text('开启屏保')
          .fontSize(16)
          .fontColor(SCREEN_SAVER_COLORS.white)
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ top: 14, bottom: 14 })
          .borderRadius(26)
          .backgroundColor(SCREEN_SAVER_COLORS.accentStrong)
          .onClick((): void => {
            this.startScreensaver();
          })

        // ---------- 「我的卡片」列表头 ----------
        Row() {
          Text('我的卡片')
            .fontSize(15)
            .fontColor(SCREEN_SAVER_COLORS.textPrimary)
          Blank()
          Text('开关控制是否显示')
            .fontSize(11)
            .fontColor(SCREEN_SAVER_COLORS.textTertiary)
        }
        .width('100%')

        // ---------- 卡片实例列表 ----------
        // 每张卡一行：标题（同类型带序号）+ 配置摘要 + 启停开关。
        // 开关直接改 AppModel，布局数据自动持久化。
        ForEach(screenSaverAppModel.layout.cards, (card: ScreensaverCardInstance) => {
          Row() {
            Column() {
              Text(this.cardTitle(card))
                .fontSize(14)
                .fontColor(SCREEN_SAVER_COLORS.textPrimary)
              Text(screenSaverAppModel.cardInstanceSummary(card))
                .fontSize(11)
                .fontColor(SCREEN_SAVER_COLORS.textTertiary)
                .margin({ top: 2 })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: card.enabled })
              .selectedColor(SCREEN_SAVER_COLORS.accentStrong)
              .onChange((value: boolean): void => {
                screenSaverAppModel.setCardEnabled(card.id, value);
              })
          }
          .width('100%')
          .padding(14)
          .borderRadius(10)
          .backgroundColor(SCREEN_SAVER_COLORS.bgElevated)
        }, (card: ScreensaverCardInstance): string => card.id)

        // ---------- 添加卡片入口 ----------
        this.addCardRow()

        // ---------- 设置入口 ----------
        Row() {
          Text('设置')
            .fontSize(14)
            .fontColor('#CCCCCC')
            .layoutWeight(1)
          Text('间隔 / 字号 / 权限')
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

  aboutToAppear(): void {
    screenSaverAppModel.whenLoaded((): void => {
      if (!screenSaverAppModel.isGuideDone()) {
        this.navStack.pushPathByName('guide', '');
      }
    });
  }

  /**
   * 路由映射表：pushPathByName 的名字在这里对应到页面组件。
   * 四个目标页面都以 NavDestination 为根（详见各页面文件）。
   */
  @Builder
  pageMap(name: string) {
    if (name === 'screensaver') {
      ScreenSaverPlayPage({ navStack: this.navStack })
    } else if (name === 'settings') {
      ScreenSaverSettingsPage({ navStack: this.navStack })
    } else if (name === 'guide') {
      ScreenSaverGuidePage({ navStack: this.navStack })
    } else if (name === 'library') {
      ScreenSaverCardLibraryPage({ navStack: this.navStack })
    }
  }

  build() {
    Navigation(this.navStack) {
      // Navigation 的首内容区：首页控制台
      ScreenSaverConsole({ navStack: this.navStack })
    }
    .title('屏保')
    .titleMode(NavigationTitleMode.Mini)
    .mode(NavigationMode.Stack)
    .navDestination(this.pageMap)
    .backgroundColor(SCREEN_SAVER_COLORS.bg)
  }
}
