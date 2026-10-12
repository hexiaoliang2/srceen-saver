import { media } from '@kit.MediaKit';
import { image } from '@kit.ImageKit';
import { fileIo } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { ScreenSaverLogger } from './Logger';

class ScreenSaverVideoThumbService {
  private coverDirReady: boolean = false;

  async firstFrameFile(context: common.UIAbilityContext, uri: string, targetWidth: number,
    targetHeight: number): Promise<string> {
    if (uri.length === 0) {
      return '';
    }
    const dir = `${context.filesDir}/video_covers`;
    if (!this.coverDirReady) {
      try {
        fileIo.mkdirSync(dir);
      } catch (err) {
        ScreenSaverLogger.info('video cover dir already ready');
      }
      this.coverDirReady = true;
    }
    const path = `${dir}/${this.hashKey(uri)}_${targetWidth}x${targetHeight}.jpg`;
    try {
      if (fileIo.accessSync(path)) {
        return path;
      }
    } catch (err) {
      ScreenSaverLogger.info('video cover cache miss');
    }
    const generated = await this.generateCover(uri, path, targetWidth, targetHeight);
    return generated;
  }

  private async generateCover(uri: string, outPath: string, targetWidth: number,
    targetHeight: number): Promise<string> {
    let file: fileIo.File | undefined = undefined;
    let generator: media.AVImageGenerator | undefined = undefined;
    let pixelMap: image.PixelMap | undefined = undefined;
    try {
      file = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
      generator = await media.createAVImageGenerator();
      const fdSrc: media.AVFileDescriptor = { fd: file.fd };
      generator.fdSrc = fdSrc;
      const safeWidth = Math.max(64, Math.min(1280, Math.round(targetWidth)));
      const safeHeight = Math.max(64, Math.min(1280, Math.round(targetHeight)));
      const param: media.PixelMapParams = { width: safeWidth, height: safeHeight };
      pixelMap = await generator.fetchFrameByTime(0, media.AVImageQueryOptions.AV_IMAGE_QUERY_NEXT_SYNC, param);
      const packer = image.createImagePacker();
      try {
        const option: image.PackingOption = { format: 'image/jpeg', quality: 85 };
        const buffer = await packer.packing(pixelMap, option);
        const outFile = fileIo.openSync(outPath,
          fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
        try {
          fileIo.writeSync(outFile.fd, buffer);
        } finally {
          fileIo.closeSync(outFile);
        }
      } finally {
        packer.release();
      }
      ScreenSaverLogger.info(`video cover generated: ${outPath}`);
      return outPath;
    } catch (err) {
      const error = err as Error;
      ScreenSaverLogger.warn(`video cover failed: ${error.message}`);
      return '';
    } finally {
      if (pixelMap !== undefined) {
        try {
          pixelMap.release();
        } catch (releaseErr) {
          ScreenSaverLogger.warn('video cover pixelmap release failed');
        }
      }
      if (generator !== undefined) {
        try {
          generator.release();
        } catch (releaseErr) {
          ScreenSaverLogger.warn('video generator release failed');
        }
      }
      if (file !== undefined) {
        try {
          fileIo.closeSync(file);
        } catch (closeErr) {
          ScreenSaverLogger.warn('video cover file close failed');
        }
      }
    }
  }

  probeReadable(uri: string): boolean {
    if (uri.length === 0) {
      return false;
    }
    let file: fileIo.File | undefined = undefined;
    try {
      file = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
      return true;
    } catch (err) {
      return false;
    } finally {
      if (file !== undefined) {
        try {
          fileIo.closeSync(file);
        } catch (closeErr) {
          ScreenSaverLogger.warn('video probe close failed');
        }
      }
    }
  }

  private hashKey(text: string): string {
    let hash = 0;
    for (let index = 0; index < text.length; index++) {
      hash = (hash * 31 + text.charCodeAt(index)) & 0x7fffffff;
    }
    return hash.toString(36);
  }
}

export const screenSaverVideoThumb: ScreenSaverVideoThumbService = new ScreenSaverVideoThumbService();
