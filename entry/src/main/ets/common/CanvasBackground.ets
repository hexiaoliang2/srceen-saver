/**
 * =============================================================================
 * 屏保整体背景（CanvasBackground.ets）—— 变更项 7
 * =============================================================================
 *
 * 【这个文件是干什么的】
 * 屏保画布的「最底层」背景：默认纯黑，另有 24 个预设色；也支持用户自选
 * 本地图片作为背景，并可对图片做**一次性离屏模糊**后缓存复用。
 *
 * 【桌面透视模糊为什么没有实现（官方结论）】
 * 已核实：`@ohos.wallpaper` 模块自 API 9 起调整为**系统 API**
 * （`getWallpaper/getFile` 需要 `ohos.permission.GET_WALLPAPER`，
 * 该权限为系统级权限，三方应用无法申请；文档原文见
 * `API参考/基础功能/Basic_Services_Kit_基础服务/ArkTS_API/其他/ohos_wallpaper_壁纸_/js-apis-wallpaper`）。
 * 因此三方应用**不能读取桌面壁纸、也不能对桌面做模糊**，也不允许用非官方手段
 * （截图/无障碍抓屏等）实现。按需求改为替代方案：
 * 「用户自选本地图片 + 一次性离屏模糊并缓存」。
 * 差异说明：替代方案模糊的是用户自己选的图片，不是桌面实时壁纸；
 * 桌面换壁纸后需要用户重新选图，也不会跟随桌面变化。
 *
 * 【性能与省电（硬约束）】
 *   - 模糊只在**图片或模糊开关变化时**离屏计算一次（effectKit 静态模糊），
 *     结果 PixelMap 常驻缓存；卡片滚动/切换背景/进出屏保都不重复计算；
 *   - 渲染层只放一张 Image（或用纯色填充），**不使用** `.blur()/.backdropBlur()`
 *     这类实时模糊属性，不引入常驻重绘；
 *   - 解码时先把长边压到 1080px 再模糊（省内存，模糊结果本来就是低频信息）。
 *
 * 【功耗提示（与「极低功耗」目标的冲突）】
 * 浅色/亮色背景在 OLED 屏上等效于点亮大量像素，功耗明显高于纯黑。
 * 本模块因此在 UI 文案里标注了这一点（设置页），默认值保持纯黑。
 * =============================================================================
 */

import { image } from '@kit.ImageKit';
import { effectKit } from '@kit.ArkGraphics2D';
import { fileIo } from '@kit.CoreFileKit';
import { ScreenSaverLogger } from './Logger';
import { screenSaverFittedSize, ScreenSaverFitSize } from './ContentFit';

/** 离屏模糊半径（px，作用在长边 ≤1080px 的解码结果上；实现侧方案，待确认）。 */
export const SCREEN_SAVER_CANVAS_BLUR_RADIUS: number = 40;
/** 背景解码长边上限（px）：模糊后细节本就丢失，不需要原图分辨率。 */
const SCREEN_SAVER_CANVAS_MAX_EDGE: number = 1080;

/**
 * 背景服务：负责「图片 → 缩放解码 → 离屏模糊 → 缓存」这一条链路。
 * 单例使用（见文件末尾），因此缓存全局共享，背景切换不会重复计算。
 */
class ScreenSaverCanvasBackgroundService {
  /** 缓存键（uri|半径）：相同键直接复用，不重算。 */
  private cacheKey: string = '';
  /** 缓存的模糊结果（可能是原图解码结果，模糊失败时的降级）。 */
  private cached: image.PixelMap | undefined = undefined;
  /** 是否已有一次离屏计算在进行（防并发重复计算）。 */
  private inflight: boolean = false;
  /** 计算代数：背景被清空时 +1，让在途结果作废。 */
  private generation: number = 0;
  /** 实际执行的离屏计算次数（验证「一次计算 + 缓存复用」用）。 */
  private computeCount: number = 0;

  /** 已完成的离屏计算次数（验证脚本/日志用）。 */
  computedTimes(): number {
    return this.computeCount;
  }

