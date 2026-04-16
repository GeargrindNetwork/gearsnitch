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

export type CycleType = 'peptide' | 'steroid' | 'mixed' | 'other';
export type CycleStatus = 'planned' | 'active' | 'paused' | 'completed' | 'archived';

export interface Cycle {
  _id: string;
  userId: string;
  name: string;
  type: CycleType;
  status: CycleStatus;
  startDate: string;
  endDate: string | null;
  timezone: string;
  notes: string | null;
  createdAt: string;
  updatedAt: string;
}

export interface CycleMonthDay {
  date: string;
  count: number;
}

export interface CycleMonthSummary {
  year: number;
  month: number;
  days: CycleMonthDay[];
  totalEntries: number;
  activeCycles: number;
}

export type MedicationDoseCategory = 'steroid' | 'peptide' | 'oralMedication';
export type MedicationDoseUnit = 'mg' | 'mcg' | 'iu' | 'ml' | 'units';
export type MedicationDoseSource = 'manual' | 'ios' | 'web' | 'imported';
export type CycleCompoundCategory = 'peptide' | 'steroid' | 'support' | 'pct' | 'other';
export type CycleDoseUnit = MedicationDoseUnit;
export type CycleRoute = 'injection' | 'oral' | 'topical' | 'other';

export interface CycleCompoundPlan {
  compoundName: string;
  compoundCategory: CycleCompoundCategory;
  targetDose: number | null;
  doseUnit: CycleDoseUnit;
  route: CycleRoute | null;
}

export interface CreateCycleInput {
  name: string;
  type: CycleType;
  status: CycleStatus;
  startDate: string;
  endDate?: string | null;
  timezone: string;
  notes?: string | null;
  tags?: string[];
  compounds?: CycleCompoundPlan[];
}

export interface UpdateCycleInput {
  name?: string;
  type?: CycleType;
  status?: CycleStatus;
  startDate?: string;
  endDate?: string | null;
  timezone?: string;
  notes?: string | null;
  tags?: string[];
  compounds?: CycleCompoundPlan[];
}

export interface MedicationCategoryDoseMg {
  steroid: number;
  peptide: number;
  oralMedication: number;
}

export interface CalendarMedicationOverlay {
  entryCount: number;
  totalDoseMg: number;
  categoryDoseMg: MedicationCategoryDoseMg;
  hasMedication: boolean;
}

export interface MedicationYearGraphResponse {
  year: number;
  axis: {
    x: {
      startDay: number;
      endDay: number;
    };
    yMg: {
      min: number;
      max: number;
    };
  };
  series: {
    steroidMgByDay: number[];
    peptideMgByDay: number[];
    oralMedicationMgByDay: number[];
  };
  totalsMg: {
    steroid: number;
    peptide: number;
    oralMedication: number;
    all: number;
  };
}

export interface MedicationDoseAmount {
  value: number;
  unit: MedicationDoseUnit;
}

export interface MedicationDose {
  _id: string;
  userId: string;
  cycleId: string | null;
  dateKey: string;
  dayOfYear: number;
  category: MedicationDoseCategory;
  compoundName: string;
  dose: MedicationDoseAmount;
  doseMg: number | null;
  occurredAt: string | null;
  notes: string | null;
  source: MedicationDoseSource;
  createdAt: string | null;
  updatedAt: string | null;
}

export interface CreateMedicationDoseInput {
  cycleId?: string | null;
  dateKey?: string;
  category: MedicationDoseCategory;
  compoundName: string;
  dose: MedicationDoseAmount;
  occurredAt: string;
  notes?: string | null;
  source?: MedicationDoseSource;
}

export interface UpdateMedicationDoseInput {
  cycleId?: string | null;
  dateKey?: string;
  category?: MedicationDoseCategory;
  compoundName?: string;
  dose?: MedicationDoseAmount;
  occurredAt?: string;
  notes?: string | null;
  source?: MedicationDoseSource;
}

