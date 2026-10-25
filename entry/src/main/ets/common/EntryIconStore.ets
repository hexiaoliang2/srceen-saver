/**
 * =============================================================================
 * 应用入口自定义图标存储（EntryIconStore.ets）
 * =============================================================================
 *
 * 选择 → 校验格式/大小 → 按最大档位图标尺寸解码 → 方形居中裁剪 → 打包 PNG →
 * 存应用沙箱 → 返回 `file://` 路径（持久化到卡片的 entry.iconUri）。
 *
 * 权限：使用系统 PhotoViewPicker（用户在系统弹窗里亲手选图），**不新增权限**。
 * 限制：仅 JPG / PNG / WebP，单文件 ≤ 2MB（超限在解码前拒绝）。
 * 内存：解码时同时给出 desiredRegion（原图中心正方形）与 desiredSize（≤384px），
 * 不会把整张原图解码进内存。
 * 兜底：文件丢失 / 解码失败 / uri 失效时卡片回退名称首字图标。
 * =============================================================================
 */

import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { image } from '@kit.ImageKit';
import { fileIo } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { ScreenSaverLogger } from './Logger';
import {
  SCREEN_SAVER_ENTRY_ICON_MAX_BYTES,
  SCREEN_SAVER_ENTRY_ICON_MAX_PX
} from '../model/ConfigModels';

const ENTRY_ICON_DIR_NAME: string = 'entry_icons';

/** 图标导入结果：失败时 reason 直接展示给用户。 */
export interface ScreenSaverEntryIconImportResult {
  ok: boolean;
  uri: string;
  reason: string;
}

function screenSaverEntryIconPath(uri: string): string {
  if (uri.startsWith('file://')) {
    return uri.substring('file://'.length);
  }
  return uri;
}

/** 选择一个图片（系统选择器，免权限）；取消返回空串。 */
export async function screenSaverPickEntryImage(): Promise<string> {
  try {
    const options = new photoAccessHelper.PhotoSelectOptions();
    options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
    options.maxSelectNumber = 1;
    const picker = new photoAccessHelper.PhotoViewPicker();
    const result = await picker.select(options);
    if (result.photoUris.length > 0) {
      return result.photoUris[0];
    }
    return '';
  } catch (err) {
    const error = err as BusinessError;
    ScreenSaverLogger.warn(`entry icon pick failed: code=${error.code} message=${error.message}`);
    return '';
  }
}

/** 自定义图标文件当前是否可读（文件被删除/uri 失效 → false）。 */
export function screenSaverEntryIconUsable(uri: string): boolean {
  if (uri.length === 0) {
    return false;
  }
  const path = screenSaverEntryIconPath(uri);
  try {
    return fileIo.accessSync(path);
  } catch (err) {
    return false;
  }
}

/** 删除旧图标文件（忽略失败：文件可能已不存在）。 */
export function screenSaverRemoveEntryIcon(uri: string): void {
  if (uri.length === 0) {
    return;
  }
  const path = screenSaverEntryIconPath(uri);
  try {
    if (fileIo.accessSync(path)) {
      fileIo.unlinkSync(path);
    }
  } catch (err) {
    ScreenSaverLogger.warn('entry icon remove skipped');
  }
}

/** 稳定文件名片段：只保留字母/数字/下划线/短横线，其余转下划线。 */
function screenSaverEntryIconSafeKey(key: string): string {
  const trimmed = key.trim();
  if (trimmed.length === 0) {
    return 'entry';
  }
  let result = '';
  for (let index = 0; index < trimmed.length && result.length < 48; index++) {
    const ch = trimmed.charAt(index);
    const code = trimmed.charCodeAt(index);
    const isDigit = code >= 48 && code <= 57;
    const isUpper = code >= 65 && code <= 90;
    const isLower = code >= 97 && code <= 122;
    const isDash = ch === '-' || ch === '_';
    result += isDigit || isUpper || isLower || isDash ? ch : '_';
  }
  return result.length > 0 ? result : 'entry';
}

/** 允许的图片 MIME（JPG / PNG / WebP）。 */
function screenSaverEntryIconMimeAllowed(mime: string): boolean {
  const value = mime.toLowerCase();
  if (value.length === 0) {
    // 少数机型拿不到 mime：交给后续解码校验，不在这里误杀。
    return true;
  }
  return value === 'image/jpeg' || value === 'image/jpg' || value === 'image/png' ||
    value === 'image/webp';
}

function screenSaverEntryIconFailure(reason: string): ScreenSaverEntryIconImportResult {
  const result: ScreenSaverEntryIconImportResult = { ok: false, uri: '', reason: reason };
  return result;
}

/**
 * 选图并落盘，返回沙箱 file:// 路径。
 *
 * 处理链：
 *   1. PhotoViewPicker 选择（免权限）；
 *   2. 校验大小（≤2MB）与格式（JPG / PNG / WebP）；
 *   3. 读原图宽高，取中心正方形区域（desiredRegion）；
 *   4. desiredSize = 384×384（最大档图标 122vp × 3 倍屏 ≈ 366px，留余量）；
 *   5. 打包 PNG（保留透明通道）；
 *   6. 写入 `${filesDir}/entry_icons/entry_icon_<cardId>_<timestamp>.png`。
 */
