import { image } from '@kit.ImageKit';
import { fileIo } from '@kit.CoreFileKit';
import { effectKit } from '@kit.ArkGraphics2D';
import { display } from '@kit.ArkUI';
import { ScreenSaverLogger } from './Logger';

const SCREEN_SAVER_DECODE_MAX_EDGE: number = 2160;
const SCREEN_SAVER_DECODE_MIN_EDGE: number = 64;
const SCREEN_SAVER_FALLBACK_DENSITY: number = 3;

export function screenSaverVpToPx(vp: number): number {
  try {
    const displayInfo = display.getDefaultDisplaySync();
    return Math.round(vp * displayInfo.densityPixels);
  } catch (err) {
    return Math.round(vp * SCREEN_SAVER_FALLBACK_DENSITY);
  }
}

export function screenSaverDarkenHex(hex: string, factor: number): string {
  if (hex.length !== 7 || !hex.startsWith('#')) {
    return '#000000';
  }
  const red = parseInt(hex.substring(1, 3), 16);
  const green = parseInt(hex.substring(3, 5), 16);
  const blue = parseInt(hex.substring(5, 7), 16);
  if (Number.isNaN(red) || Number.isNaN(green) || Number.isNaN(blue)) {
    return '#000000';
  }
  return `#${screenSaverChannelHex(red * factor)}${screenSaverChannelHex(green * factor)}${screenSaverChannelHex(blue * factor)}`;
}

function screenSaverChannelHex(value: number): string {
  const clamped = Math.max(0, Math.min(255, Math.round(value)));
  return clamped.toString(16).padStart(2, '0');
}

class ScreenSaverImageLoaderService {
  isValidUri(uri: string): boolean {
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
          ScreenSaverLogger.warn('close probe file failed');
        }
      }
    }
  }

  async decodeForRegion(uri: string, targetWidthPx: number, targetHeightPx: number): Promise<image.PixelMap | undefined> {
    const safeWidth = this.clampEdge(targetWidthPx);
    const safeHeight = this.clampEdge(targetHeightPx);
    let file: fileIo.File | undefined = undefined;
    let source: image.ImageSource | undefined = undefined;
    try {
      file = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
      source = image.createImageSource(file.fd);
      const imageInfo = await source.getImageInfo();
      const originWidth = imageInfo.size.width;
      const originHeight = imageInfo.size.height;
      if (originWidth <= 0 || originHeight <= 0) {
        return undefined;
      }
      const targetRatio = safeWidth / safeHeight;
      let cropWidth = originWidth;
      let cropHeight = Math.round(originWidth / targetRatio);
      if (cropHeight > originHeight) {
        cropHeight = originHeight;
        cropWidth = Math.round(originHeight * targetRatio);
      }
      if (cropWidth <= 0 || cropHeight <= 0) {
        return undefined;
      }
      const cropX = Math.max(0, Math.floor((originWidth - cropWidth) / 2));
      const cropY = Math.max(0, Math.floor((originHeight - cropHeight) / 2));
      const outWidth = Math.min(safeWidth, cropWidth);
      const outHeight = Math.min(safeHeight, cropHeight);
      const region: image.Region = {
        size: { width: cropWidth, height: cropHeight },
        x: cropX,
        y: cropY
      };
      const decodeSize: image.Size = { width: outWidth, height: outHeight };
      const options: image.DecodingOptions = {
        desiredRegion: region,
        desiredSize: decodeSize,
        cropAndScaleStrategy: image.CropAndScaleStrategy.CROP_FIRST
      };
      const pixelMap = await source.createPixelMap(options);
      return pixelMap;
    } catch (err) {
      const error = err as Error;
      ScreenSaverLogger.error(`decode failed: ${error.message}, uri=${uri}`);
      return undefined;
    } finally {
      if (source !== undefined) {
        try {
          source.release();
        } catch (releaseErr) {
          ScreenSaverLogger.warn('image source release failed');
        }
      }
      if (file !== undefined) {
        try {
          fileIo.closeSync(file);
        } catch (closeErr) {
          ScreenSaverLogger.warn('decode file close failed');
        }
      }
    }
  }

  async extractMainColor(pixelMap: image.PixelMap): Promise<string | undefined> {
    try {
      const picker = await effectKit.createColorPicker(pixelMap);
      const color = picker.getMainColorSync();
      return `#${this.channelHex(color.red)}${this.channelHex(color.green)}${this.channelHex(color.blue)}`;
    } catch (err) {
      const error = err as Error;
      ScreenSaverLogger.error(`extract main color failed: ${error.message}`);
      return undefined;
    }
  }

  private clampEdge(value: number): number {
    const rounded = Math.round(value);
    if (rounded < SCREEN_SAVER_DECODE_MIN_EDGE) {
      return SCREEN_SAVER_DECODE_MIN_EDGE;
    }
    if (rounded > SCREEN_SAVER_DECODE_MAX_EDGE) {
      return SCREEN_SAVER_DECODE_MAX_EDGE;
    }
    return rounded;
  }

  private channelHex(value: number): string {
    const clamped = Math.max(0, Math.min(255, Math.round(value)));
    return clamped.toString(16).padStart(2, '0');
  }
}

export const screenSaverImageLoader: ScreenSaverImageLoaderService = new ScreenSaverImageLoaderService();
