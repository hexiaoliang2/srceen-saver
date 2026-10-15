/**
 * =============================================================================
 * 相册卡片视图（PhotoCardView.ets）
 * =============================================================================
 *
 * 【这个文件是干什么的】
 * 相册卡片的界面实现：按所选间隔轮播照片（支持顺序/随机）、交叉淡入淡出
 * 过渡、预解码下一张（切图零等待）、自适应卡片尺寸解码、显示拍摄日期、
 * 以及「没照片/没权限」的占位提示。
 *
 * 【内存与性能设计（本文件的重点，面试常问）】
 * 屏保要长时间运行，相册卡片是内存压力最大的组件，所以有三条铁律：
 *   1. 按需解码：只解码「照片在卡片里实际显示的那块像素」（decodeFitted），
 *      不整图进内存；解码尺寸随卡片尺寸变化重算（尺寸变化后 300ms 防抖）；
 *   2. 限额驻留：同一时刻最多保留 3 张位图——正在显示的 currentPixel、
 *      预解码好的 incomingPixel（下一张）、正在退役的 retiringMap（淡出中）；
 *   3. 延迟释放：位图可能在淡入动画中还被 GPU 引用，立即 release 可能
 *      引发渲染异常，所以 releaseMapDeferred 延迟 100ms 再释放。
 *
 * 【变更项 4：等比完整显示（Contain）】
 * 画面一律完整可见、不裁切（ImageFit.Contain）；内容与卡片比例不一致时露出
 * 黑边（letterbox/pillarbox）区域全透明（变更项 4），判据函数在 common/ContentFit.ets。
 *
 * 【generation（代数）机制】
 * 异步解码随时可能被「换照片源/重新排版」打断。每次重置都 generation++，
 * 异步任务完成后先核对代数：对不上说明期间发生了重置，结果直接丢弃释放。
 * 这是防止「旧任务的结果污染新状态」的经典手法。
 *
 * 【随机模式防重复】
 * recentUris 记录最近 50 张播过的照片，随机抽取时跳过它们；
 * 50 张全在最近列表里（相册太小）时清空重来。
 * =============================================================================
 */

import { image } from '@kit.ImageKit';
import { ScreenSaverLogger } from '../common/Logger';
import { screenSaverImageLoader, screenSaverVpToPx, ScreenSaverFittedDecode } from '../common/ImageLoader';
import { screenSaverTicker } from '../common/Ticker';
import { screenSaverNetProbe } from '../common/NetProbe';
import { screenSaverMediaAccess, screenSaverPhotoAccessFlag } from '../common/MediaAccess';
import { screenSaverMotionDuration, SCREEN_SAVER_MOTION_PHOTO_FADE_MS } from '../common/Motion';
import { SCREEN_SAVER_METRICS } from '../common/ScreenSaverStyle';
import { screenSaverContainSize, ScreenSaverFitBars } from '../common/ContentFit';
import { screenSaverCardPalette, screenSaverTextShadow, ScreensaverCardPalette } from '../common/CardTheme';
import { screenSaverResolveDensity } from './CardCatalog';
import {
  SCREEN_SAVER_PHOTO_MIN_INTERVAL_SEC,
  SCREEN_SAVER_PHOTO_RECENT_DEDUP,
  ScreensaverCardDensity,
  ScreensaverCardInstance,
  ScreensaverCardMode,
  ScreensaverInkTone
} from '../model/ConfigModels';

// 尺寸变化后防抖 300ms 才重新解码（编辑模式连续拖尺寸时不狂解码）。
// 注意：这 300ms 内画面依旧可见——渲染层会把现有位图按新容器尺寸等比缩放，
// 松手后才换成按新尺寸重解码的清晰版本，因此不会闪黑或跳变。
const SCREEN_SAVER_REFIT_DEBOUNCE_MS: number = 300;
// 位图延迟释放时间：给淡入动画留出引用窗口。
const SCREEN_SAVER_DEFERRED_RELEASE_MS: number = 100;

