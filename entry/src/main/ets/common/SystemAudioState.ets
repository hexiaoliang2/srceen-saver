/**
 * =============================================================================
 * 系统媒体音量/静音读取（SystemAudioState.ets）
 * =============================================================================
 *
 * 只读系统状态，不修改系统音量，不申请权限：
 *   · getVolumeByStream(STREAM_USAGE_MOVIE)：当前媒体流音量档位；
 *   · isSystemMutedForStream(STREAM_USAGE_MOVIE)：系统是否静音该媒体流。
 *
 * 用于用户开启卡片声音时给出轻提示（系统静音/音量为 0），
 * 不作为“是否真正出声”的唯一依据；最终仍以播放器状态与真机听感为准。
 * =============================================================================
 */

import { audio } from '@kit.AudioKit';
import { ScreenSaverLogger } from './Logger';

export interface ScreenSaverSystemAudioState {
  known: boolean;
  volume: number;
  muted: boolean;
}

class ScreenSaverSystemAudioStateService {
  read(): ScreenSaverSystemAudioState {
    try {
      const manager = audio.getAudioManager();
      const volumeManager = manager.getVolumeManager();
      const volume = volumeManager.getVolumeByStream(audio.StreamUsage.STREAM_USAGE_MOVIE);
      const muted = volumeManager.isSystemMutedForStream(audio.StreamUsage.STREAM_USAGE_MOVIE);
      return { known: true, volume: volume, muted: muted };
    } catch (err) {
      const error = err as Error;
      ScreenSaverLogger.warn(`system audio state read failed: ${error.message}`);
      return { known: false, volume: -1, muted: false };
    }
  }

  /** 诊断：当前活跃渲染流与输出设备（只读，不上报）。 */
  describeActiveRenderers(): string {
    try {
      const manager = audio.getAudioManager();
      const renderers = manager.getStreamManager().getCurrentAudioRendererInfoArraySync();
      let text = '';
      for (const renderer of renderers) {
        let devices = '';
        for (const device of renderer.deviceDescriptors) {
          devices += `${device.deviceType},`;
        }
        text += `stream=${renderer.streamId} usage=${renderer.rendererInfo.usage} ` +
          `devices=${devices}; `;
      }
      return text.length > 0 ? text : 'none';
    } catch (err) {
      const error = err as Error;
      ScreenSaverLogger.warn(`active renderer read failed: ${error.message}`);
      return 'unknown';
    }
  }
}

export const screenSaverSystemAudioState: ScreenSaverSystemAudioStateService =
  new ScreenSaverSystemAudioStateService();
