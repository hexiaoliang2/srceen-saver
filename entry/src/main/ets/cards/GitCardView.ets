import { ScreenSaverLogger } from '../common/Logger';
import { screenSaverRelativeTime } from '../common/DateFormats';
import { screenSaverMotionOff } from '../common/Motion';
import { screenSaverGitViewModel } from '../model/GitViewModel';
import { screenSaverAppModel } from '../model/AppModel';
import { ScreensaverCardInstance, ScreensaverCardMode } from '../model/ConfigModels';

const GIT_WEEKDAY_COUNT: number = 7;
const GIT_CELL_GAP: number = 3;
const GIT_LEVELS_GREEN: string[] = ['#21262D', '#0E4429', '#006D32', '#26A641', '#39D353'];
const GIT_LEVELS_BLUE: string[] = ['#21262D', '#0A3069', '#0969DA', '#218BFF', '#79C0FF'];
const GIT_LEVELS_GRAY: string[] = ['#1C1C1E', '#2E2E30', '#444446', '#5A5A5C', '#707072'];

@ComponentV2
export struct ScreensaverGitCard {
  @Param card: ScreensaverCardInstance = new ScreensaverCardInstance();
  @Param cardMode: ScreensaverCardMode = 'play';
  @Param cardActive: boolean = true;
  @Event onRequestConfig: () => void = (): void => {};

  @Local cardW: number = 0;
  @Local cardH: number = 0;

  aboutToAppear(): void {
    screenSaverGitViewModel.hydrateFromCache();
    if (this.cardMode === 'play' && this.cardActive && screenSaverGitViewModel.shouldAutoRefresh()) {
      void screenSaverGitViewModel.refresh(this.card.git.username, this.card.git.offlineCache);
    }
  }

  @Monitor('card.git.username')
  onUsernameChanged(): void {
    void screenSaverGitViewModel.refresh(this.card.git.username, this.card.git.offlineCache);
  }

  @Monitor('cardActive')
  onActivityChanged(): void {
    if (this.cardMode === 'play' && this.cardActive && screenSaverGitViewModel.shouldAutoRefresh()) {
      void screenSaverGitViewModel.refresh(this.card.git.username, this.card.git.offlineCache);
    }
  }

  private isOfflineView(): boolean {
    return screenSaverGitViewModel.state === 'offline';
  }

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
        continue;
      }
      const weekday = new Date(dayMs).getDay();
      if (weekday <= lastWeekday && current.length > 0) {
        this.pushWeek(weeks, current);
        current = [];
      }
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
      return weeks.slice(weeks.length - requested, weeks.length);
    }
    return weeks;
  }

  private pushWeek(weeks: number[][], week: number[]): void {
    while (week.length < GIT_WEEKDAY_COUNT) {
      week.push(-1);
    }
    weeks.push(week);
  }

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

  private footerText(): string {
    const weeks = this.buildWeeks();
    const weekCount = weeks.length > 0 ? weeks.length : this.card.git.weeks;
    const relative = screenSaverRelativeTime(screenSaverGitViewModel.fetchedAt, Date.now());
    if (this.isOfflineView()) {
      return `离线 · ${relative}`;
    }
    return `近 ${weekCount} 周 · ${relative}`;
  }

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

  private toast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message, duration: 1500 });
    } catch (err) {
      const error = err as Error;
      ScreenSaverLogger.warn(`toast failed: ${error.message}`);
    }
  }

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

  build() {
    Column() {
      Row() {
        Text('GitHub 贡献')
          .fontSize(12)
          .fontColor('#B3B3B3')
          .maxLines(1)
        Blank()
        if (screenSaverGitViewModel.state === 'loading') {
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
          Text('重试')
            .fontSize(11)
            .fontColor('#4A9EFF')
            .onClick((): void => {
              this.handlePrimaryAction();
            })
        }
      }
      .width('100%')

      if (screenSaverGitViewModel.state === 'error' && screenSaverGitViewModel.days.length === 0) {
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
    .onAreaChange((oldArea: Area, newArea: Area): void => {
      this.cardW = typeof newArea.width === 'number' ? newArea.width : 0;
      this.cardH = typeof newArea.height === 'number' ? newArea.height : 0;
    })
  }
}