@ComponentV2
export struct ScreensaverPhotoCard {
  @Param card: ScreensaverCardInstance = new ScreensaverCardInstance();
  @Param cardMode: ScreensaverCardMode = 'play';
  /** 屏保在前台时为 true，后台时暂停轮播（省电流控）。 */
  @Param cardActive: boolean = true;
  /**
   * 文字墨色档与投影兜底开关（变更项 3.2/3.3）。
   * 由屏保页统一解析后下发（同一来源）；默认浅色（设置面板等深色容器里直接用默认）。
   */
  @Param cardTone: ScreensaverInkTone = 'light';
  @Param cardHalo: boolean = false;
  /** 手动切图信号：父组件改这个数字（+1），编辑态预览就切下一张。 */
  @Param manualAdvanceSeed: number = 0;

  /**
   * 当前尺寸对应的内容密度档（尺寸矩阵查表得到）。
   * 直接读 card 的跨度而不是父组件透传的 @Param：@Trace 字段变化会立即
   * 触发本视图重算，不受 ForEach 复用/@Builder 按值传参的影响。
   */
  private density(): ScreensaverCardDensity {
    return screenSaverResolveDensity(this.card.cardType, this.card.colSpan, this.card.rowSpan);
  }

  // ---------- 渲染状态 ----------
  @Local currentPixel: image.PixelMap | undefined = undefined;  // 正在显示的照片
  @Local incomingPixel: image.PixelMap | undefined = undefined; // 淡入中的新照片（也兼作预解码缓存）
  @Local fadeOpacity: number = 0;            // 新照片的透明度（0→1 淡入）
  @Local placeholderVisible: boolean = true; // 是否显示「加载中…」
  @Local infoText: string = '';              // 左下角信息（拍摄日期/文件名）
  @Local deniedVisible: boolean = false;     // 「无相册权限」占位
  @Local emptyVisible: boolean = false;      // 「还没有照片」占位
  /**
   * 当前照片的适配结论（变更项 4）：none 无黑边 / horizontal 上下黑边 / vertical 左右黑边。
   * 由 screenSaverDecideFit（ContentFit.ets）算出来，用于日志与验证。
   */
  @Local contentBars: ScreenSaverFitBars = 'none';
  /**
   * 内容宽高比（宽/高，0 = 未知）——变更项 2 的核心输入：
   * 渲染层按它把照片放进「紧贴内容」的圆角容器（四角圆角落在画面上）。
   */
  @Local currentRatio: number = 0;
  @Local incomingRatio: number = 0;

  // ---------- 内部流水线状态（不需要触发 UI 刷新，普通字段即可） ----------
  private playList: string[] = [];      // 有效照片 uri 列表
  private excludedUris: string[] = [];  // 已确认损坏/不可读的照片，跳过
  private recentUris: string[] = [];    // 最近播过的（随机模式防重复）
  private cursor: number = 0;           // 当前播放下标
  private generation: number = 0;       // 流水线代数（重置计数器）
  private intervalTimer: number = -1;   // 轮播定时器句柄
  private refitTimer: number = -1;      // 重新解码防抖定时器
  private retiringMap: image.PixelMap | undefined = undefined; // 淡出中等待释放的旧照片
  private cardW: number = 0;            // 卡片实际宽（vp）
  private cardH: number = 0;            // 卡片实际高（vp）
  private started: boolean = false;     // 是否已开始过播放（决定首图加载时机）

  /** 组件挂载：先构建播放列表、同步空态占位。真正加载等 onAreaChange 拿到尺寸后开始。 */
  aboutToAppear(): void {
    this.buildPlayList();
    this.syncEmptyStates();
  }

  /** 组件销毁：停表 + 释放全部位图。generation++ 让在途异步任务全部作废。 */
  aboutToDisappear(): void {
    this.generation++;
    this.stopTimer();
    this.stopRefitTimer();
    this.releaseMapDeferred(this.currentPixel);
    this.releaseMapDeferred(this.incomingPixel);
    this.releaseMapDeferred(this.retiringMap);
    this.currentPixel = undefined;
    this.incomingPixel = undefined;
    this.retiringMap = undefined;
  }

  /** 照片列表变了（用户重新选照片/换相册）：清历史，重启流水线。 */
  @Monitor('card.photo.uris')
  onUrisChanged(): void {
    this.excludedUris = [];
    this.recentUris = [];
    this.syncEmptyStates();
    this.restartPipeline();
  }

  /** 播放顺序变了：清「最近播放」记录（重新随机），重启流水线。 */
  @Monitor('card.photo.order')
  onOrderChanged(): void {
    this.recentUris = [];
    this.restartPipeline();
  }

