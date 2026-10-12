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
        const favoriteEntry: ScreenSaverAlbumEntry = { key: 'favorite', name: '收藏' };
        entries.push(favoriteEntry);
      }
      const userResult = await helper.getAlbums(photoAccessHelper.AlbumType.USER,
        photoAccessHelper.AlbumSubtype.USER_GENERIC);
      const userAlbums = await userResult.getAllObjects();
      for (const album of userAlbums) {
        if (album.albumName.length === 0) {
          continue;
        }
        const entry: ScreenSaverAlbumEntry = { key: `user:${album.albumName}`, name: album.albumName };
        entries.push(entry);
      }
    } catch (err) {
      const error = err as BusinessError;
      ScreenSaverLogger.error(`list albums failed: code=${error.code}, message=${error.message}`);
    }
    return entries;
  }

  async fetchAlbumImageUris(context: common.Context, albumKey: string): Promise<string[]> {
    try {
      const helper = photoAccessHelper.getPhotoAccessHelper(context);
      const uris: string[] = [];
      if (albumKey.startsWith('user:')) {
        const album = await this.findUserAlbum(context, albumKey.substring(5));
        if (album !== undefined) {
          await this.collectAlbumAssets(album, uris);
        }
      } else if (albumKey === 'favorite') {
        const favoriteResult = await helper.getAlbums(photoAccessHelper.AlbumType.SYSTEM,
          photoAccessHelper.AlbumSubtype.FAVORITE);
        const favoriteAlbums = await favoriteResult.getAllObjects();
        if (favoriteAlbums.length > 0) {
          await this.collectAlbumAssets(favoriteAlbums[0], uris);
        }
      } else {
        await this.collectAllAssets(helper, uris);
      }
      ScreenSaverLogger.info(`album ${albumKey} fetched ${uris.length} images`);
      return uris;
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
      fetchColumns: [photoAccessHelper.PhotoKeys.URI, photoAccessHelper.PhotoKeys.PHOTO_TYPE],
      predicates: predicates
    };
    return options;
  }

  private async collectAlbumAssets(album: photoAccessHelper.Album, uris: string[]): Promise<void> {
    const result = await album.getAssets(this.buildFetchOptions());
    const assets = await result.getAllObjects();
    this.appendImageUris(assets, uris);
  }

  private async collectAllAssets(helper: photoAccessHelper.PhotoAccessHelper, uris: string[]): Promise<void> {
    const result = await helper.getAssets(this.buildFetchOptions());
    const assets = await result.getAllObjects();
    this.appendImageUris(assets, uris);
  }

  private appendImageUris(assets: photoAccessHelper.PhotoAsset[], uris: string[]): void {
    for (const asset of assets) {
      if (uris.length >= SCREEN_SAVER_ALBUM_FETCH_LIMIT) {
        return;
      }
      if (asset.photoType !== photoAccessHelper.PhotoType.IMAGE) {
        continue;
      }
      const uri = asset.uri;
      if (uri.length > 0) {
        uris.push(uri);
      }
    }
  }
}

export const screenSaverMediaAccess: ScreenSaverMediaAccessService = new ScreenSaverMediaAccessService();
