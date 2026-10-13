/**
 * =============================================================================
 * 图片解码与颜色工具（ImageLoader.ets）
 * =============================================================================
 *
 * 【这个文件是干什么的】
 * 负责把磁盘上的图片文件解码成系统能显示的 PixelMap，并做两件重要优化：
 *   1. 「按需裁剪解码」：只解码照片中会被显示的那一块区域，并缩放到
 *      卡片实际大小，而不是把整张 4000 万像素的照片全部读进内存。
 *   2. 「主色提取」：从照片里取一个代表色，用于相册卡片的环境光晕。
 *
 * 【为什么按需解码很关键】
 * 屏保要长时间驻留内存。如果每次切照片都把原图整个解码（可能 30MB+），
 * 内存会频繁暴涨甚至被系统杀掉。按「显示区域 + 目标尺寸」解码后，
 * 每张图只占几百 KB，稳定得多。
 *
 * 【资源释放的铁律】
 * file（文件句柄）、ImageSource（解码器）、PixelMap（位图）都是系统资源，
 * 用完必须在 finally 里逐个释放——否则句柄泄漏积累后会打开文件失败。
 * =============================================================================
 */

import { image } from '@kit.ImageKit';
import { fileIo } from '@kit.CoreFileKit';
import { effectKit } from '@kit.ArkGraphics2D';
import { display } from '@kit.ArkUI';
import { ScreenSaverLogger } from './Logger';

// 解码目标边长的上下限：太小会糊（<64px），太大会浪费内存（>2160 即 2K 屏级）。
const SCREEN_SAVER_DECODE_MAX_EDGE: number = 2160;
const SCREEN_SAVER_DECODE_MIN_EDGE: number = 64;
// 拿不到屏幕密度时的兜底值（3 倍屏是目前主流旗舰的密度）。
const SCREEN_SAVER_FALLBACK_DENSITY: number = 3;

/**
 * vp（虚拟像素）转 px（物理像素）。
 * 为什么需要转换：ArkUI 布局用 vp（与设备无关），而解码尺寸必须用 px。
 * 屏幕密度从 display 模块拿；拿不到时用兜底值 3，宁可图稍大也不糊。
 */
export function screenSaverVpToPx(vp: number): number {
  try {
    const displayInfo = display.getDefaultDisplaySync();
    return Math.round(vp * displayInfo.densityPixels);
  } catch (err) {
    return Math.round(vp * SCREEN_SAVER_FALLBACK_DENSITY);
  }
}

/**
 * 把 '#RRGGBB' 颜色按系数调暗（factor<1 变暗，>1 变亮）。
 * 用途：相册卡片根据照片主色生成深浅搭配的背景色。
 * 非法输入（不是 7 位 # 开头、解析失败）一律返回纯黑，保证不崩溃。
 */
export function screenSaverDarkenHex(hex: string, factor: number): string {
  if (hex.length !== 7 || !hex.startsWith('#')) {
    return '#000000';
  }
  // 逐段把十六进制文本解析成 0~255 的数字：#RR GG BB
  const red = parseInt(hex.substring(1, 3), 16);
  const green = parseInt(hex.substring(3, 5), 16);
  const blue = parseInt(hex.substring(5, 7), 16);
  if (Number.isNaN(red) || Number.isNaN(green) || Number.isNaN(blue)) {
    return '#000000';
  }
  return `#${screenSaverChannelHex(red * factor)}${screenSaverChannelHex(green * factor)}${screenSaverChannelHex(blue * factor)}`;
}

/** 单个颜色通道数值 → 两位十六进制（夹在 0~255，防止越界）。 */
function screenSaverChannelHex(value: number): string {
  const clamped = Math.max(0, Math.min(255, Math.round(value)));
  return clamped.toString(16).padStart(2, '0');
}

class ScreenSaverImageLoaderService {
  /**
   * 探测一个 uri 的文件当前是否可读（比如照片被删除、权限被收回后变不可读）。
   * 实现：试着只读打开一次，成功即可读。
   * 无论结果如何，finally 里都把探测用的句柄关掉，避免泄漏。
   */
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

  /**
   * 核心：按「目标区域 + 目标尺寸」解码照片。
   * 流程：
   *   1. 尺寸夹取到 [64, 2160]，防止极端值；
   *   2. 打开文件、创建解码器（ImageSource），先读原图宽高；
   *   3. 计算居中裁剪区域：按目标宽高比在原图中间裁一块
   *      （先假设以原图宽为准算高；如果超出原图高，再反过来以高为准算宽）；
   *   4. 用 desiredRegion（只解码这块）+ desiredSize（缩放到目标大小）解码，
   *      CROP_FIRST 策略表示「先裁剪再缩放」，最省内存；
   *   5. finally 里依次释放 source 和 file。
   */
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
      // 目标宽高比 → 在原图上找一个同样比例的居中矩形
      const targetRatio = safeWidth / safeHeight;
      let cropWidth = originWidth;
      let cropHeight = Math.round(originWidth / targetRatio);
      if (cropHeight > originHeight) {
        // 以宽为准裁出来的高度超出原图：改为以高为准
        cropHeight = originHeight;
        cropWidth = Math.round(originHeight * targetRatio);
      }
      if (cropWidth <= 0 || cropHeight <= 0) {
        return undefined;
      }
      // 居中：裁剪区左上角 = (原图 - 裁剪区) / 2
      const cropX = Math.max(0, Math.floor((originWidth - cropWidth) / 2));
      const cropY = Math.max(0, Math.floor((originHeight - cropHeight) / 2));
      // 输出尺寸不能超过裁剪区本身（放大没有意义）
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
      // 释放顺序：先解码器后文件句柄（解码器还依赖着文件 fd）。
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

  /**
   * 提取一张图的主色（返回 '#RRGGBB'）。
   * 用系统图形库 effectKit 的取色器：传入 PixelMap，拿到 RGB 主色。
   * 相册卡片用它生成与照片呼应的环境光晕颜色。
   * 失败返回 undefined，调用方用默认色兜底。
   */
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

  /** 解码边长夹取到 [64, 2160]：防糊、防浪费内存。 */
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

  /** 颜色通道数值 → 两位十六进制。 */
  private channelHex(value: number): string {
    const clamped = Math.max(0, Math.min(255, Math.round(value)));
    return clamped.toString(16).padStart(2, '0');
  }
}

// 导出全局唯一实例（单例）。
export const screenSaverImageLoader: ScreenSaverImageLoaderService = new ScreenSaverImageLoaderService();
