/**
 * =============================================================================
 * Git 贡献卡片视图（GitCardView.ets）
 * =============================================================================
 *
 * 【这个文件是干什么的】
 * 把 GitHub 贡献数据渲染成「热力图」：每列一周、每行一天（周日~周六）、
 * 每个小格子的颜色深浅代表当天提交次数（0~4 级），和 GitHub 个人主页的
 * 贡献图一致。
 *
 * 【数据从哪来】
 * GitViewModel 负责拉取（带 30 分钟节流 + 离线缓存）。本组件：
 *   - 挂载时先用缓存「注水」（立即有图可看），满足节流条件才发起新请求；
 *   - 用户名变化、回到前台时按需刷新。
 *
 * 【颜色分级】
 * levelFor(): 0 次=0 级、1~3 次=1 级、4~6=2 级、7~9=3 级、10+=4 级。
 * 三套配色（绿/蓝/灰），离线时强制灰阶——一眼就能看出数据不是最新的。
 *
 * 【格子大小自适应】
 * cellSize(): 按卡片宽高和周数算出每个格子的边长（宽约束/高约束取小），
 * 夹在 [4, 14]，任何尺寸的卡都摆得下且不模糊。
 *
 * 【日期处理的防御】
 * GitHub 返回 'YYYY-MM-DD' 字符串。parseDateMs 手动拆解而不是直接 new Date(str)：
 * 避免 ISO 字符串被按 UTC 解析导致星期错位（本地时区偏移问题）。
 * =============================================================================
 */

import { ScreenSaverLogger } from '../common/Logger';
import { screenSaverRelativeTime } from '../common/DateFormats';
import { screenSaverMotionOff } from '../common/Motion';
import { screenSaverGitViewModel } from '../model/GitViewModel';
import { screenSaverAppModel } from '../model/AppModel';
import { ScreensaverCardInstance, ScreensaverCardMode } from '../model/ConfigModels';

// 一周 7 天（周日~周六，和 GitHub 一致）。
const GIT_WEEKDAY_COUNT: number = 7;
// 相邻格子的间距（vp）。
const GIT_CELL_GAP: number = 3;
// 三套五级配色：index 0（无提交）→ 4（提交最多）。绿色是 GitHub 经典配色。
const GIT_LEVELS_GREEN: string[] = ['#21262D', '#0E4429', '#006D32', '#26A641', '#39D353'];
const GIT_LEVELS_BLUE: string[] = ['#21262D', '#0A3069', '#0969DA', '#218BFF', '#79C0FF'];
const GIT_LEVELS_GRAY: string[] = ['#1C1C1E', '#2E2E30', '#444446', '#5A5A5C', '#707072'];

@ComponentV2
export struct ScreensaverGitCard {
  @Param card: ScreensaverCardInstance = new ScreensaverCardInstance();
  @Param cardMode: ScreensaverCardMode = 'play';
  /** 屏保在前台时为 true（后台不发起刷新）。 */
  @Param cardActive: boolean = true;
  /** 请求打开配置面板（未配 token 时引导用户去填）。 */
  @Event onRequestConfig: () => void = (): void => {};

  /** 卡片实际宽高（vp），格子大小自适应的依据。 */
  @Local cardW: number = 0;
  @Local cardH: number = 0;

  /**
   * 组件挂载：先注水（有缓存立即显示），再判断是否刷新。
   * 三重条件：播放模式 + 前台 + 节流窗口已过——
   * 每次进屏保不会都打接口，30 分钟内最多一次。
   */
  aboutToAppear(): void {
    screenSaverGitViewModel.hydrateFromCache();
    if (this.cardMode === 'play' && this.cardActive && screenSaverGitViewModel.shouldAutoRefresh()) {
      void screenSaverGitViewModel.refresh(this.card.git.username, this.card.git.offlineCache);
    }
  }

  /** 用户改了用户名：立即拉取新用户的数据。 */
  @Monitor('card.git.username')
  onUsernameChanged(): void {
    void screenSaverGitViewModel.refresh(this.card.git.username, this.card.git.offlineCache);
  }

  /** 回到前台：满足节流条件就补一次刷新。 */
  @Monitor('cardActive')
  onActivityChanged(): void {
    if (this.cardMode === 'play' && this.cardActive && screenSaverGitViewModel.shouldAutoRefresh()) {
      void screenSaverGitViewModel.refresh(this.card.git.username, this.card.git.offlineCache);
    }
  }

  /** 是否处于「离线展示缓存」状态（此时格子用灰阶配色）。 */
  private isOfflineView(): boolean {
    return screenSaverGitViewModel.state === 'offline';
  }

