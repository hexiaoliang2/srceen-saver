/**
 * =============================================================================
 * 图片解码与颜色工具（ImageLoader.ets）
 * =============================================================================
 *
 * 【这个文件是干什么的】
 * 负责把磁盘上的图片文件解码成系统能显示的 PixelMap，并做两件重要优化：
 *   1. 「按显示尺寸等比解码」（变更项 4）：先读原图宽高，按「等比完全显示」
 *      （contain，不裁切）算出它在卡片里实际占的像素，再按这个尺寸让解码器
 *      子采样输出——既不整张原图解码，也不会把位图放大后显示导致模糊。
 *   2. 「主色提取」：从照片里取一个代表色，用于「加载中」占位底色。
 *
 * 【为什么按需解码很关键】
 * 屏保要长时间驻留内存。如果每次切照片都把原图整个解码（可能 30MB+），
 * 内存会频繁暴涨甚至被系统杀掉。按「实际显示尺寸」解码后，
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
import {
  screenSaverDecideFit,
  screenSaverFittedSize,
  ScreenSaverFitDecision,
  ScreenSaverFitSize
} from './ContentFit';

// 解码目标长边的上限：太大会浪费内存（2160 即 2K 屏级），由 screenSaverFittedSize 兜底。
const SCREEN_SAVER_DECODE_MAX_EDGE: number = 2160;
// 拿不到屏幕密度时的兜底值（3 倍屏是目前主流旗舰的密度）。
const SCREEN_SAVER_FALLBACK_DENSITY: number = 3;

/**
 * 等比完整解码的结果（变更项 4）。
 * contentWidth/contentHeight 是解出来的位图尺寸（px），decision 是「该不该有黑边」的判据结论。
 */
export interface ScreenSaverFittedDecode {
  pixelMap: image.PixelMap;
  contentWidth: number;
  contentHeight: number;
  decision: ScreenSaverFitDecision;
}

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
   * 核心（变更项 4）：把整张照片**等比完整解码**到「卡片里的实际显示尺寸」。
   *
   * 与旧的裁剪解码（decodeForRegion）的区别：
   *   - 旧版按卡片宽高比在原图中央裁一块再缩放 —— 会**裁切**画面；
   *   - 新版先读原图宽高，用 screenSaverFittedSize 算出「等比放进卡片显示区」
   *     的像素尺寸（contain，绝不裁切、绝不放大），只把 desiredSize 交给解码器，
   *     不给 desiredRegion。
   *
   * 流程：
   *   1. 打开文件、创建解码器（ImageSource），读原图宽高；
   *   2. screenSaverFittedSize(原图 → 容器) 得到解码尺寸（长边夹在 2160 以内防内存）；
   *   3. createPixelMap({ desiredSize }) —— 解码器按目标尺寸子采样输出，
   *      既不是整张原图，也不会小于显示尺寸导致拉伸模糊；
   *   4. screenSaverDecideFit 给出「该不该有黑边、在哪一侧」的判据结论（供日志与验证）；
   *   5. finally 里依次释放 source 和 file。
   *
   * @param containerWidthPx  卡片显示区宽（px，= 卡片实际像素宽）
   * @param containerHeightPx 卡片显示区高（px）
   */
  async decodeFitted(uri: string, containerWidthPx: number,
    containerHeightPx: number): Promise<ScreenSaverFittedDecode | undefined> {
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
      const fitted: ScreenSaverFitSize = screenSaverFittedSize(originWidth, originHeight,
        containerWidthPx, containerHeightPx, SCREEN_SAVER_DECODE_MAX_EDGE);
      const decodeSize: image.Size = { width: fitted.width, height: fitted.height };
      const options: image.DecodingOptions = { desiredSize: decodeSize };
      const pixelMap = await source.createPixelMap(options);
      const decision = screenSaverDecideFit(fitted.width, fitted.height, containerWidthPx, containerHeightPx);
      const result: ScreenSaverFittedDecode = {
        pixelMap: pixelMap,
        contentWidth: fitted.width,
        contentHeight: fitted.height,
        decision: decision
      };
      return result;
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
   * 相册卡片用它给「加载中」占位底色调色（照片显示出来后统一用黑边色）。
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

  /** 颜色通道数值 → 两位十六进制。 */
  private channelHex(value: number): string {
    const clamped = Math.max(0, Math.min(255, Math.round(value)));
    return clamped.toString(16).padStart(2, '0');
  }
}

// 导出全局唯一实例（单例）。
export const screenSaverImageLoader: ScreenSaverImageLoaderService = new ScreenSaverImageLoaderService();