export interface MedicationDoseQueryOptions {
  category?: MedicationDoseCategory;
  from?: string;
  to?: string;
  page?: number;
  limit?: number;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function asString(value: unknown, fallback = ''): string {
  return typeof value === 'string' ? value : fallback;
}

function asNullableString(value: unknown): string | null {
  return typeof value === 'string' ? value : null;
}

function asNumber(value: unknown, fallback = 0): number {
  return typeof value === 'number' && Number.isFinite(value) ? value : fallback;
}

function asNumberArray(value: unknown): number[] {
  if (!Array.isArray(value)) {
    return [];
  }

  return value.map((entry) => asNumber(entry));
}

function normalizeCycle(raw: unknown): Cycle | null {
  if (!isRecord(raw)) {
    return null;
  }

  const id = asString(raw._id ?? raw.id);
  const name = asString(raw.name);
  const startDate = asString(raw.startDate);
  const status = asString(raw.status) as CycleStatus;
  const type = asString(raw.type) as CycleType;

  if (!id || !name || !startDate || !status || !type) {
    return null;
  }

  return {
    _id: id,
    userId: asString(raw.userId),
    name,
    type,
    status,
    startDate,
    endDate: asNullableString(raw.endDate),
    timezone: asString(raw.timezone, 'UTC'),
    notes: asNullableString(raw.notes),
    createdAt: asString(raw.createdAt),
    updatedAt: asString(raw.updatedAt),
  };
}

function normalizeCyclesPayload(data: unknown): Cycle[] {
  const source = Array.isArray(data)
    ? data
    : isRecord(data) && Array.isArray(data.cycles)
      ? data.cycles
      : isRecord(data) && Array.isArray(data.items)
        ? data.items
        : [];

  return source
    .map(normalizeCycle)
    .filter((cycle): cycle is Cycle => cycle !== null);
}

function normalizeCyclePayload(data: unknown): Cycle | null {
  if (isRecord(data) && 'cycle' in data) {
    return normalizeCycle(data.cycle);
  }

  return normalizeCycle(data);
}

function normalizeMedicationDose(raw: unknown): MedicationDose | null {
  if (!isRecord(raw)) {
    return null;
  }

  const id = asString(raw._id ?? raw.id);
  const userId = asString(raw.userId);
  const category = asString(raw.category) as MedicationDoseCategory;
  const compoundName = asString(raw.compoundName);
  const dateKey = asString(raw.dateKey);

  if (!id || !userId || !category || !compoundName || !dateKey) {
    return null;
  }

  const dose = isRecord(raw.dose) ? raw.dose : {};

  return {
    _id: id,
    userId,
    cycleId: asNullableString(raw.cycleId),
    dateKey,
    dayOfYear: asNumber(raw.dayOfYear),
    category,
    compoundName,
    dose: {
      value: asNumber(dose.value),
      unit: asString(dose.unit, 'mg') as MedicationDoseUnit,
    },
    doseMg: typeof raw.doseMg === 'number' ? raw.doseMg : null,
    occurredAt: asNullableString(raw.occurredAt),
    notes: asNullableString(raw.notes),
    source: asString(raw.source, 'manual') as MedicationDoseSource,
    createdAt: asNullableString(raw.createdAt),
    updatedAt: asNullableString(raw.updatedAt),
  };
}

function normalizeMedicationDoseCollection(data: unknown): MedicationDose[] {
  const source = Array.isArray(data)
    ? data
    : isRecord(data) && Array.isArray(data.doses)
      ? data.doses
      : isRecord(data) && Array.isArray(data.items)
        ? data.items
        : [];

  return source
    .map(normalizeMedicationDose)
    .filter((dose): dose is MedicationDose => dose !== null);
}

function normalizeMedicationDosePayload(data: unknown): MedicationDose | null {
  if (isRecord(data) && 'dose' in data) {
    return normalizeMedicationDose(data.dose);
  }

  return normalizeMedicationDose(data);
}

function normalizeMonthDays(rawDays: unknown): CycleMonthDay[] {
  if (Array.isArray(rawDays)) {
    return rawDays
      .map((rawDay) => {
        if (!isRecord(rawDay)) {
          return null;
        }
        const date = asString(rawDay.date);
        if (!date) {
          return null;
        }
        const count = asNumber(rawDay.count ?? rawDay.entries ?? rawDay.entryCount);
        return { date, count };
      })
      .filter((day): day is CycleMonthDay => day !== null);
  }

  if (!isRecord(rawDays)) {
    return [];
  }

  return Object.entries(rawDays)
    .map(([date, value]) => {
      if (isRecord(value)) {
        return {
          date,
          count: asNumber(value.count ?? value.entries ?? value.entryCount),
        };
      }
      return {
        date,
        count: asNumber(value),
      };
    })
    .sort((left, right) => left.date.localeCompare(right.date));
}

export async function getCycles(): Promise<Cycle[]> {
  const response = await api.get<unknown>('/cycles');
  if (!response.success || response.data == null) {
    throw new Error(response.error?.message || 'Failed to load cycles');
  }
  return normalizeCyclesPayload(response.data);
}

export async function createCycle(input: CreateCycleInput): Promise<Cycle> {
  const response = await api.post<unknown>('/cycles', {
    ...input,
    tags: input.tags ?? [],
    compounds: input.compounds ?? [],
    notes: input.notes ?? null,
    endDate: input.endDate ?? null,
  });
  const cycle = normalizeCyclePayload(response.data);
  if (!response.success || !cycle) {
    throw new Error(response.error?.message || 'Failed to create cycle');
  }
  return cycle;
}

export async function updateCycle(id: string, input: UpdateCycleInput): Promise<Cycle> {
  const response = await api.patch<unknown>(`/cycles/${id}`, input);
  const cycle = normalizeCyclePayload(response.data);
  if (!response.success || !cycle) {
    throw new Error(response.error?.message || 'Failed to update cycle');
  }
  return cycle;
}

export async function deleteCycle(id: string): Promise<void> {
  const response = await api.delete<unknown>(`/cycles/${id}`);
  if (!response.success) {
    throw new Error(response.error?.message || 'Failed to delete cycle');
  }
}

export async function getCycleMonthSummary(year: number, month: number): Promise<CycleMonthSummary> {
  const response = await api.get<unknown>(`/cycles/month?year=${year}&month=${month}`);
  if (!response.success || response.data == null) {
    throw new Error(response.error?.message || 'Failed to load cycle month summary');
  }

  const root = isRecord(response.data) ? response.data : {};
  const totals = isRecord(root.totals) ? root.totals : {};
  const days = normalizeMonthDays(root.days ?? root.entries ?? []);
  const totalEntries = asNumber(
    totals.totalEntries ?? totals.entries ?? root.totalEntries ?? root.entryCount,
    days.reduce((sum, day) => sum + day.count, 0),
  );
  const activeCycles = asNumber(
    totals.activeCycles ?? root.activeCycles ?? root.activeCycleCount,
  );

  return {
    year,
    month,
    days,
    totalEntries,
    activeCycles,
  };
}

export async function getMedicationYearGraph(year: number): Promise<MedicationYearGraphResponse> {
  const response = await api.get<unknown>(`/medications/graph/year?year=${year}`);
  if (!response.success || response.data == null) {
    throw new Error(response.error?.message || 'Failed to load medication year graph');
  }

  const root = isRecord(response.data) ? response.data : {};
  const axis = isRecord(root.axis) ? root.axis : {};
  const xAxis = isRecord(axis.x) ? axis.x : {};
  const yAxis = isRecord(axis.yMg) ? axis.yMg : {};
  const series = isRecord(root.series) ? root.series : {};
  const totals = isRecord(root.totalsMg) ? root.totalsMg : {};

  return {
    year: asNumber(root.year, year),
    axis: {
      x: {
        startDay: asNumber(xAxis.startDay, 1),
        endDay: asNumber(xAxis.endDay, 365),
      },
      yMg: {
        min: asNumber(yAxis.min, 0),
        max: asNumber(yAxis.max, 20),
      },
    },
    series: {
      steroidMgByDay: asNumberArray(series.steroidMgByDay),
      peptideMgByDay: asNumberArray(series.peptideMgByDay),
      oralMedicationMgByDay: asNumberArray(series.oralMedicationMgByDay),
    },
    totalsMg: {
      steroid: asNumber(totals.steroid),
      peptide: asNumber(totals.peptide),
      oralMedication: asNumber(totals.oralMedication),
      all: asNumber(totals.all),
    },
  };
}

export async function getMedicationDoses(
  options: MedicationDoseQueryOptions = {},
): Promise<MedicationDose[]> {
  const query = new URLSearchParams();

  if (options.category) query.set('category', options.category);
  if (options.from) query.set('from', options.from);
  if (options.to) query.set('to', options.to);
  if (typeof options.page === 'number') query.set('page', String(options.page));
  if (typeof options.limit === 'number') query.set('limit', String(options.limit));

  const suffix = query.size > 0 ? `?${query.toString()}` : '';
  const response = await api.get<unknown>(`/medications/doses${suffix}`);
  if (!response.success || response.data == null) {
    throw new Error(response.error?.message || 'Failed to load medication doses');
  }
  return normalizeMedicationDoseCollection(response.data);
}

export async function createMedicationDose(input: CreateMedicationDoseInput): Promise<MedicationDose> {
  const response = await api.post<unknown>('/medications/doses', {
    ...input,
    cycleId: input.cycleId ?? null,
    notes: input.notes ?? null,
    source: input.source ?? 'web',
  });
  const dose = normalizeMedicationDosePayload(response.data);
  if (!response.success || !dose) {
    throw new Error(response.error?.message || 'Failed to create medication dose');
  }
  return dose;
}

export async function updateMedicationDose(
  id: string,
  input: UpdateMedicationDoseInput,
): Promise<MedicationDose> {
  const response = await api.patch<unknown>(`/medications/doses/${id}`, input);
  const dose = normalizeMedicationDosePayload(response.data);
  if (!response.success || !dose) {
    throw new Error(response.error?.message || 'Failed to update medication dose');
  }
  return dose;
}

export async function deleteMedicationDose(id: string): Promise<void> {
  const response = await api.delete<unknown>(`/medications/doses/${id}`);
  if (!response.success) {
    throw new Error(response.error?.message || 'Failed to delete medication dose');
  }
}

// ─── Health Dashboard ─────────────────────────────────────────────────────────

export interface HealthDashboardResponse {
  heartRate: {
    latest: { bpm: number; recordedAt: string; source: string } | null;
    today: {
      sampleCount: number;
      minBPM: number;
      maxBPM: number;
      avgBPM: number;
      zoneDistribution: {
        rest: number;
        light: number;
        fatBurn: number;
        cardio: number;
        peak: number;
      };
    } | null;
  };
  sessions: {
    today: Array<{
      _id: string;
      gymName: string;
      startedAt: string;
      endedAt: string | null;
      durationMinutes: number | null;
      heartRateSummary: unknown;
    }>;
    activeSession: { _id: string; gymName: string; startedAt: string } | null;
  };
  devices: Array<{
    _id: string;
    name: string;
    nickname: string | null;
    type: string;
    status: string;
    isFavorite: boolean;
    lastSeenAt: string | null;
    healthCapable: boolean;
  }>;
  sources: Array<{
    name: string;
    type: string;
    lastDataAt: string | null;
    sampleCountToday: number;
  }>;
}

export interface HealthTrendsResponse {
  days: number;
  since: string;
  heartRateScatter: Array<{ date: string; bpm: number; zone: string }>;
  restingHeartRate: Array<{ date: string; value: number }>;
  weightTrend: Array<{ date: string; value: number; unit: string }>;
  caloriesTrend: Array<{ date: string; value: number }>;
  workoutTrend: Array<{ date: string; count: number; durationMinutes: number }>;
}

export async function getHealthTrends(days: number = 30): Promise<HealthTrendsResponse> {
  const response = await api.get<HealthTrendsResponse>(`/health/trends?days=${days}`);
  if (!response.success || !response.data) {
    throw new Error(response.error?.message || 'Failed to load health trends');
  }
  return response.data;
}

// ─── Notification Preferences ─────────────────────────────────────────────

export interface NotificationPreferences {
  pushEnabled: boolean;
  panicAlertsEnabled: boolean;
  disconnectAlertsEnabled: boolean;
  custom: Record<string, string>;
}

export interface NotificationPreferencesResponse {
  permissionsState: Record<string, string>;
  preferences: NotificationPreferences;
}

export async function getNotificationPreferences(): Promise<NotificationPreferencesResponse> {
  const response = await api.get<NotificationPreferencesResponse>('/notifications/preferences');
  if (!response.success || !response.data) {
    throw new Error(response.error?.message || 'Failed to load notification preferences');
  }
  return response.data;
}

export async function updateNotificationPreferences(prefs: Partial<NotificationPreferences>): Promise<NotificationPreferencesResponse> {
  const response = await api.patch<NotificationPreferencesResponse>('/notifications/preferences', prefs);
  if (!response.success || !response.data) {
    throw new Error(response.error?.message || 'Failed to update notification preferences');
  }
  return response.data;
}

// ─── Device Detail ────────────────────────────────────────────────────────

export interface DeviceDetail {
  _id: string;
  name: string;
  nickname: string | null;
  type: string;
  bluetoothIdentifier: string;
  status: string;
  isFavorite: boolean;
  isMonitoring: boolean;
  firmwareVersion: string | null;
  signalStrength: number | null;
  lastSeenAt: string | null;
  sharedWith: string[];
  createdAt: string;
}

export interface DeviceEvent {
  action: string;
  occurredAt: string;
  source: string;
  signalStrength: number | null;
}

export async function getDeviceDetail(id: string): Promise<DeviceDetail> {
  const response = await api.get<DeviceDetail>(`/devices/${id}`);
  if (!response.success || !response.data) {
    throw new Error(response.error?.message || 'Failed to load device');
  }
  return response.data;
}

export async function updateDevice(id: string, body: { nickname?: string; isFavorite?: boolean }): Promise<DeviceDetail> {
  const response = await api.patch<DeviceDetail>(`/devices/${id}`, body);
  if (!response.success || !response.data) {
    throw new Error(response.error?.message || 'Failed to update device');
  }
  return response.data;
}

export async function deleteDevice(id: string): Promise<void> {
  const response = await api.delete<unknown>(`/devices/${id}`);
  if (!response.success) {
    throw new Error(response.error?.message || 'Failed to delete device');
  }
}

export async function getDeviceEvents(id: string): Promise<DeviceEvent[]> {
  const response = await api.get<DeviceEvent[]>(`/devices/${id}/events`);
  if (!response.success || !response.data) {
    throw new Error(response.error?.message || 'Failed to load device events');
  }
  return response.data;
}

export interface DeviceShareEntry {
  _id: string;
  email: string;
  displayName: string | null;
  canReceiveAlerts: boolean;
  createdAt: string;
}

export async function getDeviceShares(id: string): Promise<DeviceShareEntry[]> {
  const response = await api.get<DeviceShareEntry[]>(`/devices/${id}/shares`);
  if (!response.success || !response.data) {
    throw new Error(response.error?.message || 'Failed to load shares');
  }
  return response.data;
}

export async function shareDevice(id: string, email: string): Promise<DeviceShareEntry> {
  const response = await api.post<DeviceShareEntry>(`/devices/${id}/shares`, { email });
  if (!response.success || !response.data) {
    throw new Error(response.error?.message || 'Failed to share device');
  }
  return response.data;
}

export async function removeDeviceShare(deviceId: string, shareId: string): Promise<void> {
  const response = await api.delete<unknown>(`/devices/${deviceId}/shares/${shareId}`);
  if (!response.success) {
    throw new Error(response.error?.message || 'Failed to remove share');
  }
}

export async function updateDeviceStatus(id: string, status: string): Promise<void> {
  const response = await api.patch<unknown>(`/devices/${id}/status`, { status });
  if (!response.success) {
    throw new Error(response.error?.message || 'Failed to update device status');
  }
}

// ─── Run Creation ─────────────────────────────────────────────────────────

export interface CreateRunInput {
  startedAt: string;
  notes?: string;
}

export interface CompleteRunInput {
  endedAt: string;
  distanceMeters?: number;
  durationSeconds?: number;
  notes?: string;
}

export interface RunDetail {
  _id: string;
  startedAt: string;
  endedAt: string | null;
  status: string;
  distanceMeters: number;
  durationSeconds: number;
  averagePaceSecondsPerKm: number | null;
  notes: string | null;
  source: string;
}

export async function createRun(input: CreateRunInput): Promise<RunDetail> {
  const response = await api.post<RunDetail>('/runs', input);
  if (!response.success || !response.data) {
    throw new Error(response.error?.message || 'Failed to create run');
  }
  return response.data;
}

export async function completeRun(id: string, input: CompleteRunInput): Promise<RunDetail> {
  const response = await api.post<RunDetail>(`/runs/${id}/complete`, input);
  if (!response.success || !response.data) {
    throw new Error(response.error?.message || 'Failed to complete run');
  }
  return response.data;
}

// ─── Emergency Contacts ───────────────────────────────────────────────────

export interface EmergencyContact {
  _id: string;
  name: string;
  phone: string;
  email: string | null;
  notifyOnPanic: boolean;
  notifyOnDisconnect: boolean;
  createdAt: string;
}

export async function getEmergencyContacts(): Promise<EmergencyContact[]> {
  const response = await api.get<EmergencyContact[]>('/emergency-contacts');
  if (!response.success || !response.data) throw new Error(response.error?.message || 'Failed to load emergency contacts');
  return response.data;
}

export async function createEmergencyContact(body: { name: string; phone: string; email?: string; notifyOnPanic?: boolean; notifyOnDisconnect?: boolean }): Promise<EmergencyContact> {
  const response = await api.post<EmergencyContact>('/emergency-contacts', body);
  if (!response.success || !response.data) throw new Error(response.error?.message || 'Failed to create contact');
  return response.data;
}

export async function deleteEmergencyContact(id: string): Promise<void> {
  const response = await api.delete<unknown>(`/emergency-contacts/${id}`);
  if (!response.success) throw new Error(response.error?.message || 'Failed to delete contact');
}

// ─── Health Dashboard ─────────────────────────────────────────────────────

export async function getHealthDashboard(): Promise<HealthDashboardResponse> {
  const response = await api.get<HealthDashboardResponse>('/health/dashboard');
  if (!response.success || !response.data) {
    throw new Error(response.error?.message || 'Failed to load health dashboard');
  }
  return response.data;
}