  /** 提交次数 → 颜色级别（0~4）。阈值和 GitHub 官方观感接近。 */
  private levelFor(count: number): number {
    if (count <= 0) {
      return 0;
    }
    if (count <= 3) {
      return 1;
    }
    if (count <= 6) {
      return 2;
    }
    if (count <= 9) {
      return 3;
    }
    return 4;
  }

  /** 级别 → 颜色。优先级：离线灰 > 用户选的配色 > 默认绿。级别越界取两端。 */
  private paletteColor(level: number): string {
    let palette: string[] = GIT_LEVELS_GREEN;
    if (this.isOfflineView()) {
      palette = GIT_LEVELS_GRAY;
    } else if (this.card.git.palette === 'blue') {
      palette = GIT_LEVELS_BLUE;
    } else if (this.card.git.palette === 'gray') {
      palette = GIT_LEVELS_GRAY;
    }
    if (level < 0) {
      return palette[0];
    }
    if (level >= palette.length) {
      return palette[palette.length - 1];
    }
    return palette[level];
  }

  /**
   * 把「每日序列」重组成「周数组」（每周 7 个格子，-1 表示该天无数据）。
   * 重组规则：遇到星期数比上一天小（或相等），说明跨周了，开新的一列；
   * 周内缺失的天补 -1 占位。
   * 最后按用户选择的周数从尾部截取（保留最近的 N 周）。
   */
  private buildWeeks(): number[][] {
    const days = screenSaverGitViewModel.days;
    if (days.length === 0) {
      return [];
    }
    const weeks: number[][] = [];
    let current: number[] = [];
    let lastWeekday = -1;
    for (const day of days) {
      const dayMs = this.parseDateMs(day.date);
      if (dayMs < 0) {
        continue; // 日期解析失败的脏数据直接跳过
      }
      const weekday = new Date(dayMs).getDay();
      // 星期数变小 = 从周六回到周日 = 新的一周开始
      if (weekday <= lastWeekday && current.length > 0) {
        this.pushWeek(weeks, current);
        current = [];
      }
      // 周首日不是周日时，前面的天补 -1
      while (current.length < weekday) {
        current.push(-1);
      }
      current.push(this.levelFor(day.count));
      lastWeekday = weekday;
    }
    if (current.length > 0) {
      this.pushWeek(weeks, current);
    }
    const requested = this.card.git.weeks;
    if (weeks.length > requested) {
      // slice 负索引等价写法：保留最后 requested 周
      return weeks.slice(weeks.length - requested, weeks.length);
    }
    return weeks;
  }

  /** 把一周补满 7 天（缺的天补 -1）后加入周数组。 */
  private pushWeek(weeks: number[][], week: number[]): void {
    while (week.length < GIT_WEEKDAY_COUNT) {
      week.push(-1);
    }
    weeks.push(week);
  }

  /**
   * 'YYYY-MM-DD' → 本地时区的时间戳。
   * 为什么不直接 new Date(date)：ISO 日期字符串会被按 UTC 解析，
   * 东八区会提前 8 小时，导致跨周边界（午夜附近）的星期判断出错。
   * 手动拆出年月日用本地时区构造，杜绝时区偏移。
   * 非法日期返回 -1。
   */
  private parseDateMs(date: string): number {
    const parts = date.split('-');
    if (parts.length !== 3) {
      return -1;
    }
    const year = parseInt(parts[0], 10);
    const month = parseInt(parts[1], 10);
    const day = parseInt(parts[2], 10);
    if (Number.isNaN(year) || Number.isNaN(month) || Number.isNaN(day)) {
      return -1;
    }
    return new Date(year, month - 1, day).getTime();
  }

  /**
   * 计算格子边长：宽约束（去掉内边距和列间距后除以周数）与
   * 高约束（去掉标题/页脚高度后除以 7 行）取较小值，夹在 [4, 14]。
   * 太小看不清、太大一屏放不下，4/14 是经验值。
   */
  private cellSize(): number {
    const weeks = this.buildWeeks();
    const weekCount = weeks.length > 0 ? weeks.length : this.card.git.weeks;
    const width = this.cardW > 0 ? this.cardW : 320;
    const height = this.cardH > 0 ? this.cardH : 120;
    const byWidth = (width - 20 - (weekCount - 1) * GIT_CELL_GAP) / weekCount;
    const byHeight = (height - 46 - (GIT_WEEKDAY_COUNT - 1) * GIT_CELL_GAP) / GIT_WEEKDAY_COUNT;
    const size = Math.min(byWidth, byHeight);
    if (size < 4) {
      return 4;
    }
    if (size > 14) {
      return 14;
    }
    return size;
  }