export async function screenSaverImportEntryIcon(contextFilesDir: string,
  stableKey: string): Promise<ScreenSaverEntryIconImportResult> {
  const picked = await screenSaverPickEntryImage();
  if (picked.length === 0) {
    return screenSaverEntryIconFailure('未选择图片，已保留原图标');
  }
  let source: image.ImageSource | undefined = undefined;
  let pixelMap: image.PixelMap | undefined = undefined;
  let packer: image.ImagePacker | undefined = undefined;
  let file: fileIo.File | undefined = undefined;
  let pickedFile: fileIo.File | undefined = undefined;
  try {
    pickedFile = fileIo.openSync(picked, fileIo.OpenMode.READ_ONLY);
    const stat = fileIo.statSync(pickedFile.fd);
    if (stat.size > SCREEN_SAVER_ENTRY_ICON_MAX_BYTES) {
      ScreenSaverLogger.warn(`entry icon too large: ${stat.size} bytes`);
      return screenSaverEntryIconFailure('图片超过 2MB，请换一张');
    }
    source = image.createImageSource(pickedFile.fd);
    const info = await source.getImageInfo();
    if (!screenSaverEntryIconMimeAllowed(info.mimeType)) {
      ScreenSaverLogger.warn(`entry icon unsupported mime: ${info.mimeType}`);
      return screenSaverEntryIconFailure('仅支持 JPG / PNG / WebP 图片');
    }
    const originWidth = info.size.width;
    const originHeight = info.size.height;
    if (originWidth <= 0 || originHeight <= 0) {
      return screenSaverEntryIconFailure('图片尺寸无效，请换一张');
    }
    const squareSide = Math.min(originWidth, originHeight);
    const cropX = Math.floor((originWidth - squareSide) / 2);
    const cropY = Math.floor((originHeight - squareSide) / 2);
    const region: image.Region = {
      x: cropX,
      y: cropY,
      size: { width: squareSide, height: squareSide }
    };
    const decodeSize: image.Size = {
      width: SCREEN_SAVER_ENTRY_ICON_MAX_PX,
      height: SCREEN_SAVER_ENTRY_ICON_MAX_PX
    };
    const decodeOptions: image.DecodingOptions = {
      desiredSize: decodeSize,
      desiredRegion: region
    };
    pixelMap = await source.createPixelMap(decodeOptions);
    packer = image.createImagePacker();
    const packOptions: image.PackingOption = { format: 'image/png', quality: 100 };
    const buffer = await packer.packing(pixelMap, packOptions);

    const dir = `${contextFilesDir}/${ENTRY_ICON_DIR_NAME}`;
    try {
      fileIo.mkdirSync(dir);
    } catch (mkdirError) {
      // 目录已存在是常态。
    }
    const safeKey = screenSaverEntryIconSafeKey(stableKey);
    // 文件名带时间戳：同名覆盖会让 Image 组件的解码缓存继续显示旧图。
    // 卡片 id 前缀保证同一张卡的图标可读且便于排查；替换时旧文件会被删除。
    const targetPath = `${dir}/entry_icon_${safeKey}_${Date.now()}.png`;
    file = fileIo.openSync(targetPath, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE |
      fileIo.OpenMode.TRUNC);
    fileIo.writeSync(file.fd, buffer);
    fileIo.closeSync(file);
    file = undefined;
    ScreenSaverLogger.info(`entry icon imported: ${targetPath}`);
    const ok: ScreenSaverEntryIconImportResult = { ok: true, uri: `file://${targetPath}`, reason: '' };
    return ok;
  } catch (err) {
    const error = err as BusinessError;
    ScreenSaverLogger.warn(`entry icon import failed: code=${error.code} message=${error.message}`);
    return screenSaverEntryIconFailure('图片处理失败，已保留原图标');
  } finally {
    if (packer !== undefined) {
      try {
        packer.release();
      } catch (releaseError) {
        ScreenSaverLogger.warn('entry icon packer release skipped');
      }
    }
    if (pixelMap !== undefined) {
      try {
        pixelMap.release();
      } catch (releaseError) {
        ScreenSaverLogger.warn('entry icon pixel release skipped');
      }
    }
    if (source !== undefined) {
      try {
        source.release();
      } catch (releaseError) {
        ScreenSaverLogger.warn('entry icon source release skipped');
      }
    }
    if (file !== undefined) {
      try {
        fileIo.closeSync(file);
      } catch (closeError) {
        ScreenSaverLogger.warn('entry icon file close skipped');
      }
    }
    if (pickedFile !== undefined) {
      try {
        fileIo.closeSync(pickedFile);
      } catch (closeError) {
        ScreenSaverLogger.warn('entry icon picked file close skipped');
      }
    }
  }
}
