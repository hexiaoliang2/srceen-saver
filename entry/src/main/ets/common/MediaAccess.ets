/**
 * =============================================================================
 * 相册/视频媒体访问（MediaAccess.ets）
 * =============================================================================
 *
 * 【这个文件是干什么的】
 * 所有跟「系统相册」打交道的操作都收口在这里：
 *   - 弹系统选图/选视频窗口（PhotoViewPicker，免权限）
 *   - 申请/引导用户开启相册读取权限（READ_IMAGEVIDEO）
 *   - 枚举相册列表（收藏、用户自建相册）
 *   - 按相册拉取照片的 uri 和拍摄日期
 *
 * 【权限小知识】
 * 1. PhotoViewPicker（系统选择器）不需要任何权限——用户在系统弹窗里
 *    亲手选的文件，系统会临时授予访问权。所以「手动添加照片」零门槛。
 * 2. 「自动读取整个相册」则需要 READ_IMAGEVIDEO 用户授权，所以要先走
 *    requestPhotoPermission；被拒绝后用 openPermissionSetting 引导去设置里开。
 *
 * 【为什么每张照片都带 dateTaken（拍摄日期）】
 * 相册卡片底部要显示「拍摄日期，无则显示文件名」。媒体库的 DATE_ADDED
 * 是「加入媒体库的时间戳」（秒级），记录下来供 PhotoCardView 格式化显示。
 * =============================================================================
 */

import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';
import { dataSharePredicates } from '@kit.ArkData';
import { BusinessError } from '@kit.BasicServicesKit';
import { ScreenSaverLogger } from './Logger';

// 需要申请的敏感权限：读取媒体库图片/视频（module.json5 里已声明）。
const SCREEN_SAVER_READ_IMAGEVIDEO: Permissions = 'ohos.permission.READ_IMAGEVIDEO';
// 单次最多拉取的照片数：防止几千张的相册把内存和时间都吃光。
const SCREEN_SAVER_ALBUM_FETCH_LIMIT: number = 2000;

/** 相册条目：唯一标识（key）、显示名、包含的资产数量。 */
export interface ScreenSaverAlbumEntry {
  key: string;
  name: string;
  count: number;
}

/** 照片条目：uri（媒体库地址）+ 拍摄日期（DATE_ADDED 原始字符串，可能为空）。 */
export interface ScreenSaverPhotoEntry {
  uri: string;
  dateTaken: string;
}

/**
 * 相册权限状态的可观察标记（V2 观察模型）。
 * @ObservedV2 + @Trace 的组合让 UI 能自动感知这两个布尔值的变化：
 * 权限被拒后相关界面立即显示引导，授权成功后立即恢复。
 */
@ObservedV2
export class ScreenSaverPhotoAccessFlag {
  @Trace albumDenied: boolean = false;
  @Trace albumLoaded: boolean = false;
}

// 全局唯一的权限状态实例（单例），各页面共享同一份状态。
export const screenSaverPhotoAccessFlag: ScreenSaverPhotoAccessFlag = new ScreenSaverPhotoAccessFlag();

class ScreenSaverMediaAccessService {
  /**
   * 弹出系统选图窗口，让用户手动挑照片（可多选）。
   * PhotoViewPicker 不需要任何权限（用户亲手选 = 系统自动临时授权）。
   * 过滤掉空 uri（防御性写法），失败返回空数组。
   */
  async pickImages(maxCount: number): Promise<string[]> {
    try {
      const options = new photoAccessHelper.PhotoSelectOptions();
      options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      options.maxSelectNumber = maxCount;
      const picker = new photoAccessHelper.PhotoViewPicker();
      const result = await picker.select(options);
      const uris: string[] = [];
      for (const uri of result.photoUris) {
        if (uri.length > 0) {
          uris.push(uri);
        }
      }
      return uris;
    } catch (err) {
      const error = err as BusinessError;
      ScreenSaverLogger.error(`pick images failed: code=${error.code}, message=${error.message}`);
      return [];
    }
  }

  /** 弹系统选视频窗口（单选），返回视频 uri；取消/失败返回空串。 */
  async pickVideo(): Promise<string> {
    try {
      const options = new photoAccessHelper.PhotoSelectOptions();
      options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.VIDEO_TYPE;
      options.maxSelectNumber = 1;
      const picker = new photoAccessHelper.PhotoViewPicker();
      const result = await picker.select(options);
      if (result.photoUris.length > 0) {
        return result.photoUris[0];
      }
      return '';
    } catch (err) {
      const error = err as BusinessError;
      ScreenSaverLogger.error(`pick video failed: code=${error.code}, message=${error.message}`);
      return '';
    }
  }

