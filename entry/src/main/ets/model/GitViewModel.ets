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

const SCREEN_SAVER_GIT_ENDPOINT: string = 'https://api.github.com/graphql';
const SCREEN_SAVER_GIT_QUERY: string = 'query($login:String!,$from:DateTime!,$to:DateTime!){' +
  'user(login:$login){contributionsCollection(from:$from,to:$to){' +
  'contributionCalendar{totalContributions weeks{contributionDays{date contributionCount}}}}}}';

interface GitRawDay {
  date?: string;
  contributionCount?: number;
}

interface GitRawWeek {
  contributionDays?: GitRawDay[];
}

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

interface GitRawErrors {
  message?: string;
}

interface GitRawResponse {
  data?: GitRawUserHolder;
  errors?: GitRawErrors[];
}

interface GitRawUserHolder {
  user?: GitRawUser;
}

interface GitRequestVariables {
  login: string;
  from: string;
  to: string;
}

interface GitRequestBody {
  query: string;
  variables: GitRequestVariables;
}

@ObservedV2
class ScreenSaverGitViewModel {
  @Trace state: GitLoadState = 'idle';
  @Trace errorText: string = '';
  @Trace days: ScreensaverGitDay[] = [];
  @Trace total: number = 0;
  @Trace fetchedAt: number = 0;
  @Trace sourceUsername: string = '';

  private inflight: boolean = false;
  private lastAttemptMs: number = 0;

  hydrateFromCache(): void {
    const cache = screenSaverAppModel.getGitCache();
    if (cache === undefined || cache.days.length === 0) {
      return;
    }
    this.days = cache.days;
    this.total = cache.total;
    this.fetchedAt = cache.fetchedAt;
    this.sourceUsername = cache.username;
    if (this.state === 'idle' || this.state === 'error') {
      this.state = 'success';
    }
  }

  shouldAutoRefresh(): boolean {
    const baseline = Math.max(this.lastAttemptMs, this.fetchedAt);
    if (baseline === 0) {
      return true;
    }
    return Date.now() - baseline >= SCREEN_SAVER_GIT_THROTTLE_MS;
  }

  async refresh(username: string, useCacheOnFailure: boolean): Promise<void> {
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
        screenSaverAppModel.setGitCache(parsed);
      } else {
        this.applyFailure(useCacheOnFailure, '数据解析失败');
      }
    } catch (err) {
      const error = err as BusinessError;
      ScreenSaverLogger.warn(`git refresh failed: code=${error.code}`);
      this.applyFailure(useCacheOnFailure, '网络请求失败');
    } finally {
      this.inflight = false;
    }
  }

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
    const holder = raw.data;
    const user = holder !== undefined ? holder.user : undefined;
    const collection = user !== undefined ? user.contributionsCollection : undefined;
    const calendar = collection !== undefined ? collection.contributionCalendar : undefined;
    if (calendar === undefined) {
      return undefined;
    }
    const days: ScreensaverGitDay[] = [];
    for (const week of calendar.weeks ?? []) {
      for (const rawDay of week.contributionDays ?? []) {
        const date = rawDay.date;
        if (date === undefined || date.length === 0) {
          continue;
        }
        const day: ScreensaverGitDay = { date: date, count: rawDay.contributionCount ?? 0 };
        days.push(day);
      }
    }
    if (days.length === 0) {
      return undefined;
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

export const screenSaverGitViewModel: ScreenSaverGitViewModel = new ScreenSaverGitViewModel();
