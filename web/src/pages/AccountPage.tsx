import { useQuery, useQueryClient } from '@tanstack/react-query';
import { useCallback, useRef, useState, type ChangeEvent } from 'react';
import { useNavigate } from 'react-router-dom';
import { toast } from 'sonner';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Separator } from '@/components/ui/separator';
import { Avatar, AvatarImage, AvatarFallback } from '@/components/ui/avatar';
import HeatmapCalendar from '@/components/account/HeatmapCalendar';
import Header from '@/components/layout/Header';
import Footer from '@/components/layout/Footer';
import { api } from '@/lib/api';
import { useAuth } from '@/lib/auth';

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

interface UserProfile {
  _id: string;
  displayName: string;
  email: string;
  avatarURL?: string | null;
  role: string;
  status: string;
  linkedAccounts: string[];
  subscriptionTier: 'annual' | 'free';
  subscription?: {
    status: 'active' | 'expired' | 'grace_period' | 'cancelled';
    plan?: string | null;
    expiresAt?: string | null;
  } | null;
  devices?: Array<{
    _id: string;
    deviceName: string;
    platform: string;
    lastSeen?: string | null;
  }>;
  referralCode?: string | null;
  orderCount?: number;
}

interface Order {
  _id: string;
  orderNumber: string;
  status: string;
  total: number;
  createdAt: string;
  items: Array<{
    name: string;
    quantity: number;
    price: number;
  }>;
}

interface CalendarDay {
  date: string;
  count: number;
}

interface CalendarDaySummary {
  gymVisits: number;
  gymMinutes: number;
  mealsLogged: number;
  totalCalories: number;
  purchasesMade: number;
  waterIntakeMl: number;
  workoutsCompleted: number;
}

interface CalendarMonthResponse {
  days: Record<string, CalendarDaySummary>;
}

// ---------------------------------------------------------------------------
// Data hooks
// ---------------------------------------------------------------------------

function useProfile(enabled: boolean) {
  return useQuery<UserProfile>({
    queryKey: ['me'],
    queryFn: async () => {
      const res = await api.get<UserProfile>('/users/me');
      if (!res.success || !res.data) throw new Error(res.error?.message ?? 'Failed to fetch profile');
      return res.data;
    },
    enabled,
    retry: false,
  });
}

function useOrders(enabled: boolean) {
  return useQuery<Order[]>({
    queryKey: ['orders'],
    queryFn: async () => {
      const res = await api.get<Order[]>('/store/orders');
      if (!res.success || !res.data) throw new Error(res.error?.message ?? 'Failed to fetch orders');
      return res.data;
    },
    enabled,
    retry: false,
  });
}