  /**
   * 申请相册读取权限（弹系统授权弹窗）。
   * authResults 里 0 表示用户同意；弹窗失败/被拒都返回 false，
   * 调用方据此显示「去授权」的引导界面。
   */
  async requestPhotoPermission(context: common.Context): Promise<boolean> {
    try {
      const atManager = abilityAccessCtrl.createAtManager();
      const result = await atManager.requestPermissionsFromUser(context, [SCREEN_SAVER_READ_IMAGEVIDEO]);
      const granted = result.authResults.length > 0 && result.authResults[0] === 0;
      ScreenSaverLogger.info(`photo permission request result: ${granted}`);
      return granted;
    } catch (err) {
      const error = err as BusinessError;
      ScreenSaverLogger.error(`request photo permission failed: code=${error.code}, message=${error.message}`);
      return false;
    }
  }

  /**
   * 在设置页里再次申请权限。
   * 使用场景：用户之前拒绝了弹窗（系统不再弹），需要引导他到
   * 「设置 → 应用 → 权限」里手动开启。这里直接拉起系统授权界面。
   */
  async openPermissionSetting(context: common.Context): Promise<void> {
    try {
      const atManager = abilityAccessCtrl.createAtManager();
      await atManager.requestPermissionOnSetting(context, [SCREEN_SAVER_READ_IMAGEVIDEO]);
      ScreenSaverLogger.info('permission setting dialog shown');
    } catch (err) {
      const error = err as BusinessError;
      ScreenSaverLogger.error(`open permission setting failed: code=${error.code}, message=${error.message}`);
    }
  }

  /**
   * 枚举相册列表：系统「收藏」相册 + 用户自建相册。
   * 收藏相册特殊（系统级、可能为空），单独处理放最前面；
   * 用户相册用 key = 'user:相册名' 标识，供后续 fetchAlbumImageEntries 反查。
   */
  async listAlbums(context: common.Context): Promise<ScreenSaverAlbumEntry[]> {
    const entries: ScreenSaverAlbumEntry[] = [];
    try {
      const helper = photoAccessHelper.getPhotoAccessHelper(context);
      // 系统收藏相册（FAVORITE）：拿到后再统计里面的资产数。
      const favoriteResult = await helper.getAlbums(photoAccessHelper.AlbumType.SYSTEM,
        photoAccessHelper.AlbumSubtype.FAVORITE);
      const favoriteAlbums = await favoriteResult.getAllObjects();
      if (favoriteAlbums.length > 0) {
        const favoriteCount = await this.countAlbumAssets(favoriteAlbums[0]);
        const favoriteEntry: ScreenSaverAlbumEntry = { key: 'favorite', name: '收藏', count: favoriteCount };
        entries.push(favoriteEntry);
      }
      // 用户自建相册
      const userResult = await helper.getAlbums(photoAccessHelper.AlbumType.USER,
        photoAccessHelper.AlbumSubtype.USER_GENERIC);
      const userAlbums = await userResult.getAllObjects();
      for (const album of userAlbums) {
        if (album.albumName.length === 0) {
          continue; // 跳过没有名字的异常相册
        }
        const count = await this.countAlbumAssets(album);
        const entry: ScreenSaverAlbumEntry = { key: `user:${album.albumName}`, name: album.albumName, count: count };
        entries.push(entry);
      }
    } catch (err) {
      const error = err as BusinessError;
      // 权限未授予时这里会失败：返回空列表，界面显示引导授权。
      ScreenSaverLogger.error(`list albums failed: code=${error.code}, message=${error.message}`);
    }
    return entries;
  }

  /** 统计整个媒体库里图片+视频的总数（设置页展示用）。 */
  async countAllAssets(context: common.Context): Promise<number> {
    try {
      const helper = photoAccessHelper.getPhotoAccessHelper(context);
      const result = await helper.getAssets(this.buildFetchOptions());
      const count = result.getCount(); // getCount 是同步方法，直接返回数量
      result.close();                  // FetchResult 用完必须 close，否则句柄泄漏
      return count;
    } catch (err) {
      const error = err as BusinessError;
      ScreenSaverLogger.warn(`count all assets failed: code=${error.code}, message=${error.message}`);
      return -1; // -1 表示「统计失败」，界面据此不显示数字
    }
  }

  /** 统计某个相册里的资产数量。失败返回 -1（不显示数字而不是显示 0）。 */
  private async countAlbumAssets(album: photoAccessHelper.Album): Promise<number> {
    try {
      const result = await album.getAssets(this.buildFetchOptions());
      const count = result.getCount();
      result.close();
      return count;
    } catch (err) {
      const error = err as BusinessError;
      ScreenSaverLogger.warn(`count album assets failed: code=${error.code}, message=${error.message}`);
      return -1;
    }
  }