  /** 轮播间隔变了：只需重启定时器，不用重载照片。 */
  @Monitor('card.photo.intervalSec')
  onIntervalChanged(): void {
    this.restartTimer();
  }

  /** 信息开关或密度档变了：重新计算左下角文字（极简档下不显示）。 */
  @Monitor('card.photo.showInfo', 'card.colSpan', 'card.rowSpan')
  onInfoChanged(): void {
    this.updateInfoText();
  }

  /** 前后台/模式切换：前台恢复轮播，后台暂停（省电）。 */
  @Monitor('cardActive', 'cardMode')
  onActivityChanged(): void {
    if (this.cardMode === 'play' && this.cardActive) {
      this.restartTimer();
    } else {
      this.stopTimer();
    }
  }

  /** 编辑态手动切图信号（父组件把 manualAdvanceSeed +1 触发）。 */
  @Monitor('manualAdvanceSeed')
  onManualAdvance(): void {
    if (this.cardMode !== 'edit' || this.playList.length <= 1 || !this.started) {
      return;
    }
    void this.advanceNow();
  }

  /**
   * 编辑态手动切图：优先直接展示预解码好的下一张（立即响应），
   * 没有预解码就现场挑下一张解码。
   */
  private async advanceNow(): Promise<void> {
    const targetPixel = this.incomingPixel;
    const targetIndex = this.pendingNextIndex;
    if (targetPixel !== undefined && targetIndex >= 0) {
      this.retiringMap = this.currentPixel;
      this.pendingNextIndex = -1;
      this.completeFade(targetPixel, targetIndex);
      this.releaseMapDeferred(this.retiringMap);
      this.retiringMap = undefined;
      return;
    }
    this.cursor = this.pickNextIndex();
    const gen = this.generation;
    await this.loadCurrent(gen, 0);
  }

  /**
   * 同步两个占位态：
   * 没照片 + 用了指定相册 + 权限被拒 → 显示「无相册访问权限」（可跳设置）；
   * 没照片 + 权限正常 → 显示「还没有照片」。
   */
  private syncEmptyStates(): void {
    const hasUris = this.card.photo.uris.length > 0;
    this.deniedVisible = !hasUris && this.card.photo.sourceAlbum !== 'all' && screenSaverPhotoAccessFlag.albumDenied;
    this.emptyVisible = !hasUris && !this.deniedVisible;
  }

  /** 构建播放列表：过滤空 uri；游标越界回到 0。 */
  private buildPlayList(): void {
    const uris = this.card.photo.uris;
    const list: string[] = [];
    for (const uri of uris) {
      if (uri.length > 0) {
        list.push(uri);
      }
    }
    if (this.card.photo.order === 'shuffle' && this.cardMode === 'play') {
      this.playList = list;
    } else {
      this.playList = list;
    }
    if (this.cursor >= this.playList.length) {
      this.cursor = 0;
    }
  }

  /**
   * 挑下一张的下标。
   * 顺序模式：cursor+1 循环；
   * 随机模式：从「不在最近 50 张里、不是当前这张」的候选中随机挑一个；
   * 候选为空（相册太小全播遍了）时清空最近记录重挑，只剩一张就原地不动。
   */
  private pickNextIndex(): number {
    if (this.playList.length === 0) {
      return -1;
    }
    if (this.card.photo.order !== 'shuffle' || this.cardMode !== 'play') {
      this.cursor = (this.cursor + 1) % this.playList.length;
      return this.cursor;
    }
    // 最近列表最多 50 条，超出就移除最旧的（先进先出）
    if (this.recentUris.length >= SCREEN_SAVER_PHOTO_RECENT_DEDUP) {
      this.recentUris.shift();
    }
    const candidates: number[] = [];
    for (let index = 0; index < this.playList.length; index++) {
      const uri = this.playList[index];
      // 排除「当前这张」（多于一张时），避免随机连续抽到同一张
      if (uri === this.playList[this.cursor] && this.playList.length > 1) {
        continue;
      }
      if (this.recentUris.indexOf(uri) < 0) {
        candidates.push(index);
      }
    }
    if (candidates.length === 0) {
      // 全部在最近列表里：清空重挑一轮
      this.recentUris = [];
      for (let index = 0; index < this.playList.length; index++) {
        if (index !== this.cursor) {
          candidates.push(index);
        }
      }
      if (candidates.length === 0) {
        return this.cursor; // 只有一张照片
      }
    }
    const pick = candidates[Math.floor(Math.random() * candidates.length)];
    this.cursor = pick;
    return pick;
  }

