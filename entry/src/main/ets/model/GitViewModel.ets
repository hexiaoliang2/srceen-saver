/**
 * =============================================================================
 * Git 贡献数据视图模型（GitViewModel.ets）
 * =============================================================================
 *
 * 【这个文件是干什么的】
 * 负责从 GitHub 的 GraphQL 接口拉取某用户近一年的「贡献热力图」数据
 * （每天提交了几次），并管理加载状态（loading/success/offline/error）、
 * 节流（30 分钟内不重复请求）和离线缓存。
 *
 * 【为什么固定取 370 天】
 * 用户在界面上可选展示 12/20/26/52 周。请求时一次性取 370 天（一年+5 天
 * 缓冲），前端再按所选周数截取。这样切换周数不需要重新发请求。
 *
 * 【三重防护，保证屏保不被网络问题搞崩】
 *   1. inflight 标记：上一次请求没回来之前不再发新请求（防重复点击）；
 *   2. 节流（THROTTLE_MS=30 分钟）：进了屏保反复进出也不会狂打接口；
 *   3. 失败降级：请求/解析失败时优先显示上次的缓存数据（offline 态），
 *      一点缓存都没有才显示错误提示。
 *
 * 【小白知识点：GraphQL 是什么】
 * 一种「按需取字段」的接口协议：客户端用一段查询语句声明要什么数据，
 * 服务端只返回这些字段。比 REST 更省流量，但需要 GitHub token 鉴权。
 * =============================================================================
 */

import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { ScreenSaverLogger } from '../common/Logger';
import { screenSaverAppModel } from './AppModel';
import {
  GitLoadState,
  SCREEN_SAVER_GIT_FETCH_TIMEOUT_MS,
  SCREEN_SAVER_GIT_THROTTLE_MS,
  ScreensaverGitData,
  ScreensaverGitDay
} from './ConfigModels';

// GitHub GraphQL 接口地址（需在模块里申请网络权限，见 module.json5）。
const SCREEN_SAVER_GIT_ENDPOINT: string = 'https://api.github.com/graphql';
// GraphQL 查询语句：按用户名 + 时间范围，取贡献日历（总数 + 每天的提交数）。
const SCREEN_SAVER_GIT_QUERY: string = 'query($login:String!,$from:DateTime!,$to:DateTime!){' +
  'user(login:$login){contributionsCollection(from:$from,to:$to){' +
  'contributionCalendar{totalContributions weeks{contributionDays{date contributionCount}}}}}}';

// ---------- 以下 interface 描述 GitHub 返回 JSON 的结构（全部字段可选） ----------
// 逐层嵌套：response → data → user → contributionsCollection → contributionCalendar

/** 一天的贡献：日期 + 提交数。 */
interface GitRawDay {
  date?: string;
  contributionCount?: number;
}

/** 一周（贡献日历按周组织）。 */
interface GitRawWeek {
  contributionDays?: GitRawDay[];
}

/** 贡献日历：总贡献数 + 按周的每日明细。 */
interface GitRawCalendar {
  totalContributions?: number;
  weeks?: GitRawWeek[];
}

interface GitRawCollection {
  contributionCalendar?: GitRawCalendar;
}

interface GitRawUser {
  contributionsCollection?: GitRawCollection;
}

/** GraphQL 错误对象（可能返回多个）。 */
interface GitRawErrors {
  message?: string;
}

/** GraphQL 响应根结构：data（成功）或 errors（失败）至少有其一。 */
interface GitRawResponse {
  data?: GitRawUserHolder;
  errors?: GitRawErrors[];
}

interface GitRawUserHolder {
  user?: GitRawUser;
}

/** GraphQL 请求变量：用户名 + 起止时间。 */
interface GitRequestVariables {
  login: string;
  from: string;
  to: string;
}

/** GraphQL 请求体：查询语句 + 变量。 */
interface GitRequestBody {
  query: string;
  variables: GitRequestVariables;
}

/**
 * Git 视图模型：@ObservedV2 让以下 @Trace 字段变化时自动刷新界面。
 * 比如 state 从 'loading' 变 'success'，Git 卡片立即从加载动画变成热力图。
 */