function useCalendarMonth(year: number, month: number, enabled: boolean) {
  return useQuery<CalendarDay[]>({
    queryKey: ['calendar', year, month],
    queryFn: async () => {
      const res = await api.get<CalendarMonthResponse>(`/calendar/month?year=${year}&month=${month}`);
      if (!res.success || !res.data?.days) return [];

      return Object.entries(res.data.days)
        .sort(([leftDate], [rightDate]) => leftDate.localeCompare(rightDate))
        .map(([date, summary]) => ({
          date,
          count:
            summary.gymVisits
            + summary.mealsLogged
            + summary.purchasesMade
            + summary.workoutsCompleted
            + (summary.waterIntakeMl > 0 ? 1 : 0),
        }));
    },
    enabled,
    retry: false,
  });
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function initials(name: string): string {
  return name
    .split(' ')
    .map((p) => p[0])
    .join('')
    .toUpperCase()
    .slice(0, 2);
}

function formatDate(iso: string): string {
  return new Date(iso).toLocaleDateString('en-US', {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
  });
}

function formatCurrency(cents: number): string {
  return `$${(cents / 100).toFixed(2)}`;
}

function downloadJson(filename: string, payload: unknown) {
  const json = JSON.stringify(payload, null, 2);
  const blob = new Blob([json], { type: 'application/json' });
  const url = URL.createObjectURL(blob);
  const anchor = document.createElement('a');

  anchor.href = url;
  anchor.download = filename;
  anchor.click();

  URL.revokeObjectURL(url);
}

async function createAvatarDataUrl(file: File): Promise<string> {
  if (!file.type.startsWith('image/')) {
    throw new Error('Choose a JPG, PNG, or WebP image.');
  }

  const objectUrl = URL.createObjectURL(file);

  try {
    const image = await new Promise<HTMLImageElement>((resolve, reject) => {
      const nextImage = new Image();
      nextImage.onload = () => resolve(nextImage);
      nextImage.onerror = () => reject(new Error('Failed to read the selected image.'));
      nextImage.src = objectUrl;
    });

    const maxDimension = 512;
    const scale = Math.min(1, maxDimension / Math.max(image.naturalWidth, image.naturalHeight));
    const width = Math.max(1, Math.round(image.naturalWidth * scale));
    const height = Math.max(1, Math.round(image.naturalHeight * scale));

    const canvas = document.createElement('canvas');
    canvas.width = width;
    canvas.height = height;

    const context = canvas.getContext('2d');
    if (!context) {
      throw new Error('Failed to prepare the selected image.');
    }

    context.drawImage(image, 0, 0, width, height);

    const dataUrl = canvas.toDataURL('image/jpeg', 0.82);
    if (dataUrl.length > 2_000_000) {
      throw new Error('That image is still too large. Try a smaller photo.');
    }

    return dataUrl;
  } finally {
    URL.revokeObjectURL(objectUrl);
  }
}

// ---------------------------------------------------------------------------
// Sub-components
// ---------------------------------------------------------------------------

function ProfileTab({
  user,
  isExporting,
  isSavingAvatar,
  onExport,
  onPickAvatar,
  onRemoveAvatar,
}: {
  user: UserProfile;
  isExporting: boolean;
  isSavingAvatar: boolean;
  onExport: () => void;
  onPickAvatar: () => void;
  onRemoveAvatar: () => void;
}) {
  const subStatus =
    user.subscription?.status ?? (user.subscriptionTier === 'annual' ? 'active' : 'cancelled');
  const isSubscribed = subStatus === 'active' || subStatus === 'grace_period';

  return (
    <div className="space-y-6">
      <Card className="border-zinc-800 bg-zinc-900/50">
        <CardContent className="flex items-center gap-5 pt-6">
          <Avatar size="lg" className="h-16 w-16">
            {user.avatarURL ? (
              <AvatarImage src={user.avatarURL} alt={user.displayName} />
            ) : null}
            <AvatarFallback className="bg-zinc-800 text-lg text-zinc-300">
              {initials(user.displayName)}
            </AvatarFallback>
          </Avatar>

          <div className="min-w-0 flex-1">
            <h2 className="truncate text-xl font-semibold text-white">{user.displayName}</h2>
            <p className="truncate text-sm text-zinc-400">{user.email}</p>
            <div className="mt-2 flex flex-wrap gap-2">
              {user.linkedAccounts.map((provider) => (
                <Badge key={provider} variant="outline" className="border-zinc-700 text-zinc-400 text-xs capitalize">
                  {provider}
                </Badge>
              ))}
              <Badge
                variant="outline"
                className={
                  isSubscribed
                    ? 'border-emerald-700 text-emerald-400'
                    : 'border-zinc-700 text-zinc-500'
                }
                >
                  {isSubscribed ? 'Subscribed' : 'Free'}
                </Badge>
            </div>
            <div className="mt-3 flex flex-wrap gap-2">
              <Button
                size="sm"
                variant="outline"
                className="border-zinc-700 text-zinc-200 hover:text-white"
                onClick={onPickAvatar}
                disabled={isSavingAvatar}
              >
                {isSavingAvatar ? 'Updating photo...' : 'Change Photo'}
              </Button>
              {user.avatarURL ? (
                <Button
                  size="sm"
                  variant="ghost"
                  className="text-zinc-400 hover:text-white"
                  onClick={onRemoveAvatar}
                  disabled={isSavingAvatar}
                >
                  Remove Photo
                </Button>
              ) : null}
            </div>
          </div>
        </CardContent>
      </Card>

      <Card className="border-zinc-800 bg-zinc-900/50">
        <CardHeader>
          <CardTitle className="flex items-center gap-3">
            Subscription
            <Badge
              variant="outline"
              className={
                isSubscribed
                  ? 'border-emerald-700 text-emerald-400'
                  : 'border-zinc-600 text-zinc-400'
              }
            >
              {isSubscribed ? 'Active' : 'Inactive'}
            </Badge>
          </CardTitle>
        </CardHeader>
        <CardContent>
          {isSubscribed ? (
            <div className="space-y-4">
              {user.subscription?.plan && (
                <p className="text-sm text-zinc-300">
                  Plan: <span className="font-medium text-white">{user.subscription.plan}</span>
                </p>
              )}
              {user.subscription?.expiresAt && (
                <p className="text-sm text-zinc-400">
                  Renews: {formatDate(user.subscription.expiresAt)}
                </p>
              )}
              <div className="flex flex-wrap gap-3">
                <Button
                  className="bg-emerald-500 font-semibold text-black hover:bg-emerald-400"
                  onClick={() => window.open('https://apps.apple.com/account/subscriptions', '_blank', 'noopener,noreferrer')}
                >
                  Manage in App Store
                </Button>
                <Button
                  variant="outline"
                  className="border-zinc-700 text-zinc-200 hover:text-white"
                  onClick={() => window.location.assign('/runs')}
                >
                  Open Run Replay
                </Button>
                <Button
                  variant="ghost"
                  className="text-zinc-400 hover:text-white"
                  onClick={() => window.location.assign('/support')}
                >
                  Billing Help
                </Button>
              </div>
            </div>
          ) : (
            <div className="space-y-4">
              <p className="mb-4 text-zinc-400">
                Subscribe through the iOS app to unlock unlimited device monitoring,
                gym geofencing, and health tracking.
              </p>
              <div className="rounded-lg border border-zinc-800 bg-zinc-950 p-4">
                <div className="flex items-center justify-between">
                  <div>
                    <p className="font-semibold text-white">GearSnitch Annual</p>
                    <p className="text-sm text-zinc-400">365-day subscription</p>
                  </div>
                  <p className="text-xl font-bold text-white">$29.99/yr</p>
                </div>
              </div>
              <div className="flex flex-wrap gap-3">
                <Button
                  className="bg-gradient-to-r from-cyan-500 to-emerald-500 font-semibold text-black hover:from-cyan-400 hover:to-emerald-400"
                  onClick={() => window.location.assign('/#download')}
                >
                  Download the iPhone App
                </Button>
                <Button
                  variant="outline"
                  className="border-zinc-700 text-zinc-200 hover:text-white"
                  onClick={() => window.location.assign('/support')}
                >
                  See Subscription Help
                </Button>
              </div>
            </div>
          )}
        </CardContent>
      </Card>

      <Card className="border-zinc-800 bg-zinc-900/50">
        <CardHeader>
          <CardTitle>Data Export</CardTitle>
        </CardHeader>
        <CardContent className="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
          <p className="max-w-2xl text-sm text-zinc-400">
            Download a JSON export of your account profile, subscription, devices, sessions,
            referrals, and order history.
          </p>
          <Button
            variant="outline"
            className="border-zinc-700 text-zinc-200 hover:text-white"
            onClick={onExport}
            disabled={isExporting}
          >
            {isExporting ? 'Preparing export...' : 'Export My Data'}
          </Button>
        </CardContent>
      </Card>

      <Card className="border-zinc-800 bg-zinc-900/50">
        <CardHeader>
          <CardTitle>My Devices</CardTitle>
        </CardHeader>
        <CardContent>
          {user.devices && user.devices.length > 0 ? (
            <ul className="space-y-3">
              {user.devices.map((device) => (
                <li key={device._id} className="flex items-center justify-between rounded-lg border border-zinc-800 bg-zinc-950 px-4 py-3">
                  <div>
                    <p className="text-sm font-medium text-white">{device.deviceName}</p>
                    <p className="text-xs text-zinc-500 capitalize">{device.platform}</p>
                  </div>
                  {device.lastSeen && (
                    <span className="text-xs text-zinc-500">
                      Last seen {formatDate(device.lastSeen)}
                    </span>
                  )}
                </li>
              ))}
            </ul>
          ) : (
            <p className="text-zinc-400">
              Pair and manage your Bluetooth devices from the iOS app. Device status will appear here once connected.
            </p>
          )}
        </CardContent>
      </Card>

      {user.referralCode && (
        <Card className="border-zinc-800 bg-zinc-900/50">
          <CardHeader>
            <CardTitle>Referral Code</CardTitle>
          </CardHeader>
          <CardContent className="space-y-3">
            <p className="text-sm text-zinc-400">
              Share your code and earn 90 days free for every friend who subscribes.
            </p>
            <div className="flex items-center justify-between rounded-lg border border-zinc-800 bg-zinc-950 px-4 py-3">
              <code className="font-mono text-lg text-emerald-400">{user.referralCode}</code>
              <Button
                variant="outline"
                size="sm"
                className="border-zinc-700"
                onClick={() => navigator.clipboard.writeText(user.referralCode!)}
              >
                Copy
              </Button>
            </div>
          </CardContent>
        </Card>
      )}
    </div>
  );
}

function PurchasesTab() {
  const { isAuthenticated } = useAuth();
  const { data: orders, isLoading, error } = useOrders(isAuthenticated);

  if (isLoading) {
    return (
      <Card className="border-zinc-800 bg-zinc-900/50">
        <CardContent className="py-12 text-center text-zinc-500">Loading orders...</CardContent>
      </Card>
    );
  }

  if (error || !orders || orders.length === 0) {
    return (
      <Card className="border-zinc-800 bg-zinc-900/50">
        <CardHeader>
          <CardTitle>Purchase History</CardTitle>
        </CardHeader>
        <CardContent>
          <p className="text-zinc-400">No purchases yet. Visit the store to browse GearSnitch products.</p>
        </CardContent>
      </Card>
    );
  }

  return (
    <Card className="border-zinc-800 bg-zinc-900/50">
      <CardHeader>
        <CardTitle>Purchase History</CardTitle>
      </CardHeader>
      <CardContent className="space-y-4">
        {orders.map((order) => (
          <div key={order._id} className="rounded-lg border border-zinc-800 bg-zinc-950 p-4">
            <div className="flex items-start justify-between">
              <div>
                <p className="text-sm font-medium text-white">Order #{order.orderNumber}</p>
                <p className="text-xs text-zinc-500">{formatDate(order.createdAt)}</p>
              </div>
              <div className="text-right">
                <Badge
                  variant="outline"
                  className={
                    order.status === 'delivered'
                      ? 'border-emerald-700 text-emerald-400'
                      : order.status === 'shipped'
                        ? 'border-cyan-700 text-cyan-400'
                        : 'border-zinc-700 text-zinc-400'
                  }
                >
                  {order.status}
                </Badge>
                <p className="mt-1 text-sm font-semibold text-white">{formatCurrency(order.total)}</p>
              </div>
            </div>

            {order.items.length > 0 && (
              <>
                <Separator className="my-3 bg-zinc-800" />
                <ul className="space-y-1">
                  {order.items.map((item, index) => (
                    <li key={index} className="flex justify-between text-sm">
                      <span className="text-zinc-400">
                        {item.name} <span className="text-zinc-600">x{item.quantity}</span>
                      </span>
                      <span className="text-zinc-300">{formatCurrency(item.price * item.quantity)}</span>
                    </li>
                  ))}
                </ul>
              </>
            )}
          </div>
        ))}
      </CardContent>
    </Card>
  );
}

function CalendarTab() {
  const { isAuthenticated } = useAuth();
  const now = new Date();
  const [year] = useState(now.getFullYear());
  const [month] = useState(now.getMonth() + 1);
  const { data: days, isLoading } = useCalendarMonth(year, month, isAuthenticated);

  return (
    <Card className="border-zinc-800 bg-zinc-900/50">
      <CardHeader>
        <CardTitle>Activity Calendar</CardTitle>
      </CardHeader>
      <CardContent>
        {isLoading ? (
          <p className="text-zinc-500">Loading calendar...</p>
        ) : (
          <div className="max-w-xs">
            <HeatmapCalendar data={days ?? []} year={year} month={month} />
          </div>
        )}
      </CardContent>
    </Card>
  );
}

// ---------------------------------------------------------------------------
// Main page
// ---------------------------------------------------------------------------

export default function AccountPage() {
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const { isAuthenticated, signOut } = useAuth();
  const { data: user, isLoading, error } = useProfile(isAuthenticated);
  const avatarInputRef = useRef<HTMLInputElement | null>(null);
  const [signingOut, setSigningOut] = useState(false);
  const [exporting, setExporting] = useState(false);
  const [savingAvatar, setSavingAvatar] = useState(false);

  const handleSignOut = useCallback(async () => {
    setSigningOut(true);
    await signOut();
    setSigningOut(false);
    navigate('/', { replace: true });
  }, [navigate, signOut]);

  const handleExport = useCallback(async () => {
    setExporting(true);

    try {
      const res = await api.post<Record<string, unknown>>('/users/me/export', {});
      if (!res.success || !res.data) {
        throw new Error(res.error?.message ?? 'Failed to export account data');
      }

      const exportedAt =
        typeof res.data.exportedAt === 'string' ? res.data.exportedAt : new Date().toISOString();
      const safeStamp = exportedAt.replace(/[:.]/g, '-');
      downloadJson(`gearsnitch-data-export-${safeStamp}.json`, res.data);
      toast.success('Your data export was downloaded.');
    } catch (err) {
      toast.error(err instanceof Error ? err.message : 'Failed to export account data');
    } finally {
      setExporting(false);
    }
  }, []);

  const handleAvatarSelection = useCallback(
    async (event: ChangeEvent<HTMLInputElement>) => {
      const file = event.target.files?.[0];
      event.target.value = '';

      if (!file) {
        return;
      }

      setSavingAvatar(true);

      try {
        const avatarURL = await createAvatarDataUrl(file);
        const res = await api.patch<UserProfile>('/users/me/avatar', { avatarURL });
        if (!res.success || !res.data) {
          throw new Error(res.error?.message ?? 'Failed to update your profile photo.');
        }

        queryClient.setQueryData<UserProfile>(['me'], res.data);
        toast.success('Profile photo updated.');
      } catch (err) {
        toast.error(
          err instanceof Error ? err.message : 'Failed to update your profile photo.',
        );
      } finally {
        setSavingAvatar(false);
      }
    },
    [queryClient],
  );

  const handleRemoveAvatar = useCallback(async () => {
    setSavingAvatar(true);

    try {
      const res = await api.patch<UserProfile>('/users/me/avatar', { avatarURL: null });
      if (!res.success || !res.data) {
        throw new Error(res.error?.message ?? 'Failed to remove your profile photo.');
      }

      queryClient.setQueryData<UserProfile>(['me'], res.data);
      toast.success('Profile photo removed.');
    } catch (err) {
      toast.error(
        err instanceof Error ? err.message : 'Failed to remove your profile photo.',
      );
    } finally {
      setSavingAvatar(false);
    }
  }, [queryClient]);

  return (
    <div className="min-h-screen bg-zinc-950 text-zinc-100">
      <Header />
      <input
        ref={avatarInputRef}
        type="file"
        accept="image/jpeg,image/png,image/webp"
        className="hidden"
        onChange={handleAvatarSelection}
      />

      <section className="px-6 py-16 pt-24 lg:px-8">
        <div className="mx-auto max-w-4xl">
          <div className="mb-8 flex items-center justify-between">
            <h1 className="text-3xl font-bold tracking-tight">My Account</h1>
            {isAuthenticated && (
              <Button
                variant="outline"
                className="border-zinc-700 text-zinc-400 hover:text-white"
                onClick={handleSignOut}
                disabled={signingOut}
              >
                {signingOut ? 'Signing out...' : 'Sign Out'}
              </Button>
            )}
          </div>

          {isLoading && (
            <Card className="border-zinc-800 bg-zinc-900/50">
              <CardContent className="py-12 text-center text-zinc-500">
                Loading your profile...
              </CardContent>
            </Card>
          )}

          {!isLoading && error && (
            <Card className="border-zinc-800 bg-zinc-900/50">
              <CardHeader>
                <CardTitle>Account Unavailable</CardTitle>
              </CardHeader>
              <CardContent className="space-y-3 text-zinc-400">
                <p>{error instanceof Error ? error.message : 'Failed to load your account.'}</p>
                <p className="text-sm text-zinc-500">
                  Try refreshing the page. If the problem persists, sign out and start a new browser session.
                </p>
              </CardContent>
            </Card>
          )}

          {!isLoading && !error && user && (
            <Tabs defaultValue="profile" className="w-full">
              <TabsList className="border border-zinc-800 bg-zinc-900">
                <TabsTrigger value="profile">Profile</TabsTrigger>
                <TabsTrigger value="purchases">Purchases</TabsTrigger>
                <TabsTrigger value="calendar">Calendar</TabsTrigger>
              </TabsList>

              <TabsContent value="profile" className="mt-6">
                <ProfileTab
                  user={user}
                  isExporting={exporting}
                  isSavingAvatar={savingAvatar}
                  onExport={handleExport}
                  onPickAvatar={() => avatarInputRef.current?.click()}
                  onRemoveAvatar={handleRemoveAvatar}
                />
              </TabsContent>

              <TabsContent value="purchases" className="mt-6">
                <PurchasesTab />
              </TabsContent>

              <TabsContent value="calendar" className="mt-6">
                <CalendarTab />
              </TabsContent>
            </Tabs>
          )}
        </div>
      </section>

      <Footer />
    </div>
  );
}
