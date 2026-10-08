import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { fileIo } from '@kit.CoreFileKit';
import { ScreenSaverGlowButton } from '../../common/GlowButton';
import { ScreenSaverLogger } from '../../common/Logger';
import { screenSaverAppModel } from '../../model/AppModel';
import { ScreenSaverCardInstance, ScreenSaverNumberOption } from '../../model/ConfigModels';

const SCREEN_SAVER_PHOTO_INTERVAL_OPTIONS: ScreenSaverNumberOption[] = [
  { value: 10, label: '10 秒' },
  { value: 30, label: '30 秒' },
  { value: 60, label: '1 分钟' },
  { value: 300, label: '5 分钟' }
];

const SCREEN_SAVER_SAMPLE_PHOTO_NAMES: string[] = [
  'photo_landscape_4k.jpg',
  'photo_portrait.jpg',
  'photo_square.jpg',
  'photo_lowres.jpg',
  'photo_dark.jpg',
  'photo_wide.jpg'
];

const SCREEN_SAVER_SAMPLE_PHOTO_DIR: string = 'sample_photos';

@ComponentV2
export struct ScreenSaverPhotoSettingsPanel {
  @Param card: ScreenSaverCardInstance = new ScreenSaverCardInstance();
  @Event onDone: () => void = (): void => {};
  @Local sampleBusy: boolean = false;

  private async pickPhotos(): Promise<void> {
    try {
      const options = new photoAccessHelper.PhotoSelectOptions();
      options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      options.maxSelectNumber = 50;
      const picker = new photoAccessHelper.PhotoViewPicker();
      const result = await picker.select(options);
      if (result.photoUris.length > 0) {
        this.card.photo.uris = result.photoUris;
        screenSaverAppModel.save();
      }
    } catch (err) {
      const error = err as BusinessError;
      ScreenSaverLogger.error(`pick photos failed: code=${error.code}, message=${error.message}`);
    }
  }

  private async useSamplePhotos(): Promise<void> {
    if (this.sampleBusy) {
      return;
    }
    this.sampleBusy = true;
    try {
      const context = this.getUIContext().getHostContext();
      if (context === undefined) {
        return;
      }
      const sampleDir = `${context.filesDir}/${SCREEN_SAVER_SAMPLE_PHOTO_DIR}`;
      try {
        fileIo.mkdirSync(sampleDir);
      } catch (mkdirError) {
        ScreenSaverLogger.info('sample photo dir already ready');
      }
      const paths: string[] = [];
      for (const name of SCREEN_SAVER_SAMPLE_PHOTO_NAMES) {
        const targetPath = `${sampleDir}/${name}`;
        let exists = false;
        try {
          exists = fileIo.accessSync(targetPath);
        } catch (accessError) {
          exists = false;
        }
        if (!exists) {
          const content = await context.resourceManager.getRawFileContent(`${SCREEN_SAVER_SAMPLE_PHOTO_DIR}/${name}`);
          const file = fileIo.openSync(targetPath, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE);
          try {
            fileIo.writeSync(file.fd, content.buffer as ArrayBuffer);
          } finally {
            fileIo.closeSync(file);
          }
        }
        paths.push(targetPath);
      }
      this.card.photo.uris = paths;
      screenSaverAppModel.save();
      this.toast(`已添加 ${paths.length} 张示例图片`);
    } catch (err) {
      const error = err as Error;
      ScreenSaverLogger.error(`use sample photos failed: ${error.message}`);
      this.toast('示例图片添加失败，请查看日志');
    } finally {
      this.sampleBusy = false;
    }
  }

  private clearPhotos(): void {
    this.card.photo.uris = [];
    screenSaverAppModel.save();
  }

  private toast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message, duration: 1500 });
    } catch (err) {
      const error = err as Error;
      ScreenSaverLogger.warn(`showToast failed: ${error.message}`);
    }
  }

  build() {
    Column({ space: 10 }) {
      Row() {
        Text('相册设置')
          .fontSize(15)
          .fontColor('#F2F2F2')
        Blank()
        ScreenSaverGlowButton({
          label: '完成',
          textColor: '#8AB4F8',
          fontSize: 13,
          btnHeight: 28,
          hPadding: 12,
          onTap: (): void => {
            this.onDone();
          }
        })
      }
      .width('100%')

      Row() {
        Text(`已选 ${this.card.photo.uris.length} 张照片`)
          .fontSize(14)
          .fontColor('#CCCCCC')
        Blank()
        ScreenSaverGlowButton({
          label: '清空',
          textColor: '#E6A6A6',
          glowColor: '#E67A7A',
          fontSize: 13,
          btnHeight: 28,
          hPadding: 12,
          onTap: (): void => {
            this.clearPhotos();
          }
        })
      }
      .width('100%')

      ScreenSaverGlowButton({
        label: '从图库选择照片',
        textColor: '#FFFFFF',
        baseColor: '#3D6FBF',
        glowColor: '#5B87D9',
        fontSize: 14,
        btnHeight: 40,
        hPadding: 24,
        fullWidth: true,
        onTap: (): void => {
          void this.pickPhotos();
        }
      })

      ScreenSaverGlowButton({
        label: '使用示例图片（6 张）',
        textColor: '#8AB4F8',
        baseColor: '#26262B',
        glowColor: '#4A9EFF',
        fontSize: 14,
        btnHeight: 40,
        hPadding: 24,
        fullWidth: true,
        onTap: (): void => {
          void this.useSamplePhotos();
        }
      })

      Text('示例图片内置在应用内（含横/竖/方形/低分辨率/宽幅），用于快速体验轮播、画质与环境色效果')
        .fontSize(11)
        .fontColor('#777777')
        .width('100%')

      Row() {
        Text('轮播间隔')
          .fontSize(14)
          .fontColor('#CCCCCC')
        Blank()
        ForEach(SCREEN_SAVER_PHOTO_INTERVAL_OPTIONS, (option: ScreenSaverNumberOption) => {
          ScreenSaverGlowButton({
            label: option.label,
            textColor: this.card.photo.intervalSec === option.value ? '#FFFFFF' : '#BBBBBB',
            baseColor: this.card.photo.intervalSec === option.value ? '#3D6FBF' : '#26262B',
            glowColor: '#4A9EFF',
            fontSize: 12,
            btnHeight: 28,
            hPadding: 10,
            marginLeft: 6,
            onTap: (): void => {
              this.card.photo.intervalSec = option.value;
              screenSaverAppModel.save();
            }
          })
        }, (option: ScreenSaverNumberOption): string => option.label)
      }
      .width('100%')

      Row() {
        Text('随机播放')
          .fontSize(14)
          .fontColor('#CCCCCC')
        Blank()
        Toggle({ type: ToggleType.Switch, isOn: this.card.photo.shuffle })
          .selectedColor('#3D6FBF')
          .onChange((isOn: boolean): void => {
            this.card.photo.shuffle = isOn;
            screenSaverAppModel.save();
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding(16)
  }
}