  /** 底部页脚：正常显示「近 N 周 · x 分钟前更新」，离线时前缀「离线 · 」。 */
  private footerText(): string {
    const weeks = this.buildWeeks();
    const weekCount = weeks.length > 0 ? weeks.length : this.card.git.weeks;
    const relative = screenSaverRelativeTime(screenSaverGitViewModel.fetchedAt, Date.now());
    if (this.isOfflineView()) {
      return `离线 · ${relative}`;
    }
    return `近 ${weekCount} 周 · ${relative}`;
  }

  /** 中部状态文案：加载中/错误信息（success 时为空）。 */
  private statusText(): string {
    const state = screenSaverGitViewModel.state;
    if (state === 'loading') {
      return '刷新中…';
    }
    if (state === 'error') {
      return screenSaverGitViewModel.errorText.length > 0 ? screenSaverGitViewModel.errorText : '加载失败';
    }
    return '';
  }

  /** 弹 toast（播放态点重试但缺 token 时的提示）。 */
  private toast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message, duration: 1500 });
    } catch (err) {
      const error = err as Error;
      ScreenSaverLogger.warn(`toast failed: ${error.message}`);
    }
  }

  /**
   * 主操作（重试按钮）：
   * 缺 token → 编辑态跳配置面板填 token，播放态提示去编辑模式；
   * 有 token → 手动刷新（手动重试不受节流限制，这是用户明确表达意愿）。
   */
  private handlePrimaryAction(): void {
    if (screenSaverAppModel.getGitToken().length === 0) {
      if (this.cardMode === 'edit') {
        this.onRequestConfig();
      } else {
        this.toast('请在编辑模式中打开卡片配置填写 token');
      }
      return;
    }
    void screenSaverGitViewModel.refresh(this.card.git.username, this.card.git.offlineCache);
  }

  /**
   * 界面结构（Column 纵向三段）：
   *   1. 标题行：「GitHub 贡献」+ 右侧刷新动画/重试按钮；
   *   2. 热力图（错误且无数据时显示错误文案）；
   *   3. 页脚：周数 + 更新时间。
   * ForEach 的第三个参数（键生成器）很重要：键含 level/week 内容，
   * 数据变化时 ArkUI 能精确识别哪个格子变了，只刷新那个格子。
   */
  build() {
    Column() {
      Row() {
        Text('GitHub 贡献')
          .fontSize(12)
          .fontColor('#B3B3B3')
          .maxLines(1)
        Blank()
        if (screenSaverGitViewModel.state === 'loading') {
          // 加载中：关动效时用文字，否则用系统转圈动画
          if (screenSaverMotionOff()) {
            Text('刷新中…')
              .fontSize(10)
              .fontColor('#77777D')
          } else {
            LoadingProgress()
              .width(16)
              .height(16)
              .color('#4A9EFF')
          }
        } else if (screenSaverGitViewModel.state === 'error' || screenSaverGitViewModel.state === 'offline') {
          // 出错/离线：编辑态显示「重试」按钮
          if (this.cardMode === 'edit') {
            Column() {
              Text('重试')
                .fontSize(11)
                .fontColor('#4A9EFF')
            }
            .constraintSize({ minWidth: 40, minHeight: 40 })
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
            .margin({ right: -10, top: -4 })
            .onClick((): void => {
              this.handlePrimaryAction();
            })
          }
        }
      }
      .width('100%')

      if (screenSaverGitViewModel.state === 'error' && screenSaverGitViewModel.days.length === 0) {
        // 完全没有数据可显示：只显示错误文案
        Column({ space: 4 }) {
          Text(this.statusText())
            .fontSize(11)
            .fontColor('#8C8C8C')
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        // 热力图：外层 Row 是周（列），内层 Column 是天（行）
        Row({ space: GIT_CELL_GAP }) {
          ForEach(this.buildWeeks(), (week: number[], weekIndex: number) => {
            Column({ space: GIT_CELL_GAP }) {
              ForEach(week, (level: number, dayIndex: number) => {
                Column()
                  .width(this.cellSize())
                  .height(this.cellSize())
                  .borderRadius(2)
                  .backgroundColor(this.paletteColor(level))
              }, (level: number, dayIndex: number): string => `d_${weekIndex}_${dayIndex}_${level}`)
            }
          }, (week: number[], weekIndex: number): string => `w_${weekIndex}_${week.length}`)
        }
        .width('100%')
        .layoutWeight(1)
        .alignItems(VerticalAlign.Center)
      }

      Text(this.footerText())
        .fontSize(10)
        .fontColor('#6E6E73')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 4 })
    }
    .width('100%')
    .height('100%')
    .padding({ left: 10, right: 10, top: 8, bottom: 8 })
    // 记录卡片实际尺寸，供 cellSize 自适应计算
    .onAreaChange((oldArea: Area, newArea: Area): void => {
      this.cardW = typeof newArea.width === 'number' ? newArea.width : 0;
      this.cardH = typeof newArea.height === 'number' ? newArea.height : 0;
    })
  }
}
