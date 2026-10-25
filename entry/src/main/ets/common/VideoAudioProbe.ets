/**
 * =============================================================================
 * 视频音轨探测（VideoAudioProbe.ets）
 * =============================================================================
 *
 * 只做一件事：判断本地视频文件里是否存在音频轨。
 *   · present：存在音频轨，声音按钮可用；
 *   · absent：无音频轨，声音按钮置灰并提示；
 *   · unknown：元数据不支持/读取失败，不阻断播放，由调用方决定降级。
 *
 * 实现使用 AVMetadataExtractor + AVFileDescriptor：
 *   · fileIo 可直接打开 file://media/... 与沙箱文件路径；
 *   · metadata.tracks 里 MD_KEY_TRACK_TYPE === MEDIA_TYPE_AUD 即存在音频轨；
 *   · 结果按 uri 缓存，避免每次重绘都打开文件。
 *
 * 不读写 Preferences，不引入网络，不新增权限。
 * =============================================================================
 */

import { media } from '@kit.MediaKit';
import { fileIo } from '@kit.CoreFileKit';
import { ScreenSaverLogger } from './Logger';

export type ScreenSaverVideoAudioTrackState = 'present' | 'absent' | 'unsupported' | 'unknown';

/** uri → 文件路径归一化；媒体库 URI 保持原样，沙箱 URI 去掉 file:/// 前缀。 */
function screenSaverAudioFilePath(uri: string): string {
  if (uri.startsWith('file:///')) {
    return uri.substring(7);
  }
  return uri;
}

class ScreenSaverVideoAudioProbeService {
  private cache: Record<string, ScreenSaverVideoAudioTrackState> = {};

  /** Video 组件可稳定输出的本地音频编码白名单。 */
  private codecSupported(codecs: string): boolean {
    if (codecs.length === 0) {
      return false;
    }
    const lower = codecs.toLowerCase();
    if (lower.includes('ac3') || lower.includes('eac3') || lower.includes('dts') ||
      lower.includes('truehd')) {
      return false;
    }
    return lower.includes('mp4a') || lower.includes('aac') || lower.includes('mpeg') ||
      lower.includes('mp3') || lower.includes('opus');
  }

  /** 读取视频音轨状态；同一 uri 只探测一次。 */
  async probe(uri: string): Promise<ScreenSaverVideoAudioTrackState> {
    if (uri.length === 0) {
      return 'unknown';
    }
    const cached = this.cache[uri];
    if (cached !== undefined) {
      return cached;
    }
    let file: fileIo.File | undefined = undefined;
    let extractor: media.AVMetadataExtractor | undefined = undefined;
    try {
      file = fileIo.openSync(screenSaverAudioFilePath(uri), fileIo.OpenMode.READ_ONLY);
      extractor = await media.createAVMetadataExtractor();
      const fdSrc: media.AVFileDescriptor = { fd: file.fd };
      extractor.fdSrc = fdSrc;
      const metadata = await extractor.fetchMetadata();
      const tracks = metadata.tracks;
      if (tracks === undefined || tracks.length === 0) {
        this.cache[uri] = 'unknown';
        ScreenSaverLogger.info('video audio probe: tracks unavailable');
        return 'unknown';
      }
      let hasAudio = false;
      let audioCodec = '';
      for (const track of tracks) {
        const trackType = track[media.MediaDescriptionKey.MD_KEY_TRACK_TYPE];
        if (trackType === media.MediaType.MEDIA_TYPE_AUD) {
          hasAudio = true;
          const codec = track[media.MediaDescriptionKey.MD_KEY_CODEC_MIME];
          if (codec !== undefined) {
            audioCodec += `${codec},`;
          }
        }
      }
      let state: ScreenSaverVideoAudioTrackState = hasAudio ? 'present' : 'absent';
      if (hasAudio && !this.codecSupported(audioCodec)) {
        // 有音轨但 codec 未暴露/为 AC3、DTS 等 Video 组件不支持的编码。
        state = 'unsupported';
      }
      ScreenSaverLogger.info(`video audio codecs: ${audioCodec.length > 0 ? audioCodec : 'none'}`);
      this.cache[uri] = state;
      ScreenSaverLogger.info(`video audio probe: tracks=${tracks.length} result=${state}`);
      return state;
    } catch (err) {
      const error = err as Error;
      this.cache[uri] = 'unknown';
      ScreenSaverLogger.warn(`video audio probe failed: ${error.message}`);
      return 'unknown';
    } finally {
      if (extractor !== undefined) {
        try {
          extractor.release();
        } catch (releaseErr) {
          ScreenSaverLogger.warn('video audio extractor release failed');
        }
      }
      if (file !== undefined) {
        try {
          fileIo.closeSync(file);
        } catch (closeErr) {
          ScreenSaverLogger.warn('video audio file close failed');
        }
      }
    }
  }
}

export const screenSaverVideoAudioProbe: ScreenSaverVideoAudioProbeService =
  new ScreenSaverVideoAudioProbeService();