  /** 记录刚播过的 uri（随机防重复用），带去重和 50 条上限。 */
  private noteRecent(uri: string): void {
    if (this.recentUris.indexOf(uri) >= 0) {
      return;
    }
    this.recentUris.push(uri);
    if (this.recentUris.length > SCREEN_SAVER_PHOTO_RECENT_DEDUP) {
      this.recentUris.shift();
    }
  }

  /**
   * 整体重启流水线（照片源/顺序变化时）：
   * 代数 +1（作废在途任务）→ 停表 → 释放预解码 → 重建列表。
   * 列表空就释放当前图显示占位；已开播则从头播放。
   */
  private restartPipeline(): void {
    this.generation++;
    this.stopTimer();
    this.stopRefitTimer();
    this.releaseIncoming();
    this.fadeOpacity = 0;
    this.buildPlayList();
    if (this.playList.length === 0) {
      const retire = this.currentPixel;
      this.currentPixel = undefined;
      this.releaseMapDeferred(retire);
      this.placeholderVisible = true;
      return;
    }
    if (this.started) {
      this.beginPlayback();
    } else {
      this.placeholderVisible = true;
    }
  }

  /** 从第一张开始播放：清预解码、游标归零、加载首图、启动轮播定时器。 */
  private beginPlayback(): void {
    this.generation++;
    const gen = this.generation;
    this.stopTimer();
    this.releaseIncoming();
    this.cursor = 0;
    this.placeholderVisible = false;
    void this.loadCurrent(gen, 0);
    this.restartTimer();
  }

  /**
   * 加载 cursor 指向的照片（自动跳过坏图）。
   * attempt 参数是「已经试过几张」的计数，试遍全列表都失败才放弃显示占位。
   * 每次异步操作（decodeUri）回来都核对 generation。
   */
  private async loadCurrent(gen: number, attempt: number): Promise<void> {
    if (this.playList.length === 0) {
      return;
    }
    if (attempt >= this.playList.length) {
      // 所有照片都坏了：清图显示占位
      const retire = this.currentPixel;
      this.currentPixel = undefined;
      this.releaseMapDeferred(retire);
      this.placeholderVisible = true;
      return;
    }
    const uri = this.playList[this.cursor];
    const decoded = await this.decodeUri(uri);
    if (gen !== this.generation) {
      // 期间发生了重置：本次结果作废，立刻释放防止泄漏
      this.releaseMap(decoded?.pixelMap);
      return;
    }
    if (decoded === undefined) {
      // 这张坏了：记入排除名单，挑下一张重试
      this.noteBroken(uri);
      const nextIndex = this.pickNextIndex();
      if (nextIndex < 0 || nextIndex === this.cursor) {
        this.placeholderVisible = true;
        return;
      }
      void this.loadCurrent(gen, attempt + 1);
      return;
    }
    const retire = this.currentPixel;
    this.currentPixel = decoded.pixelMap;
    this.currentRatio = decoded.decision.contentRatio;
    this.releaseMapDeferred(retire);
    this.fadeOpacity = 0;
    this.placeholderVisible = false;
    this.noteRecent(uri);
    this.updateInfoText();
    // 首图就绪后立刻后台预解码下一张（轮播到时零等待）
    void this.preloadNext(0);
  }