  /**
   * 取背景图片的（模糊）位图。
   * 命中缓存直接返回；否则离屏计算一次并缓存。
   * 返回 undefined 表示不可用（调用方退回纯色/黑底）。
   */
  async ensure(uri: string, blurEnabled: boolean): Promise<image.PixelMap | undefined> {
    if (uri.length === 0) {
      return undefined;
    }
    const radius = blurEnabled ? SCREEN_SAVER_CANVAS_BLUR_RADIUS : 0;
    const key = `${uri}|${radius}`;
    if (key === this.cacheKey && this.cached !== undefined) {
      return this.cached;
    }
    if (this.inflight) {
      // 已有一次计算在跑：本次直接返回旧缓存，等下一次状态刷新再换图，
      // 避免「连续切换背景」时叠算多份位图。
      return this.cached;
    }
    this.inflight = true;
    const generation = this.generation;
    try {
      const decoded = await this.decodeScaled(uri);
      if (decoded === undefined) {
        return this.cached;
      }
      let result: image.PixelMap = decoded;
      if (radius > 0) {
        const blurred = await this.applyBlur(decoded, radius);
        if (blurred !== undefined) {
          result = blurred;
          this.releaseMap(decoded);
        }
      }
      if (generation !== this.generation) {
        // 计算期间背景已被清空/切换：丢弃结果，避免把旧图写进缓存。
        this.releaseMap(result);
        return this.cached;
      }
      this.releaseMap(this.cached);
      this.cached = result;
      this.cacheKey = key;
      this.computeCount++;
      ScreenSaverLogger.info(`canvas background ready: blur=${radius > 0} computed=${this.computeCount}`);
      return this.cached;
    } catch (err) {
      const error = err as Error;
      ScreenSaverLogger.warn(`canvas background failed: ${error.message}`);
      return this.cached;
    } finally {
      this.inflight = false;
    }
  }

  /** 清空缓存（用户移除背景图片时调用）。 */
  clear(): void {
    this.generation++;
    this.releaseMap(this.cached);
    this.cached = undefined;
    this.cacheKey = '';
  }

  /** 等比缩小解码（长边 ≤ SCREEN_SAVER_CANVAS_MAX_EDGE，绝不放大）。 */
  private async decodeScaled(uri: string): Promise<image.PixelMap | undefined> {
    let file: fileIo.File | undefined = undefined;
    let source: image.ImageSource | undefined = undefined;
    try {
      file = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
      source = image.createImageSource(file.fd);
      const info = await source.getImageInfo();
      const originWidth = info.size.width;
      const originHeight = info.size.height;
      if (originWidth <= 0 || originHeight <= 0) {
        return undefined;
      }
      const fitted: ScreenSaverFitSize = screenSaverFittedSize(originWidth, originHeight,
        SCREEN_SAVER_CANVAS_MAX_EDGE, SCREEN_SAVER_CANVAS_MAX_EDGE, SCREEN_SAVER_CANVAS_MAX_EDGE);
      const desired: image.Size = { width: fitted.width, height: fitted.height };
      const options: image.DecodingOptions = { desiredSize: desired };
      const pixelMap = await source.createPixelMap(options);
      return pixelMap;
    } catch (err) {
      const error = err as Error;
      ScreenSaverLogger.error(`canvas background decode failed: ${error.message}`);
      return undefined;
    } finally {
      if (source !== undefined) {
        try {
          source.release();
        } catch (releaseErr) {
          ScreenSaverLogger.warn('canvas background source release failed');
        }
      }
      if (file !== undefined) {
        try {
          fileIo.closeSync(file);
        } catch (closeErr) {
          ScreenSaverLogger.warn('canvas background file close failed');
        }
      }
    }
  }

  /**
   * 离屏静态模糊（effectKit，一次性计算，返回新的 PixelMap）。
   * 失败返回 undefined，调用方降级为「不模糊的原图」。
   */
  private async applyBlur(source: image.PixelMap, radius: number): Promise<image.PixelMap | undefined> {
    try {
      const filter = effectKit.createEffect(source);
      if (filter === null) {
        return undefined;
      }
      const blurred = await filter.blur(radius).getEffectPixelMap(false);
      return blurred;
    } catch (err) {
      const error = err as Error;
      ScreenSaverLogger.warn(`canvas background blur failed: ${error.message}`);
      return undefined;
    }
  }

  /** 释放位图（失败只记日志）。 */
  private releaseMap(map: image.PixelMap | undefined): void {
    if (map === undefined) {
      return;
    }
    try {
      map.release();
    } catch (err) {
      ScreenSaverLogger.warn('canvas background release failed');
    }
  }
}

// 全局唯一实例：缓存跨页面共享。
export const screenSaverCanvasBackground: ScreenSaverCanvasBackgroundService =
  new ScreenSaverCanvasBackgroundService();
