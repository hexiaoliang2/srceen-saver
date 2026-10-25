/**
 * =============================================================================
 * 相册卡片设置面板（PhotoSettingsSheet.ets）
 * =============================================================================
 *
 * 【这个文件是干什么的】
 * 相册卡片的设置抽屉，是四个设置面板里最复杂的一个。
 * 功能分两大块：
 *   1. 照片来源：两种方式——
 *      a. 从图库选择照片（系统 picker，无需任何权限）；
 *      b. 浏览系统相册（需要相册读取权限，可选「全部照片/收藏/用户相册」）。
 *   2. 播放行为：自动轮播（间隔下限 15s）、切换间隔、播放顺序（随机/时间序）、
 *      信息显示（拍摄日期/文件名）、预取下一张、删除卡片。
 *
 * 【双面板结构】
 * build() 里用 albumPanelVisible 在两个 @Builder 之间切换：
 *   - mainPanel：主设置面板；
 *   - albumSourcePanel：点「来源相册」进入的相册选择子面板（含返回按钮）。
 *
 * 【权限设计的三个层次】
 *   - picker 方式：系统代取，零权限，永远可用（保底方案）；
 *   - 浏览相册：需要权限，首次点击「加载相册列表」时现场申请；
 *   - 被永久拒绝：不再弹窗，显示「去开启权限」按钮跳系统设置。
 * =============================================================================
 */

import { common } from '@kit.AbilityKit';
import {
  ScreenSaverChip,
  ScreenSaverDeleteCardRow,
  ScreenSaverSheetHeader,
  ScreenSaverToggleRow,
} from '../../common/SheetParts';
import { SCREEN_SAVER_COLORS } from '../../common/ScreenSaverStyle';
import { ScreenSaverLogger } from '../../common/Logger';
import { screenSaverAppModel } from '../../model/AppModel';
import { ScreensaverPhotoCard } from '../../cards/PhotoCardView';
import {
  SCREEN_SAVER_PHOTO_INTERVAL_OPTIONS,
  ScreensaverCardInstance,
  ScreensaverNumberOption,
} from '../../model/ConfigModels';
import {
  screenSaverMediaAccess,
  screenSaverPhotoAccessFlag,
  ScreenSaverAlbumEntry
} from '../../common/MediaAccess';

/** 「全部照片」相册的固定标识（区别于真实相册 key）。 */
const ALBUM_ALL_KEY: string = 'all';

interface PhotoOrderOption {
  value: string;
  label: string;
}

const ORDER_OPTIONS: PhotoOrderOption[] = [
  { value: 'shuffle', label: '随机' },
  { value: 'time', label: '时间序' }
];

@ComponentV2
export struct ScreenSaverPhotoSettingsPanel {
  @Param card: ScreensaverCardInstance = new ScreensaverCardInstance();
  @Event onDone: () => void = (): void => {};
  @Event onDelete: () => void = (): void => {};

  /** 是否显示相册选择子面板（false = 主面板）。 */
  @Local albumPanelVisible: boolean = false;
  /** 系统相册列表（进入子面板时加载）。 */
  @Local albumEntries: ScreenSaverAlbumEntry[] = [];
  /** 相册列表是否已成功加载过（控制「需授权」提示块的显隐）。 */
  @Local albumsLoaded: boolean = false;
  /** 异步操作进行中标志（防重复点击）。 */
  @Local busy: boolean = false;
  /** 底部状态文案（如「已选择 12 张照片」）。 */
  @Local statusText: string = '';
  /** 预览区的手动换图种子：点一次预览 +1，PhotoCard 收到变化就切下一张。 */
  @Local previewSeed: number = 0;
  /** 「全部照片」的总张数（-1 表示还没查过）。 */
  @Local allPhotoCount: number = -1;

  private uiContext(): common.UIAbilityContext | undefined {
    return this.getUIContext().getHostContext() as common.UIAbilityContext | undefined;
  }

