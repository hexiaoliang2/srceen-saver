/**
 * =============================================================================
 * 视频封面帧生成器（VideoThumb.ets）
 * =============================================================================
 *
 * 【这个文件是干什么的】
 * 给视频卡片生成「封面图」（视频第 0 秒的画面），并把结果缓存成
 * 应用私有目录里的 jpg 文件。这样播放/编辑态都能先展示封面，
 * 不用一直开着视频解码器（省电的关键）。
 *
 * 【为什么必须缓存成文件】
 * 直接用 AVImageGenerator 每次现取封面帧需要打开视频、定位、解码，
 * 又慢又费电。屏保每次进入编辑态都要显示封面，缓存成小 jpg 后，
 * 后续直接读文件，几乎零成本。
 *
 * 【缓存文件命名】
 * 目录：{应用文件目录}/video_covers
 * 文件：{uri 哈希}_{宽}x{高}.jpg
 * 把尺寸编进文件名，是因为同一视频在不同卡片大小下需要不同分辨率的封面，
 * 各存一份互不覆盖。
 * =============================================================================
 */

import { media } from '@kit.MediaKit';
import { image } from '@kit.ImageKit';
import { fileIo } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { ScreenSaverLogger } from './Logger';

/**
 * URI → 文件路径 归一化。
 *
 * 卡片上存的是「URI」（Video 组件要求 URI 形式，沙箱文件也要带 file:// 前缀），
 * 而 fileIo 打开文件用的是路径；对 file:///data/... 这种沙箱 URI 需要把前缀去掉。
 * 媒体库 URI（file://media/...）保持原样——它本身就是 fileIo 认识的形式。
 */
function screenSaverToFilePath(uri: string): string {
  if (uri.startsWith('file:///')) {
    return uri.substring(7);
  }
  return uri;
}

class ScreenSaverVideoThumbService {
  /** 缓存目录是否已确保创建（只创建一次，避免每次都试 mkdir）。 */
  private coverDirReady: boolean = false;

  /**
   * 入口：拿到某个视频在目标尺寸下的封面图文件路径。
   * 命中缓存直接返回；未命中则现场生成一帧并写入缓存。
   * uri 为空（用户还没选视频）时返回空字符串。
   */
  async firstFrameFile(context: common.UIAbilityContext, uri: string, targetWidth: number,
    targetHeight: number): Promise<string> {
    if (uri.length === 0) {
      return '';
    }
    // filesDir 是应用私有的文件目录，应用自己可随时读写，无需额外权限。
    const dir = `${context.filesDir}/video_covers`;
    if (!this.coverDirReady) {
      try {
        fileIo.mkdirSync(dir);
      } catch (err) {
        // 目录已存在时 mkdirSync 会抛错——这属于正常情况，记一条日志即可。
        ScreenSaverLogger.info('video cover dir already ready');
      }
      this.coverDirReady = true;
    }
    const path = `${dir}/${this.hashKey(uri)}_${targetWidth}x${targetHeight}.jpg`;
    try {
      // 缓存命中：文件已存在，直接复用，跳过昂贵的解码。
      if (fileIo.accessSync(path)) {
        return path;
      }
    } catch (err) {
      ScreenSaverLogger.info('video cover cache miss');
    }
    const generated = await this.generateCover(uri, path, targetWidth, targetHeight);
    return generated;
  }

  /**
   * 现场生成封面：
   *   1. 只读打开视频文件；
   *   2. 创建 AVImageGenerator（视频取帧器），把文件 fd 喂给它；
   *   3. fetchFrameByTime(0, ...) 取 0 秒位置的下一个同步帧（通常是首帧），
   *      得到一张 PixelMap；
   *   4. 用 ImagePacker 把 PixelMap 压成 85 质量的 jpg 写入缓存文件；
   *   5. finally 里按「PixelMap → generator → file」的顺序逐个释放资源。
   * 任一步失败返回空字符串，调用方显示占位图，绝不让屏保崩溃。
   */
  private async generateCover(uri: string, outPath: string, targetWidth: number,
    targetHeight: number): Promise<string> {
    let file: fileIo.File | undefined = undefined;
    let generator: media.AVImageGenerator | undefined = undefined;
    let pixelMap: image.PixelMap | undefined = undefined;
    try {
      file = fileIo.openSync(screenSaverToFilePath(uri), fileIo.OpenMode.READ_ONLY);
      generator = await media.createAVImageGenerator();
      // AVFileDescriptor：用文件描述符告诉生成器去哪读视频。
      const fdSrc: media.AVFileDescriptor = { fd: file.fd };
      generator.fdSrc = fdSrc;
      // 取帧尺寸夹在 [64, 1280]：太小会糊，太大没必要（封面而已）。
      const safeWidth = Math.max(64, Math.min(1280, Math.round(targetWidth)));
      const safeHeight = Math.max(64, Math.min(1280, Math.round(targetHeight)));
      const param: media.PixelMapParams = { width: safeWidth, height: safeHeight };
      // AV_IMAGE_QUERY_NEXT_SYNC：从 0 秒开始找「下一个同步帧」，
      // 保证取到的帧可以独立解码显示（非同步帧缺参考帧无法显示）。
      pixelMap = await generator.fetchFrameByTime(0, media.AVImageQueryOptions.AV_IMAGE_QUERY_NEXT_SYNC, param);
      const packer = image.createImagePacker();
      try {
        const option: image.PackingOption = { format: 'image/jpeg', quality: 85 };
        const buffer = await packer.packing(pixelMap, option);
        // TRUNC：文件已存在时先清空再写，避免残留旧数据。
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
      // 释放顺序：位图 → 取帧器 → 文件句柄（依赖前者时先释放被依赖者之外的对象）。
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

  /** 探测视频文件当前是否可读（视频被删或权限收回后用于降级提示）。 */
  probeReadable(uri: string): boolean {
    if (uri.length === 0) {
      return false;
    }
    let file: fileIo.File | undefined = undefined;
    try {
      file = fileIo.openSync(screenSaverToFilePath(uri), fileIo.OpenMode.READ_ONLY);
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

  /**
   * 简易字符串哈希（用于缓存文件名）。
   * 经典算法：hash = hash * 31 + 字符码；& 0x7fffffff 保证结果为正数，
   * 最后转 36 进制缩短文件名。这里不需要密码学强度，够短不碰撞即可。
   */
  private hashKey(text: string): string {
    let hash = 0;
    for (let index = 0; index < text.length; index++) {
      hash = (hash * 31 + text.charCodeAt(index)) & 0x7fffffff;
    }
    return hash.toString(36);
  }
}

// 导出全局唯一实例（单例），coverDirReady 标记也因此全局共享。
export const screenSaverVideoThumb: ScreenSaverVideoThumbService = new ScreenSaverVideoThumbService();
