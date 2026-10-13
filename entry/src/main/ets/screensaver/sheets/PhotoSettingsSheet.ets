import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import {
  ScreenSaverChip,
  ScreenSaverDeleteCardRow,
  ScreenSaverSheetHeader,
  ScreenSaverToggleRow
} from '../../common/SheetParts';
import { SCREEN_SAVER_COLORS } from '../../common/ScreenSaverStyle';
import { ScreenSaverLogger } from '../../common/Logger';
import { screenSaverAppModel } from '../../model/AppModel';
import { ScreensaverPhotoCard } from '../../cards/PhotoCardView';
import {
  SCREEN_SAVER_PHOTO_INTERVAL_OPTIONS,
  ScreensaverCardInstance,
  ScreensaverNumberOption
} from '../../model/ConfigModels';
import {
  screenSaverMediaAccess,
  screenSaverPhotoAccessFlag,
  ScreenSaverAlbumEntry
} from '../../common/MediaAccess';

const ALBUM_ALL_KEY: string = 'all';
const SAMPLE_PHOTO_NAMES: string[] = [
  'photo_landscape_4k.jpg',
  'photo_portrait.jpg',
  'photo_square.jpg',
  'photo_lowres.jpg',
  'photo_dark.jpg',
  'photo_wide.jpg'
];
const SAMPLE_PHOTO_DIR: string = 'sample_photos';

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

  @Local albumPanelVisible: boolean = false;
  @Local albumEntries: ScreenSaverAlbumEntry[] = [];
  @Local albumsLoaded: boolean = false;
  @Local busy: boolean = false;
  @Local statusText: string = '';
  @Local previewSeed: number = 0;
  @Local allPhotoCount: number = -1;

  private uiContext(): common.UIAbilityContext | undefined {
    return this.getUIContext().getHostContext() as common.UIAbilityContext | undefined;
  }

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

  private async useSamplePhotos(): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    this.statusText = '';
    try {
      const context = this.uiContext();
      if (context === undefined) {
        return;
      }
      const sampleDir = `${context.filesDir}/${SAMPLE_PHOTO_DIR}`;
      const existingUris = await this.ensureSamplePhotos(context, sampleDir);
      if (existingUris.length > 0) {
        this.card.photo.uris = existingUris;
        this.card.photo.sourceAlbum = ALBUM_ALL_KEY;
        screenSaverAppModel.save();
        this.statusText = `已添加 ${existingUris.length} 张示例图片`;
      }
    } finally {
      this.busy = false;
    }
  }

  private async ensureSamplePhotos(context: common.UIAbilityContext, sampleDir: string): Promise<string[]> {
    try {
      fileIo.mkdirSync(sampleDir);
    } catch (mkdirError) {
      ScreenSaverLogger.info('sample photo dir already ready');
    }
    const paths: string[] = [];
    for (const name of SAMPLE_PHOTO_NAMES) {
      const targetPath = `${sampleDir}/${name}`;
      let exists = false;
      try {
        exists = fileIo.accessSync(targetPath);
      } catch (accessError) {
        exists = false;
      }
      if (!exists) {
        const content = await context.resourceManager.getRawFileContent(`${SAMPLE_PHOTO_DIR}/${name}`);
        const file = fileIo.openSync(targetPath, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE);
        try {
          fileIo.writeSync(file.fd, content.buffer as ArrayBuffer);
        } finally {
          fileIo.closeSync(file);
        }
      }
      paths.push(targetPath);
    }
    return paths;
  }

  private clearPhotos(): void {
    this.card.photo.uris = [];
    screenSaverAppModel.save();
    this.statusText = '已清空照片';
  }

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

  private async openPermissionSetting(): Promise<void> {
    const context = this.uiContext();
    if (context === undefined) {
      return;
    }
    await screenSaverMediaAccess.openPermissionSetting(context);
  }

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

  private toast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message, duration: 1500 });
    } catch (err) {
      const error = err as Error;
      ScreenSaverLogger.warn(`toast failed: ${error.message}`);
    }
  }

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

  @Builder
  albumSourcePanel() {
    Column() {
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

  @Builder
  mainPanel() {
    Column() {
      ScreenSaverSheetHeader({
        title: '相册卡片',
        onDone: (): void => {
          this.onDone();
        }
      })
      .padding({ left: 16, right: 16 })

      Scroll() {
        Column({ space: 12 }) {
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

          Row({ space: 8 }) {
            ScreenSaverChip({
              label: this.busy ? '请稍候…' : '从图库选择照片',
              onTap: (): void => {
                void this.pickPhotos();
              }
            })
            ScreenSaverChip({
              label: '示例图片（6 张）',
              onTap: (): void => {
                void this.useSamplePhotos();
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

          ScreenSaverToggleRow({
            label: '自动轮播',
            tip: '间隔下限 15s，关闭后仅手动切换',
            isOn: this.card.photo.intervalSec > 0,
            onChange: (value: boolean): void => {
              this.card.photo.intervalSec = value ? Math.max(15, screenSaverAppModel.layout.settings.defaultIntervalSec) : 0;
              screenSaverAppModel.save();
            }
          })

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

          ScreenSaverToggleRow({
            label: '信息显示',
            tip: '显示拍摄日期，无则显示文件名',
            isOn: this.card.photo.showInfo,
            onChange: (value: boolean): void => {
              this.card.photo.showInfo = value;
              screenSaverAppModel.save();
            }
          })

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
