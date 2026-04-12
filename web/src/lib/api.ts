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
    const headers: Record<string, string> = { 'Content-Type': 'application/json' };
    if (this.token) headers['Authorization'] = `Bearer ${this.token}`;

    const res = await fetch(`${this.baseUrl}${path}`, {
      method,
      headers,
      body: body ? JSON.stringify(body) : undefined,
      credentials: 'include',
    });

    if (
      res.status === 401
      && allowRefreshRetry
      && this.refreshHandler
      && this.canRetryWithRefresh(path)
    ) {
      const refreshedToken = await this.refreshHandler();
      if (refreshedToken) {
        return this.request<T>(method, path, body, false);
      }
    }

    return this.parseResponse<T>(res);
  }

  get<T>(path: string) { return this.request<T>('GET', path); }
  post<T>(path: string, body?: unknown) { return this.request<T>('POST', path, body); }
  patch<T>(path: string, body?: unknown) { return this.request<T>('PATCH', path, body); }
  delete<T>(path: string) { return this.request<T>('DELETE', path); }
}

export const api = new ApiClient(API_BASE);