  /**
   * 定时轮播到点：优先播放预解码好的下一张（交叉淡入）。
   * 守卫条件：后台/未激活不播（cardActive + 心跳 isActive 双保险）；
   * 只有 1 张照片不播。
   */
  private async advance(): Promise<void> {
    if (!this.cardActive || !screenSaverTicker.isActive()) {
      return;
    }
    if (this.playList.length <= 1) {
      return;
    }
    const targetPixel = this.incomingPixel;
    const targetIndex = this.pendingNextIndex;
    if (targetPixel === undefined || targetIndex < 0) {
      // 预解码没就绪（或被清掉）：现场解码下一张
      this.cursor = this.pickNextIndex();
      const gen = this.generation;
      void this.loadCurrent(gen, 0);
      return;
    }
    // 旧图退役 → 淡入新图（动效关闭时直接切换）
    this.retiringMap = this.currentPixel;
    this.pendingNextIndex = -1;
    const gen = this.generation;
    const fadeMs = screenSaverMotionDuration(SCREEN_SAVER_MOTION_PHOTO_FADE_MS);
    if (fadeMs <= 0) {
      this.completeFade(targetPixel, targetIndex);
      this.releaseMapDeferred(this.retiringMap);
      this.retiringMap = undefined;
      return;
    }
    // 交叉淡入：新图 opacity 0→1 动画，结束后完成交接
    this.getUIContext().animateTo({
      duration: fadeMs,
      curve: Curve.EaseInOut,
      onFinish: (): void => {
        if (gen !== this.generation) {
          return; // 动画期间被重置：放弃交接（重置逻辑已处理释放）
        }
        this.completeFade(targetPixel, targetIndex);
      }
    }, (): void => {
      this.fadeOpacity = 1;
    });
  }

  /** 预解码的下一张对应的下标（-1 = 没有预解码）。 */
  private pendingNextIndex: number = -1;

  /**
   * 后台预解码下一张。开了「仅 WiFi 预取」时先探测网络类型，
   * 计费网络直接放弃（不偷跑流量）。坏图重试逻辑与 loadCurrent 相同。
   */
  private async preloadNext(attempt: number): Promise<void> {
    if (this.playList.length <= 1 || attempt >= this.playList.length) {
      return;
    }
    if (this.card.photo.wifiOnlyPrefetch) {
      const metered = await screenSaverNetProbe.isMetered();
      if (metered) {
        return;
      }
    }
    const gen = this.generation;
    const index = this.pickNextIndex();
    if (index < 0) {
      return;
    }
    const uri = this.playList[index];
    const decoded = await this.decodeUri(uri);
    if (gen !== this.generation) {
      this.releaseMap(decoded?.pixelMap);
      return;
    }
    if (decoded === undefined) {
      this.noteBroken(uri);
      void this.preloadNext(attempt + 1);
      return;
    }
    // 替换旧的预解码图（只保留一张预解码）
    const retire = this.incomingPixel;
    this.incomingPixel = decoded.pixelMap;
    this.incomingRatio = decoded.decision.contentRatio;
    this.pendingNextIndex = index;
    this.releaseMapDeferred(retire);
  }

  /** 淡入动画结束后的交接：新图转正、旧图释放、刷新信息、再预解码下一张。 */
  private completeFade(targetPixel: image.PixelMap, targetIndex: number): void {
    const retire = this.retiringMap;
    this.retiringMap = undefined;
    this.currentPixel = targetPixel;
    this.currentRatio = this.incomingRatio;
    this.cursor = targetIndex;
    this.incomingPixel = undefined;
    this.fadeOpacity = 0;
    this.releaseMapDeferred(retire);
    this.noteRecent(this.playList[targetIndex]);
    this.updateInfoText();
    void this.preloadNext(0);
  }

  /**
   * 计算左下角信息文字：
   * 优先显示拍摄日期（uriDates 查表），没有日期回退显示文件名（截断 40 字）。
   * 极简档（1×1 等小尺寸）按尺寸矩阵的规则不显示信息条。
   */
  private updateInfoText(): void {
    if (!this.card.photo.showInfo || this.playList.length === 0 || this.density() === 'minimal') {
      this.infoText = '';
      return;
    }
    const uri = this.playList[this.cursor];
    const taken = this.formatTakenDate(uri);
    if (taken.length > 0) {
      this.infoText = taken;
      return;
    }
    const slash = uri.lastIndexOf('/');
    const name = slash >= 0 ? uri.substring(slash + 1) : uri;
    this.infoText = name.length > 40 ? `${name.substring(0, 40)}…` : name;
  }

  /**
   * uri → 「2026/10/13」格式的拍摄日期。
   * 媒体库 DATE_ADDED 存的是「秒级」时间戳，手选照片路径可能没有日期记录，
   * 所以逐层防御：没记录返回空；数值非法返回空；
   * 秒/毫秒自适应（<100 亿视为秒，×1000 转毫秒）；Date 解析失败返回空。
   */
  private formatTakenDate(uri: string): string {
    const raw = this.card.photo.uriDates[uri];
    if (raw === undefined || raw.length === 0) {
      return '';
    }
    const value = Number(raw);
    if (!Number.isFinite(value) || value <= 0) {
      return '';
    }
    const ms = value < 10000000000 ? value * 1000 : value;
    const date = new Date(ms);
    const time = date.getTime();
    if (!Number.isFinite(time) || time <= 0) {
      return '';
    }
    return `${date.getFullYear()}/${date.getMonth() + 1}/${date.getDate()}`;
  }

