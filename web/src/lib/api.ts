import { APP_RELEASE } from '@/lib/release-meta';
import { createRequestId, webLogger } from '@/lib/logger';

const API_BASE = import.meta.env.VITE_API_URL || 'http://localhost:3001/api/v1';

export interface ApiResponse<T> {
  success: boolean;
  data: T | null;
  meta: Record<string, unknown>;
  error: { code: string; message: string } | null;
}

type RefreshHandler = () => Promise<string | null>;

class ApiClient {
  private baseUrl: string;
  private token: string | null = null;
  private refreshHandler: RefreshHandler | null = null;

  constructor(baseUrl: string) {
    this.baseUrl = baseUrl;
  }

  setToken(token: string | null) {
    this.token = token;
  }

  setRefreshHandler(handler: RefreshHandler | null) {
    this.refreshHandler = handler;
  }

  private async parseResponse<T>(res: Response): Promise<ApiResponse<T>> {
    const contentType = res.headers.get('content-type') ?? '';
    if (contentType.includes('application/json')) {
      return res.json() as Promise<ApiResponse<T>>;
    }

    return {
      success: res.ok,
      data: null,
      meta: {},
      error: res.ok
        ? null
        : {
            code: String(res.status),
            message: res.statusText || 'Request failed',
          },
    };
  }

  private canRetryWithRefresh(path: string): boolean {
    return path !== '/auth/refresh' && !path.startsWith('/auth/oauth/');
  }

  private async request<T>(
    method: string,
    path: string,
    body?: unknown,
    allowRefreshRetry = true,
  ): Promise<ApiResponse<T>> {
    const requestId = createRequestId();
    const headers: Record<string, string> = {
      'Content-Type': 'application/json',
      'X-Request-ID': requestId,
      'X-Client-Platform': APP_RELEASE.platform,
      'X-Client-Version': APP_RELEASE.version,
      'X-Client-Build': APP_RELEASE.buildId,
    };
    if (this.token) headers['Authorization'] = `Bearer ${this.token}`;

    let res: Response
    try {
      res = await fetch(`${this.baseUrl}${path}`, {
        method,
        headers,
        body: body ? JSON.stringify(body) : undefined,
        credentials: 'include',
      });
    } catch (error) {
      webLogger.error('API request threw before receiving a response', {
        method,
        path,
        requestId,
        error: error instanceof Error
          ? { name: error.name, message: error.message, stack: error.stack }
          : String(error),
      });
      throw error;
    }

    if (
      res.status === 401
      && allowRefreshRetry
      && this.refreshHandler
      && this.canRetryWithRefresh(path)
    ) {
      webLogger.warn('API request received 401; attempting token refresh', {
        method,
        path,
        requestId,
      });
      const refreshedToken = await this.refreshHandler();
      if (refreshedToken) {
        return this.request<T>(method, path, body, false);
      }
    }

    const parsed = await this.parseResponse<T>(res);
    if (!res.ok || parsed.success === false) {
      webLogger.error('API request failed', {
        method,
        path,
        requestId,
        statusCode: res.status,
        error: parsed.error?.message ?? 'Unknown API failure',
      });
    }

    return parsed;
  }

  get<T>(path: string) { return this.request<T>('GET', path); }
  post<T>(path: string, body?: unknown) { return this.request<T>('POST', path, body); }
  patch<T>(path: string, body?: unknown) { return this.request<T>('PATCH', path, body); }
  delete<T>(path: string) { return this.request<T>('DELETE', path); }
}

export const api = new ApiClient(API_BASE);