  /**
   * 按相册 key 拉取照片条目（uri + 拍摄日期）。
   * key 有三种取值：
   *   'user:相册名' → 用户自建相册
   *   'favorite'    → 系统收藏相册
   *   其它           → 整个媒体库
   * 只保留 IMAGE 类型（视频卡片有专门的选择入口）。
   */
  async fetchAlbumImageEntries(context: common.Context, albumKey: string): Promise<ScreenSaverPhotoEntry[]> {
    try {
      const helper = photoAccessHelper.getPhotoAccessHelper(context);
      const entries: ScreenSaverPhotoEntry[] = [];
      if (albumKey.startsWith('user:')) {
        // substring(5) 去掉 'user:' 前缀，取出相册名
        const album = await this.findUserAlbum(context, albumKey.substring(5));
        if (album !== undefined) {
          await this.collectAlbumAssets(album, entries);
        }
      } else if (albumKey === 'favorite') {
        const favoriteResult = await helper.getAlbums(photoAccessHelper.AlbumType.SYSTEM,
          photoAccessHelper.AlbumSubtype.FAVORITE);
        const favoriteAlbums = await favoriteResult.getAllObjects();
        if (favoriteAlbums.length > 0) {
          await this.collectAlbumAssets(favoriteAlbums[0], entries);
        }
      } else {
        await this.collectAllAssets(helper, entries);
      }
      ScreenSaverLogger.info(`album ${albumKey} fetched ${entries.length} images`);
      return entries;
    } catch (err) {
      const error = err as BusinessError;
      ScreenSaverLogger.error(`fetch album images failed: code=${error.code}, message=${error.message}`);
      return [];
    }
  }

  /** 按名字在用户相册里找到对应的 Album 对象。找不到返回 undefined。 */
  private async findUserAlbum(context: common.Context, albumName: string): Promise<photoAccessHelper.Album | undefined> {
    const helper = photoAccessHelper.getPhotoAccessHelper(context);
    const result = await helper.getAlbums(photoAccessHelper.AlbumType.USER,
      photoAccessHelper.AlbumSubtype.USER_GENERIC);
    const albums = await result.getAllObjects();
    for (const album of albums) {
      if (album.albumName === albumName) {
        return album;
      }
    }
    return undefined;
  }

  /**
   * 构造媒体查询条件。
   * fetchColumns 指定要查询哪些字段：URI（地址）、PHOTO_TYPE（图片/视频，
   * 用于过滤）、DATE_ADDED（拍摄/入库日期，供相册卡片显示）。
   */
  private buildFetchOptions(): photoAccessHelper.FetchOptions {
    const predicates = new dataSharePredicates.DataSharePredicates();
    const options: photoAccessHelper.FetchOptions = {
      fetchColumns: [
        photoAccessHelper.PhotoKeys.URI,
        photoAccessHelper.PhotoKeys.PHOTO_TYPE,
        photoAccessHelper.PhotoKeys.DATE_ADDED
      ],
      predicates: predicates // 空谓词 = 不过滤，取全部
    };
    return options;
  }

  /** 拉取某相册的全部资产并追加到 entries。 */
  private async collectAlbumAssets(album: photoAccessHelper.Album, entries: ScreenSaverPhotoEntry[]): Promise<void> {
    const result = await album.getAssets(this.buildFetchOptions());
    const assets = await result.getAllObjects();
    this.appendImageEntries(assets, entries);
  }

  /** 拉取整个媒体库的资产并追加到 entries。 */
  private async collectAllAssets(helper: photoAccessHelper.PhotoAccessHelper,
    entries: ScreenSaverPhotoEntry[]): Promise<void> {
    const result = await helper.getAssets(this.buildFetchOptions());
    const assets = await result.getAllObjects();
    this.appendImageEntries(assets, entries);
  }

  /**
   * 把 PhotoAsset 数组转换成精简的照片条目。
   * - 上限 2000 张，防止巨型相册拖垮内存；
   * - 只收 IMAGE 类型；
   * - DATE_ADDED 用 asset.get() 读取（值是秒级时间戳字符串），
   *   读取失败时置空串——日期只是辅助信息，缺了就回退显示文件名。
   */
  private appendImageEntries(assets: photoAccessHelper.PhotoAsset[], entries: ScreenSaverPhotoEntry[]): void {
    for (const asset of assets) {
      if (entries.length >= SCREEN_SAVER_ALBUM_FETCH_LIMIT) {
        return;
      }
      if (asset.photoType !== photoAccessHelper.PhotoType.IMAGE) {
        continue;
      }
      const uri = asset.uri;
      if (uri.length === 0) {
        continue;
      }
      let dateTaken = '';
      try {
        const rawDate = asset.get(photoAccessHelper.PhotoKeys.DATE_ADDED);
        // get() 的返回类型较宽（可能是 string/number），统一转成 string 保存
        dateTaken = typeof rawDate === 'string' ? rawDate : `${rawDate}`;
      } catch (dateError) {
        dateTaken = '';
      }
      const entry: ScreenSaverPhotoEntry = { uri: uri, dateTaken: dateTaken };
      entries.push(entry);
    }
  }
}

// 导出全局唯一实例（单例）。
export const screenSaverMediaAccess: ScreenSaverMediaAccessService = new ScreenSaverMediaAccessService();
