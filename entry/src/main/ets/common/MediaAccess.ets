import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';
import { dataSharePredicates } from '@kit.ArkData';
import { BusinessError } from '@kit.BasicServicesKit';
import { ScreenSaverLogger } from './Logger';

const SCREEN_SAVER_READ_IMAGEVIDEO: Permissions = 'ohos.permission.READ_IMAGEVIDEO';
const SCREEN_SAVER_ALBUM_FETCH_LIMIT: number = 2000;

export interface ScreenSaverAlbumEntry {
  key: string;
  name: string;
  count: number;
}

export interface ScreenSaverPhotoEntry {
  uri: string;
  dateTaken: string;
}

@ObservedV2
export class ScreenSaverPhotoAccessFlag {
  @Trace albumDenied: boolean = false;
  @Trace albumLoaded: boolean = false;
}

export const screenSaverPhotoAccessFlag: ScreenSaverPhotoAccessFlag = new ScreenSaverPhotoAccessFlag();

class ScreenSaverMediaAccessService {
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

  async listAlbums(context: common.Context): Promise<ScreenSaverAlbumEntry[]> {
    const entries: ScreenSaverAlbumEntry[] = [];
    try {
      const helper = photoAccessHelper.getPhotoAccessHelper(context);
      const favoriteResult = await helper.getAlbums(photoAccessHelper.AlbumType.SYSTEM,
        photoAccessHelper.AlbumSubtype.FAVORITE);
      const favoriteAlbums = await favoriteResult.getAllObjects();
      if (favoriteAlbums.length > 0) {
        const favoriteCount = await this.countAlbumAssets(favoriteAlbums[0]);
        const favoriteEntry: ScreenSaverAlbumEntry = { key: 'favorite', name: '收藏', count: favoriteCount };
        entries.push(favoriteEntry);
      }
      const userResult = await helper.getAlbums(photoAccessHelper.AlbumType.USER,
        photoAccessHelper.AlbumSubtype.USER_GENERIC);
      const userAlbums = await userResult.getAllObjects();
      for (const album of userAlbums) {
        if (album.albumName.length === 0) {
          continue;
        }
        const count = await this.countAlbumAssets(album);
        const entry: ScreenSaverAlbumEntry = { key: `user:${album.albumName}`, name: album.albumName, count: count };
        entries.push(entry);
      }
    } catch (err) {
      const error = err as BusinessError;
      ScreenSaverLogger.error(`list albums failed: code=${error.code}, message=${error.message}`);
    }
    return entries;
  }

  async countAllAssets(context: common.Context): Promise<number> {
    try {
      const helper = photoAccessHelper.getPhotoAccessHelper(context);
      const result = await helper.getAssets(this.buildFetchOptions());
      const count = result.getCount();
      result.close();
      return count;
    } catch (err) {
      const error = err as BusinessError;
      ScreenSaverLogger.warn(`count all assets failed: code=${error.code}, message=${error.message}`);
      return -1;
    }
  }

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

  async fetchAlbumImageEntries(context: common.Context, albumKey: string): Promise<ScreenSaverPhotoEntry[]> {
    try {
      const helper = photoAccessHelper.getPhotoAccessHelper(context);
      const entries: ScreenSaverPhotoEntry[] = [];
      if (albumKey.startsWith('user:')) {
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

  private buildFetchOptions(): photoAccessHelper.FetchOptions {
    const predicates = new dataSharePredicates.DataSharePredicates();
    const options: photoAccessHelper.FetchOptions = {
      fetchColumns: [
        photoAccessHelper.PhotoKeys.URI,
        photoAccessHelper.PhotoKeys.PHOTO_TYPE,
        photoAccessHelper.PhotoKeys.DATE_ADDED
      ],
      predicates: predicates
    };
    return options;
  }

  private async collectAlbumAssets(album: photoAccessHelper.Album, entries: ScreenSaverPhotoEntry[]): Promise<void> {
    const result = await album.getAssets(this.buildFetchOptions());
    const assets = await result.getAllObjects();
    this.appendImageEntries(assets, entries);
  }

  private async collectAllAssets(helper: photoAccessHelper.PhotoAccessHelper,
    entries: ScreenSaverPhotoEntry[]): Promise<void> {
    const result = await helper.getAssets(this.buildFetchOptions());
    const assets = await result.getAllObjects();
    this.appendImageEntries(assets, entries);
  }

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
        dateTaken = typeof rawDate === 'string' ? rawDate : `${rawDate}`;
      } catch (dateError) {
        dateTaken = '';
      }
      const entry: ScreenSaverPhotoEntry = { uri: uri, dateTaken: dateTaken };
      entries.push(entry);
    }
  }
}

export const screenSaverMediaAccess: ScreenSaverMediaAccessService = new ScreenSaverMediaAccessService();