@ObservedV2
class ScreenSaverGitViewModel {
  @Trace state: GitLoadState = 'idle';
  @Trace errorText: string = '';            // 给用户看的错误/提示文案
  @Trace days: ScreensaverGitDay[] = [];    // 每日贡献序列
  @Trace total: number = 0;                 // 总贡献数
  @Trace fetchedAt: number = 0;             // 最近一次成功抓取的时间戳
  @Trace sourceUsername: string = '';       // 数据对应的用户名

  /** 是否有请求正在进行（防止并发重复请求）。 */
  private inflight: boolean = false;
  /** 最近一次「发起请求」的时间（节流基准）。 */
  private lastAttemptMs: number = 0;

  /**
   * 用磁盘缓存「注水」：应用启动/进入屏保时先显示上次抓取的数据，
   * 让界面立即有内容（而不是空转加载），后台再择机刷新。
   */
  hydrateFromCache(): void {
    const cache = screenSaverAppModel.getGitCache();
    if (cache === undefined || cache.days.length === 0) {
      return;
    }
    this.days = cache.days;
    this.total = cache.total;
    this.fetchedAt = cache.fetchedAt;
    this.sourceUsername = cache.username;
    // 只有还没成功过（或上次失败）才借缓存升级为 success；
    // 已经有更新数据时不回退。
    if (this.state === 'idle' || this.state === 'error') {
      this.state = 'success';
    }
  }

  /**
   * 是否应该自动刷新：距上次请求（无论成败）超过 30 分钟节流窗口才放行。
   * baseline 取「上次尝试」和「上次成功」的较大者。
   */
  shouldAutoRefresh(): boolean {
    const baseline = Math.max(this.lastAttemptMs, this.fetchedAt);
    if (baseline === 0) {
      return true; // 从未请求过
    }
    return Date.now() - baseline >= SCREEN_SAVER_GIT_THROTTLE_MS;
  }

  /**
   * 拉取最新数据（手动刷新/进入屏保时调用）。
   * 前置检查（token、用户名）不通过直接置错误态，不发网络请求。
   * 成功后写入 AppModel 缓存（离线兜底的数据源）。
   */
  async refresh(username: string, useCacheOnFailure: boolean): Promise<void> {
    // 请求进行中：直接忽略本次调用（防重复点击）。
    if (this.inflight) {
      return;
    }
    const token = screenSaverAppModel.getGitToken();
    if (token.length === 0) {
      this.state = 'error';
      this.errorText = '未配置 GitHub token · 请在配置中填写';
      return;
    }
    if (username.length === 0) {
      this.state = 'error';
      this.errorText = '未配置用户名';
      return;
    }
    this.inflight = true;
    this.lastAttemptMs = Date.now();
    this.state = 'loading';
    this.errorText = '';
    try {
      const text = await this.requestGraphql(username, token);
      const parsed = this.parseResponse(text, username);
      if (parsed !== undefined) {
        this.state = 'success';
        this.days = parsed.days;
        this.total = parsed.total;
        this.fetchedAt = parsed.fetchedAt;
        this.sourceUsername = parsed.username;
        // 成功数据写进磁盘缓存，供离线时显示
        screenSaverAppModel.setGitCache(parsed);
      } else {
        this.applyFailure(useCacheOnFailure, '数据解析失败');
      }
    } catch (err) {
      const error = err as BusinessError;
      ScreenSaverLogger.warn(`git refresh failed: code=${error.code}`);
      this.applyFailure(useCacheOnFailure, '网络请求失败');
    } finally {
      this.inflight = false; // 无论成败都解除占用
    }
  }

  /**
   * 失败降级策略（核心是「有旧数据绝不显示空白」）：
   *   1. 内存里已有数据 + 允许用缓存 → 进 offline 态，继续显示旧数据；
   *   2. 内存没有但磁盘缓存有 → 把缓存读出来进 offline 态；
   *   3. 任何数据都没有 → 只能进 error 态显示错误提示。
   */
  private applyFailure(useCacheOnFailure: boolean, reason: string): void {
    if (useCacheOnFailure && this.days.length > 0) {
      this.state = 'offline';
      this.errorText = reason;
      return;
    }
    const cache = screenSaverAppModel.getGitCache();
    if (useCacheOnFailure && cache !== undefined && cache.days.length > 0) {
      this.days = cache.days;
      this.total = cache.total;
      this.fetchedAt = cache.fetchedAt;
      this.state = 'offline';
      this.errorText = reason;
      return;
    }
    this.state = 'error';
    this.errorText = reason;
  }