  /** 尺寸变化后 300ms 防抖再重新解码当前照片（编辑模式连续缩放不狂解码）。 */
  private scheduleRefit(): void {
    this.stopRefitTimer();
    this.refitTimer = setTimeout((): void => {
      this.refitTimer = -1;
      this.refitCurrent();
    }, SCREEN_SAVER_REFIT_DEBOUNCE_MS);
  }

  /** 重新解码：代数 +1 作废在途任务，释放预解码，按新尺寸重载当前照片。 */
  private refitCurrent(): void {
    if (this.playList.length === 0 || !this.started) {
      return;
    }
    this.generation++;
    const gen = this.generation;
    this.releaseIncoming();
    void this.reloadCurrent(gen);
  }

  /** 按新尺寸重载当前这张（不换照片、不算 attempt）。 */
  private async reloadCurrent(gen: number): Promise<void> {
    const uri = this.playList[this.cursor];
    const decoded = await this.decodeUri(uri);
    if (gen !== this.generation) {
      this.releaseMap(decoded?.pixelMap);
      return;
    }
    if (decoded === undefined) {
      return;
    }
    const retire = this.currentPixel;
    this.currentPixel = decoded.pixelMap;
    this.currentRatio = decoded.decision.contentRatio;
    this.releaseMapDeferred(retire);
    this.placeholderVisible = false;
    void this.preloadNext(0);
  }

  /**
   * 解码一张照片（变更项 4：等比完整显示，不裁切）。
   *
   * 判据链路（可回归）：
   *   1. 容器像素 = 卡片实际像素（cardW/cardH → px），即「容器实际显示像素」；
   *   2. decodeFitted 读原图宽高，用 screenSaverFittedSize 算出等比放进容器的解码尺寸
   *      （绝不裁切、绝不放大、长边 ≤ 2160 防内存）；
   *   3. screenSaverDecideFit 给出「是否该有黑边、在哪一侧」的结论并打日志；
   *   4. 返回解码结果（调用方从 decision 里取内容比例，用于变更项 2 的圆角容器）。
   */
  private async decodeUri(uri: string): Promise<ScreenSaverFittedDecode | undefined> {
    if (this.excludedUris.indexOf(uri) >= 0) {
      return undefined;
    }
    const containerW = this.targetWidthPx();
    const containerH = this.targetHeightPx();
    const decoded = await screenSaverImageLoader.decodeFitted(uri, containerW, containerH);
    if (decoded === undefined) {
      return undefined;
    }
    this.contentBars = decoded.decision.bars;
    ScreenSaverLogger.info(`photo fit uri=${uri} card=${containerW}x${containerH}px content=` +
      `${decoded.contentWidth}x${decoded.contentHeight}px ratio=${decoded.decision.contentRatio.toFixed(3)}/` +
      `${decoded.decision.cardRatio.toFixed(3)} bars=${decoded.decision.bars}`);
    return decoded;
  }

  /** 当前墨色档的调色板（文字颜色与兜底投影色都从这里取，同一来源）。 */
  private palette(): ScreensaverCardPalette {
    return screenSaverCardPalette(this.cardTone);
  }

  /** 一般文字的投影参数（halo 关闭时 radius=0 = 不画）。 */
  private textShadow(): ShadowOptions {
    return screenSaverTextShadow(this.cardHalo, this.palette().halo);
  }

  /**
   * 信息条文字的投影：信息条压在**照片**上（内容像素不可预知，属复杂背景），
   * 因此恒启用轻投影（radius 4px，比正文投影更收敛），保证日期可读。
   */
  private infoTextShadow(): ShadowOptions {
    const options: ShadowOptions = {
      radius: 4,
      color: this.palette().halo,
      offsetX: 0,
      offsetY: 1
    };
    return options;
  }