  /**
   * 方式一：系统 picker 选照片（最多 50 张）。
   * 零权限、一次可多选；选完直接写入 card.photo.uris 并持久化。
   */
  private async pickPhotos(): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    this.statusText = '';
    try {
      const uris = await screenSaverMediaAccess.pickImages(50);
      if (uris.length > 0) {
        this.card.photo.uris = uris;
        this.card.photo.sourceAlbum = ALBUM_ALL_KEY;
        screenSaverAppModel.save();
        this.statusText = `已选择 ${uris.length} 张照片`;
      }
    } finally {
      this.busy = false;
    }
  }

  /** 清空照片列表（卡片会显示空态占位）。 */
  private clearPhotos(): void {
    this.card.photo.uris = [];
    screenSaverAppModel.save();
    this.statusText = '已清空照片';
  }

  /**
   * 方式二的前置步骤：加载系统相册列表。
   * 先现场申请相册读取权限；被拒绝则记入标记（用于显示「去开启权限」按钮）
   * 并提示用户仍可用 picker 方式。
   */
  private async loadAlbums(): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    try {
      const context = this.uiContext();
      if (context === undefined) {
        return;
      }
      const granted = await screenSaverMediaAccess.requestPhotoPermission(context);
      if (!granted) {
        screenSaverPhotoAccessFlag.albumDenied = true;
        this.statusText = '未获得相册访问权限';
        return;
      }
      screenSaverPhotoAccessFlag.albumDenied = false;
      const entries = await screenSaverMediaAccess.listAlbums(context);
      this.albumEntries = entries;
      this.albumsLoaded = true;
      this.allPhotoCount = await screenSaverMediaAccess.countAllAssets(context);
      this.statusText = entries.length > 0 ? '' : '未发现可用相册，可使用「从图库选择照片」';
    } finally {
      this.busy = false;
    }
  }

  /**
   * 选中某个相册：拉取该相册全部照片的 uri + 拍摄日期，
   * 写入卡片并持久化，然后退回主面板。
   * uriDates 是「uri → 日期」映射，供卡片空态/信息条显示拍摄日期。
   */
  private async selectAlbum(key: string): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    this.statusText = '正在读取相册…';
    try {
      const context = this.uiContext();
      if (context === undefined) {
        return;
      }
      const entries = await screenSaverMediaAccess.fetchAlbumImageEntries(context, key);
      if (entries.length === 0) {
        this.statusText = '该相册为空或读取失败';
        return;
      }
      const uris: string[] = [];
      const dates: Record<string, string> = {};
      for (const entry of entries) {
        uris.push(entry.uri);
        if (entry.dateTaken.length > 0) {
          dates[entry.uri] = entry.dateTaken;
        }
      }
      this.card.photo.uris = uris;
      this.card.photo.uriDates = dates;
      this.card.photo.sourceAlbum = key;
      screenSaverAppModel.save();
      this.statusText = `已载入 ${uris.length} 张照片`;
      this.albumPanelVisible = false;
    } finally {
      this.busy = false;
    }
  }

  /** 跳系统授权设置界面（权限被永久拒绝后的补救入口）。 */
  private async openPermissionSetting(): Promise<void> {
    const context = this.uiContext();
    if (context === undefined) {
      return;
    }
    await screenSaverMediaAccess.openPermissionSetting(context);
  }

  /**
   * 来源相册的显示名：
   * 'all' → 全部照片；'favorite' → 收藏；'user:xxx' → 去掉前缀显示相册名。
   */
  private albumLabel(): string {
    const key = this.card.photo.sourceAlbum;
    if (key === ALBUM_ALL_KEY) {
      return '全部照片';
    }
    if (key === 'favorite') {
      return '收藏';
    }
    if (key.startsWith('user:')) {
      return key.substring(5);
    }
    return key;
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
   * 千分位格式化（12345 → 12,345）。
   * 手写循环实现，避免依赖 Intl（ArkTS 环境下更可控）。
   */
  private formatCount(value: number): string {
    const text = value.toString();
    let out = '';
    let digits = 0;
    for (let index = text.length - 1; index >= 0; index--) {
      out = text.charAt(index) + out;
      digits++;
      if (digits % 3 === 0 && index > 0) {
        out = `,${out}`;
      }
    }
    return out;
  }

  /** 面板标题：带实例标识（如「相册 1 · 设置」），便于核对面板归属哪张卡片。 */
  private panelTitle(): string {
    return `${screenSaverAppModel.cardInstanceTitle(this.card)} · 设置`;
  }

  /**
   * ================= 相册选择子面板 =================
   * 「全部照片」+ 系统相册列表 + 「新建相册…」（引导去系统图库）。
   * 未加载过列表时显示授权提示块；被拒过后追加「去开启权限」按钮。
   */
  @Builder
  albumSourcePanel() {
    Column() {
      // ---------- 子面板顶栏 ----------
      Row() {
        Text('选择相册')
          .fontSize(15)
          .fontColor(SCREEN_SAVER_COLORS.textPrimary)
        Blank()
        Text('返回')
          .fontSize(13)
          .fontColor(SCREEN_SAVER_COLORS.accent)
          .padding({ left: 10, right: 2, top: 11, bottom: 11 })
          .onClick((): void => {
            this.albumPanelVisible = false;
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16 })

      Scroll() {
        Column({ space: 8 }) {
          // ---------- 全部照片 ----------
          Row() {
            Text('全部照片')
              .fontSize(14)
              .fontColor(this.card.photo.sourceAlbum === ALBUM_ALL_KEY ?
              SCREEN_SAVER_COLORS.accent : '#CCCCCC')
            Blank()
            if (this.allPhotoCount >= 0) {
              Text(this.formatCount(this.allPhotoCount))
                .fontSize(12)
                .fontColor(SCREEN_SAVER_COLORS.textTertiary)
                .margin({ right: 8 })
            }
            if (this.card.photo.sourceAlbum === ALBUM_ALL_KEY) {
              Text('✓')
                .fontSize(14)
                .fontColor(SCREEN_SAVER_COLORS.accent)
            }
          }
          .width('100%')
          .padding({ top: 8, bottom: 8 })
          .onClick((): void => {
            void this.selectAlbum(ALBUM_ALL_KEY);
          })

          // ---------- 系统相册列表 ----------
          ForEach(this.albumEntries, (entry: ScreenSaverAlbumEntry) => {
            Row() {
              Text(entry.name)
                .fontSize(14)
                .fontColor(this.card.photo.sourceAlbum === entry.key ?
                SCREEN_SAVER_COLORS.accent : '#CCCCCC')
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)
              if (entry.count >= 0) {
                Text(this.formatCount(entry.count))
                  .fontSize(12)
                  .fontColor(SCREEN_SAVER_COLORS.textTertiary)
                  .margin({ left: 8, right: 8 })
              }
              if (this.card.photo.sourceAlbum === entry.key) {
                Text('✓')
                  .fontSize(14)
                  .fontColor(SCREEN_SAVER_COLORS.accent)
              }
            }
            .width('100%')
            .padding({ top: 8, bottom: 8 })
            .onClick((): void => {
              void this.selectAlbum(entry.key);
            })
          }, (entry: ScreenSaverAlbumEntry): string => entry.key)

          // ---------- 新建相册（引导） ----------
          // 三方应用无法替用户建相册，只能提示去系统图库操作。
          Row() {
            Text('新建相册…')
              .fontSize(13)
              .fontColor(SCREEN_SAVER_COLORS.textTertiary)
          }
          .width('100%')
          .padding({ top: 8, bottom: 8 })
          .onClick((): void => {
            this.toast('请在系统图库中新建相册后再回到这里选择');
          })

          // ---------- 授权提示块（列表未加载时显示） ----------
          if (!this.albumsLoaded) {
            Text('浏览系统相册需要相册读取权限；也可以直接使用「从图库选择照片」，无需授权')
              .fontSize(11)
              .fontColor(SCREEN_SAVER_COLORS.textTertiary)
              .width('100%')
              .margin({ top: 4 })
            Row({ space: 8 }) {
              ScreenSaverChip({
                label: this.busy ? '加载中…' : '加载相册列表（需授权）',
                onTap: (): void => {
                  void this.loadAlbums();
                }
              })
              if (screenSaverPhotoAccessFlag.albumDenied) {
                ScreenSaverChip({
                  label: '去开启权限',
                  onTap: (): void => {
                    void this.openPermissionSetting();
                  }
                })
              }
            }
            .width('100%')
          }

          if (this.statusText.length > 0) {
            Text(this.statusText)
              .fontSize(12)
              .fontColor(SCREEN_SAVER_COLORS.textSecondary)
              .width('100%')
          }
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

  /**
   * ================= 主设置面板 =================
   * 实时预览（点击可手动换图）→ 来源相册/三个操作按钮 →
   * 自动轮播/间隔/顺序 → 信息显示/预取 → 删除卡片。
   */
  @Builder
  mainPanel() {
    Column() {
      ScreenSaverSheetHeader({
        title: this.panelTitle(),
        onDone: (): void => {
          this.onDone();
        }
      })
      .padding({ left: 16, right: 16 })

      Scroll() {
        Column({ space: 12 }) {
          // ---------- 实时预览 ----------
          // 点一下预览区就手动切换下一张（previewSeed+1 触发卡片刷新）。
          Column() {
            ScreensaverPhotoCard({
              card: this.card,
              cardMode: 'edit',
              cardActive: false,
              manualAdvanceSeed: this.previewSeed
            })
          }
          .width('100%')
          .height(140)
          .borderRadius(8)
          .backgroundColor(SCREEN_SAVER_COLORS.cardBg)
          .clip(true)
          .onClick((): void => {
            this.previewSeed++;
          })

          // ---------- 来源相册入口 ----------
          Row() {
            Text('来源相册')
              .fontSize(14)
              .fontColor('#CCCCCC')
            Blank()
            Text(this.albumLabel())
              .fontSize(13)
              .fontColor(SCREEN_SAVER_COLORS.accent)
              .padding({ top: 8, bottom: 8 })
              .onClick((): void => {
                this.albumPanelVisible = true;
              })
          }
          .width('100%')

          // ---------- 来源操作 ----------
          Row({ space: 8 }) {
            ScreenSaverChip({
              label: this.busy ? '请稍候…' : '从图库选择照片',
              onTap: (): void => {
                void this.pickPhotos();
              }
            })
            ScreenSaverChip({
              label: '清空',
              onTap: (): void => {
                this.clearPhotos();
              }
            })
          }
          .width('100%')

          // ---------- 已选数量 + 状态 ----------
          Row() {
            Text(`已选 ${this.card.photo.uris.length} 张`)
              .fontSize(12)
              .fontColor(SCREEN_SAVER_COLORS.textTertiary)
            Blank()
            if (this.statusText.length > 0) {
              Text(this.statusText)
                .fontSize(12)
                .fontColor(SCREEN_SAVER_COLORS.textSecondary)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
          }
          .width('100%')

          // ---------- 自动轮播 ----------
          // intervalSec === 0 表示关闭；打开时取默认间隔（下限 15s）。
          ScreenSaverToggleRow({
            label: '自动轮播',
            tip: '间隔下限 15s，关闭后仅手动切换',
            isOn: this.card.photo.intervalSec > 0,
            onChange: (value: boolean): void => {
              this.card.photo.intervalSec = value ? Math.max(15, screenSaverAppModel.layout.settings.defaultIntervalSec) : 0;
              screenSaverAppModel.save();
            }
          })

          // ---------- 切换间隔（仅开启轮播时显示） ----------
          if (this.card.photo.intervalSec > 0) {
            Row() {
              Text('切换间隔')
                .fontSize(14)
                .fontColor('#CCCCCC')
              Blank()
              Row({ space: 8 }) {
                ForEach(SCREEN_SAVER_PHOTO_INTERVAL_OPTIONS, (seconds: number) => {
                  ScreenSaverChip({
                    label: `${seconds}s`,
                    selected: this.card.photo.intervalSec === seconds,
                    onTap: (): void => {
                      this.card.photo.intervalSec = seconds;
                      screenSaverAppModel.save();
                    }
                  })
                }, (seconds: number): string => `interval_${seconds}`)
              }
            }
            .width('100%')
          }

          // ---------- 播放顺序 ----------
          Row() {
            Text('播放顺序')
              .fontSize(14)
              .fontColor('#CCCCCC')
            Blank()
            Row({ space: 8 }) {
              ForEach(ORDER_OPTIONS, (option: PhotoOrderOption) => {
                ScreenSaverChip({
                  label: option.label,
                  selected: this.card.photo.order === option.value,
                  onTap: (): void => {
                    this.card.photo.order = option.value === 'shuffle' ? 'shuffle' : 'time';
                    screenSaverAppModel.save();
                  }
                })
              }, (option: PhotoOrderOption): string => option.value)
            }
          }
          .width('100%')

          // ---------- 信息显示 ----------
          // 显示拍摄日期（无则回退文件名）。
          ScreenSaverToggleRow({
            label: '信息显示',
            tip: '显示拍摄日期，无则显示文件名',
            isOn: this.card.photo.showInfo,
            onChange: (value: boolean): void => {
              this.card.photo.showInfo = value;
              screenSaverAppModel.save();
            }
          })

          // ---------- 预取下一张 ----------
          ScreenSaverToggleRow({
            label: '预取下一张',
            tip: '提前准备下一张照片，切换更顺滑',
            isOn: this.card.photo.wifiOnlyPrefetch,
            onChange: (value: boolean): void => {
              this.card.photo.wifiOnlyPrefetch = value;
              screenSaverAppModel.save();
            }
          })

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

  build() {
    Column() {
      if (this.albumPanelVisible) {
        this.albumSourcePanel()
      } else {
        this.mainPanel()
      }
    }
    .width('100%')
  }
}