  /**
   * 发送 GraphQL 请求。
   * - 时间范围：从「当前时间往前 370 天」到「当前时间」；
   * - 鉴权：Authorization: bearer <token>；
   * - 超时：连接/读取各 10 秒；
   * - finally 里 destroy()：HTTP 请求对象是系统资源，用完必须销毁。
   * 非 200 状态码、非文本响应都抛错（由 refresh 的 catch 统一降级）。
   */
  private async requestGraphql(username: string, token: string): Promise<string> {
    const to = new Date();
    const from = new Date(to.getTime() - 370 * 24 * 3600 * 1000);
    const variables: GitRequestVariables = {
      login: username,
      from: from.toISOString(),
      to: to.toISOString()
    };
    const body: GitRequestBody = {
      query: SCREEN_SAVER_GIT_QUERY,
      variables: variables
    };
    const bodyText = JSON.stringify(body);
    const headers: Record<string, string> = {
      'Content-Type': 'application/json',
      'Authorization': `bearer ${token}`,
      'User-Agent': 'ScreenSaverApp'
    };
    const request = http.createHttp();
    try {
      const response = await request.request(SCREEN_SAVER_GIT_ENDPOINT, {
        method: http.RequestMethod.POST,
        header: headers,
        extraData: bodyText,
        connectTimeout: SCREEN_SAVER_GIT_FETCH_TIMEOUT_MS,
        readTimeout: SCREEN_SAVER_GIT_FETCH_TIMEOUT_MS
      });
      if (response.responseCode !== 200) {
        throw new Error(`http ${response.responseCode}`);
      }
      const result = response.result;
      if (typeof result !== 'string') {
        throw new Error('unexpected response type');
      }
      return result;
    } finally {
      request.destroy();
    }
  }

  /**
   * 解析 GraphQL 响应文本 → 严格数据结构。
   * 逐层取值（?.风格的防御写法）：任何一层缺失都返回 undefined 走降级。
   * GraphQL 特殊性：HTTP 200 也可能带 errors（部分失败），
   * 所以错误信息单独提取给用户看，数据部分照常尝试解析。
   */
  private parseResponse(text: string, username: string): ScreensaverGitData | undefined {
    let raw: GitRawResponse | undefined = undefined;
    try {
      raw = JSON.parse(text) as GitRawResponse;
    } catch (err) {
      const error = err as Error;
      ScreenSaverLogger.warn(`git response parse failed: ${error.message}`);
      return undefined;
    }
    const errors = raw.errors;
    if (errors !== undefined && errors.length > 0) {
      const first = errors[0];
      this.errorText = first.message !== undefined ? first.message : 'GraphQL 错误';
      ScreenSaverLogger.warn(`git graphql errors: ${this.errorText}`);
    }
    // 层层下钻：data → user → contributionsCollection → contributionCalendar
    const holder = raw.data;
    const user = holder !== undefined ? holder.user : undefined;
    const collection = user !== undefined ? user.contributionsCollection : undefined;
    const calendar = collection !== undefined ? collection.contributionCalendar : undefined;
    if (calendar === undefined) {
      return undefined;
    }
    // 贡献日历按「周数组 → 天数组」组织，拍平成逐日序列。
    const days: ScreensaverGitDay[] = [];
    for (const week of calendar.weeks ?? []) {
      for (const rawDay of week.contributionDays ?? []) {
        const date = rawDay.date;
        if (date === undefined || date.length === 0) {
          continue; // 跳过缺日期的脏数据
        }
        const day: ScreensaverGitDay = { date: date, count: rawDay.contributionCount ?? 0 };
        days.push(day);
      }
    }
    if (days.length === 0) {
      return undefined; // 空数据视为失败
    }
    const data: ScreensaverGitData = {
      username: username,
      days: days,
      fetchedAt: Date.now(),
      total: calendar.totalContributions ?? 0
    };
    return data;
  }
}

// 全局唯一实例（单例）：inflight/节流时间戳因此全局共享。
export const screenSaverGitViewModel: ScreenSaverGitViewModel = new ScreenSaverGitViewModel();