  /**
   * 内容容器宽（vp）：按照片真实比例等比放进卡片（变更项 2）。
   * 比例未知（还没解码出图）时返回整卡宽（Contain 兜底渲染）。
   */
  private contentWidth(ratio: number): number {
    const width = this.cardW > 0 ? this.cardW : 320;
    const height = this.cardH > 0 ? this.cardH : 480;
    return screenSaverContainSize(width, height, ratio).width;
  }

  /** 内容容器高（vp），规则同 contentWidth。 */
  private contentHeight(ratio: number): number {
    const width = this.cardW > 0 ? this.cardW : 320;
    const height = this.cardH > 0 ? this.cardH : 480;
    return screenSaverContainSize(width, height, ratio).height;
  }

  /** 解码目标宽（px）：卡片实际宽，未测得时用 320vp 默认值。 */
  private targetWidthPx(): number {
    const width = this.cardW > 0 ? this.cardW : 320;
    return screenSaverVpToPx(width);
  }

  /** 解码目标高（px）：卡片实际高，未测得时用 480vp 默认值。 */
  private targetHeightPx(): number {
    const height = this.cardH > 0 ? this.cardH : 480;
    return screenSaverVpToPx(height);
  }

  /** 把坏图记入排除名单（只记一次，重复日志会刷屏）。 */
  private noteBroken(uri: string): void {
    if (this.excludedUris.indexOf(uri) < 0) {
      this.excludedUris.push(uri);
      ScreenSaverLogger.warn(`skip broken photo: ${uri}`);
    }
  }

  /**
   * 启动轮播定时器。守卫条件依次检查：
   * 已开播 / 多于一张 / 播放模式且激活 / 间隔>0。
   * 间隔有 15 秒下限（太频繁的切换毫无意义还费电）。
   */
  private restartTimer(): void {
    this.stopTimer();
    if (!this.started || this.playList.length <= 1) {
      return;
    }
    if (this.cardMode !== 'play' || !this.cardActive) {
      return;
    }
    if (this.card.photo.intervalSec <= 0) {
      return;
    }
    const intervalMs = Math.max(SCREEN_SAVER_PHOTO_MIN_INTERVAL_SEC, this.card.photo.intervalSec) * 1000;
    this.intervalTimer = setInterval((): void => {
      void this.advance();
    }, intervalMs);
  }

  private stopTimer(): void {
    if (this.intervalTimer >= 0) {
      clearInterval(this.intervalTimer);
      this.intervalTimer = -1;
    }
  }

  private stopRefitTimer(): void {
    if (this.refitTimer >= 0) {
      clearTimeout(this.refitTimer);
      this.refitTimer = -1;
    }
  }

  /** 释放预解码的位图并重置其下标。 */
  private releaseIncoming(): void {
    const map = this.incomingPixel;
    this.incomingPixel = undefined;
    this.pendingNextIndex = -1;
    this.releaseMapDeferred(map);
  }

  /** 立即释放一张位图（失败只记日志）。 */
  private releaseMap(map: image.PixelMap | undefined): void {
    if (map === undefined) {
      return;
    }
    try {
      map.release();
    } catch (err) {
      const error = err as Error;
      ScreenSaverLogger.warn(`pixelmap release failed: ${error.message}`);
    }
  }

  /**
   * 延迟 100ms 释放：刚被替换下来的位图可能还在渲染管线上（淡入动画），
   * 立即释放会导致花屏/黑块，延迟一下更安全。
   */
  private releaseMapDeferred(map: image.PixelMap | undefined): void {
    if (map === undefined) {
      return;
    }
    setTimeout((): void => {
      this.releaseMap(map);
    }, SCREEN_SAVER_DEFERRED_RELEASE_MS);
  }

