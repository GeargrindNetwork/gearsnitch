import { useQuery, useQueryClient } from '@tanstack/react-query';
import { useCallback, useState } from 'react';
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

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

interface UserProfile {
  _id: string;
  displayName: string;
  email: string;
  photoUrl?: string;
  roles: string[];
  status: string;
  authProviders: string[];
  subscription?: {
    status: 'active' | 'expired' | 'trial' | 'none';
    plan?: string;
    expiresAt?: string;
  };
  devices?: Array<{
    _id: string;
    deviceName: string;
    platform: string;
    lastSeen?: string;
  }>;
  referralCode?: string;
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

// ---------------------------------------------------------------------------
// Data hooks
// ---------------------------------------------------------------------------

function useProfile() {
  return useQuery<UserProfile>({
    queryKey: ['me'],
    queryFn: async () => {
      const res = await api.get<UserProfile>('/auth/me');
      if (!res.success || !res.data) throw new Error(res.error?.message ?? 'Failed to fetch profile');
      return res.data;
    },
    retry: false,
  });
}

function useOrders() {
  return useQuery<Order[]>({
    queryKey: ['orders'],
    queryFn: async () => {
      const res = await api.get<Order[]>('/store/orders');
      if (!res.success || !res.data) throw new Error(res.error?.message ?? 'Failed to fetch orders');
      return res.data;
    },
    retry: false,
  });
}

function useCalendarMonth(year: number, month: number) {
  return useQuery<CalendarDay[]>({
    queryKey: ['calendar', year, month],
    queryFn: async () => {
      const res = await api.get<CalendarDay[]>(`/calendar/month?year=${year}&month=${month}`);
      if (!res.success || !res.data) return [];
      return res.data;
    },
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

// ---------------------------------------------------------------------------
// Sub-components
// ---------------------------------------------------------------------------

function SignedOutState() {
  return (
    <Card className="border-zinc-800 bg-zinc-900/50">
      <CardHeader>
        <CardTitle>Profile</CardTitle>
      </CardHeader>
      <CardContent className="space-y-4">
        <p className="text-zinc-400">Sign in through the iOS app to view and manage your account here.</p>
        <p className="text-sm text-zinc-500">
          Once signed in, your session will be shared with the web dashboard.
        </p>
      </CardContent>
    </Card>
  );
}

function ProfileTab({ user }: { user: UserProfile }) {
  const subStatus = user.subscription?.status ?? 'none';

  return (
    <div className="space-y-6">
      {/* Profile header */}
      <Card className="border-zinc-800 bg-zinc-900/50">
        <CardContent className="flex items-center gap-5 pt-6">
          <Avatar size="lg" className="h-16 w-16">
            {user.photoUrl ? (
              <AvatarImage src={user.photoUrl} alt={user.displayName} />
            ) : null}
            <AvatarFallback className="bg-zinc-800 text-lg text-zinc-300">
              {initials(user.displayName)}
            </AvatarFallback>
          </Avatar>

          <div className="min-w-0 flex-1">
            <h2 className="truncate text-xl font-semibold text-white">{user.displayName}</h2>
            <p className="truncate text-sm text-zinc-400">{user.email}</p>
            <div className="mt-2 flex flex-wrap gap-2">
              {user.authProviders.map((p) => (
                <Badge key={p} variant="outline" className="border-zinc-700 text-zinc-400 text-xs capitalize">
                  {p}
                </Badge>
              ))}
              <Badge
                variant="outline"
                className={
                  subStatus === 'active'
                    ? 'border-emerald-700 text-emerald-400'
                    : 'border-zinc-700 text-zinc-500'
                }
              >
                {subStatus === 'active' ? 'Subscribed' : 'Free'}
              </Badge>
            </div>
          </div>
        </CardContent>
      </Card>

      {/* Subscription */}
      <Card className="border-zinc-800 bg-zinc-900/50">
        <CardHeader>
          <CardTitle className="flex items-center gap-3">
            Subscription
            <Badge
              variant="outline"
              className={
                subStatus === 'active'
                  ? 'border-emerald-700 text-emerald-400'
                  : 'border-zinc-600 text-zinc-400'
              }
            >
              {subStatus === 'active' ? 'Active' : subStatus === 'trial' ? 'Trial' : 'Inactive'}
            </Badge>
          </CardTitle>
        </CardHeader>
        <CardContent>
          {subStatus === 'active' || subStatus === 'trial' ? (
            <div className="space-y-2">
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
            </div>
          ) : (
            <div>
              <p className="text-zinc-400 mb-4">
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
            </div>
          )}
        </CardContent>
      </Card>

      {/* Devices */}
      <Card className="border-zinc-800 bg-zinc-900/50">
        <CardHeader>
          <CardTitle>My Devices</CardTitle>
        </CardHeader>
        <CardContent>
          {user.devices && user.devices.length > 0 ? (
            <ul className="space-y-3">
              {user.devices.map((d) => (
                <li key={d._id} className="flex items-center justify-between rounded-lg border border-zinc-800 bg-zinc-950 px-4 py-3">
                  <div>
                    <p className="text-sm font-medium text-white">{d.deviceName}</p>
                    <p className="text-xs text-zinc-500 capitalize">{d.platform}</p>
                  </div>
                  {d.lastSeen && (
                    <span className="text-xs text-zinc-500">
                      Last seen {formatDate(d.lastSeen)}
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

      {/* Referral */}
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
  const { data: orders, isLoading, error } = useOrders();

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
                  {order.items.map((item, idx) => (
                    <li key={idx} className="flex justify-between text-sm">
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
  const now = new Date();
  const [year] = useState(now.getFullYear());
  const [month] = useState(now.getMonth() + 1);
  const { data: days, isLoading } = useCalendarMonth(year, month);

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
  const queryClient = useQueryClient();
  const { data: user, isLoading, error } = useProfile();
  const [signingOut, setSigningOut] = useState(false);

  const handleSignOut = useCallback(async () => {
    setSigningOut(true);
    try {
      await api.post('/auth/logout');
    } catch {
      // Logout endpoint may 401 if token already expired -- that's fine
    }
    api.setToken(null);
    localStorage.removeItem('token');
    queryClient.clear();
    setSigningOut(false);
    window.location.href = '/';
  }, [queryClient]);

  // Hydrate token from storage on first render
  const token = localStorage.getItem('token');
  if (token) {
    api.setToken(token);
  }

  const isSignedIn = !isLoading && !error && !!user;

  return (
    <div className="min-h-screen bg-zinc-950 text-zinc-100">
      <Header />

      <section className="px-6 py-16 pt-24 lg:px-8">
        <div className="mx-auto max-w-4xl">
          <div className="mb-8 flex items-center justify-between">
            <h1 className="text-3xl font-bold tracking-tight">My Account</h1>
            {isSignedIn && (
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

          {!isLoading && !isSignedIn && <SignedOutState />}

          {isSignedIn && user && (
            <Tabs defaultValue="profile" className="w-full">
              <TabsList className="bg-zinc-900 border border-zinc-800">
                <TabsTrigger value="profile">Profile</TabsTrigger>
                <TabsTrigger value="purchases">Purchases</TabsTrigger>
                <TabsTrigger value="calendar">Calendar</TabsTrigger>
              </TabsList>

              <TabsContent value="profile" className="mt-6">
                <ProfileTab user={user} />
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