  /** 权限被拒时的「去开启」按钮：跳系统授权设置界面。 */
  private async openPermissionSetting(): Promise<void> {
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      return;
    }
    await screenSaverMediaAccess.openPermissionSetting(context);
  }

  /**
   * 界面结构（Stack 分层，从底到顶）：
   *   1. 照片（**Contain：等比完整显示，不裁切**）放进「内容容器」：
   *      容器尺寸 = 按照片真实比例等比放进卡片（变更项 2），
   *      圆角 = 卡片圆角（SCREEN_SAVER_METRICS.cardRadius，10vp）并裁剪——
   *      内容未铺满时圆角落在画面四角上，铺满时与卡片圆角一致（已确认方案）；
   *   2. 淡入中的新照片（opacity 由动画驱动，同样容器 + 圆角）；
   *   3. 「加载中…」/「还没有照片」/「无相册访问权限」占位文字；
   *   4. 左下角信息条（拍摄日期/文件名；变更项 3.1：底色全透明，靠轻投影保证可读）。
   *
   * 变更项 3.1：卡片无任何黑色底块——加载占位不再铺深色底、信息条不再铺 45% 黑底，
   * 未铺满区域的留白全透明，露出屏保整体背景。
   */
  build() {
    Stack() {
      if (this.currentPixel !== undefined) {
        Stack() {
          Image(this.currentPixel)
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Contain)
        }
        .width(this.contentWidth(this.currentRatio))
        .height(this.contentHeight(this.currentRatio))
        .align(Alignment.Center)
        .borderRadius(SCREEN_SAVER_METRICS.cardRadius)
        .clip(true)
      }
      if (this.incomingPixel !== undefined) {
        Stack() {
          Image(this.incomingPixel)
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Contain)
        }
        .width(this.contentWidth(this.incomingRatio))
        .height(this.contentHeight(this.incomingRatio))
        .align(Alignment.Center)
        .borderRadius(SCREEN_SAVER_METRICS.cardRadius)
        .clip(true)
        .opacity(this.fadeOpacity)
      }
      if (this.placeholderVisible && !this.deniedVisible && !this.emptyVisible && this.density() !== 'minimal') {
        Text('加载中…')
          .fontSize(12)
          .fontColor(this.palette().textTertiary)
          .textShadow(this.textShadow())
      }
      if (this.emptyVisible && this.density() !== 'minimal') {
        Column({ space: 4 }) {
          Text('还没有照片')
            .fontSize(13)
            .fontColor(this.palette().textSecondary)
            .textShadow(this.textShadow())
          Text('在配置中选择相册来源')
            .fontSize(11)
            .fontColor(this.palette().textTertiary)
            .textShadow(this.textShadow())
        }
      }
      if (this.deniedVisible && this.density() !== 'minimal') {
        Column({ space: 6 }) {
          Text('无相册访问权限')
            .fontSize(13)
            .fontColor(this.palette().textSecondary)
            .textShadow(this.textShadow())
          // 「去开启」按钮只在编辑态显示（播放态不可交互，保持纯净）
          if (this.cardMode === 'edit') {
            Column() {
              Text('去开启')
                .fontSize(12)
                .fontColor('#4A9EFF')
            }
            .constraintSize({ minWidth: 40, minHeight: 40 })
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
            .borderRadius(6)
            .backgroundColor('#26262B')
            .onClick((): void => {
              void this.openPermissionSetting();
            })
          }
        }
      }
      if (this.infoText.length > 0) {
        Row() {
          Text(this.infoText)
            .fontSize(this.density() === 'compact' ? 9 : 10)
            .fontColor(this.palette().textSecondary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            // 变更项 3.1/3.3：信息条底色全透明；文字压在照片上，恒用轻投影兜底。
            .textShadow(this.infoTextShadow())
        }
        .width('100%')
        .padding({ left: 8, right: 8, top: 3, bottom: 3 })
        .align(Alignment.BottomStart)
      }
    }
    .width('100%')
    .height('100%')
    .clip(true)
    /**
     * 尺寸监听（流水线的启动开关）：
     * - 首次拿到有效尺寸 → started = true，开始播放；
     * - 之后尺寸变化超 1vp → 300ms 防抖重新解码（新尺寸更清晰）。
     * 注意照片解码依赖真实尺寸，所以必须等这里而不是 aboutToAppear 就加载。
     */
    .onAreaChange((oldArea: Area, newArea: Area): void => {
      const width = typeof newArea.width === 'number' ? newArea.width : 0;
      const height = typeof newArea.height === 'number' ? newArea.height : 0;
      if (width <= 0 || height <= 0) {
        return;
      }
      const sizeChanged = Math.abs(width - this.cardW) > 1 || Math.abs(height - this.cardH) > 1;
      this.cardW = width;
      this.cardH = height;
      if (!this.started) {
        this.started = true;
        if (this.playList.length > 0) {
          this.beginPlayback();
        }
      } else if (sizeChanged && this.playList.length > 0) {
        this.scheduleRefit();
      }
      this.syncEmptyStates();
    })
  }
}
