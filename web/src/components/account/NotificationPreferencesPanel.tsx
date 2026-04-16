import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { useState } from 'react';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { getNotificationPreferences, updateNotificationPreferences, type NotificationPreferences } from '@/lib/api';

function Toggle({ label, description, checked, onChange, disabled }: {
  label: string; description: string; checked: boolean; onChange: (v: boolean) => void; disabled?: boolean;
}) {
  return (
    <label className="flex items-center justify-between gap-4 py-3">
      <div>
        <p className="text-sm font-medium text-zinc-200">{label}</p>
        <p className="text-xs text-zinc-500">{description}</p>
      </div>
      <button
        type="button"
        role="switch"
        aria-checked={checked}
        disabled={disabled}
        onClick={() => onChange(!checked)}
        className={`relative inline-flex h-6 w-11 shrink-0 cursor-pointer rounded-full border-2 border-transparent transition-colors duration-200 ${checked ? 'bg-emerald-500' : 'bg-zinc-700'} ${disabled ? 'opacity-50' : ''}`}
      >
        <span className={`pointer-events-none inline-block h-5 w-5 transform rounded-full bg-white shadow transition-transform duration-200 ${checked ? 'translate-x-5' : 'translate-x-0'}`} />
      </button>
    </label>
  );
}

export default function NotificationPreferencesPanel() {
  const queryClient = useQueryClient();
  const { data, isLoading } = useQuery({
    queryKey: ['notification-preferences'],
    queryFn: getNotificationPreferences,
    staleTime: 30_000,
  });

  const [prefs, setPrefs] = useState<NotificationPreferences>({
    pushEnabled: false,
    panicAlertsEnabled: false,
    disconnectAlertsEnabled: false,
    custom: {},
  });
  const [dirty, setDirty] = useState(false);
  const [syncedDataRef, setSyncedDataRef] = useState<NotificationPreferences | null>(null);

  // Sync server state to local state when data changes
  if (data?.preferences && data.preferences !== syncedDataRef) {
    setPrefs(data.preferences);
    setDirty(false);
    setSyncedDataRef(data.preferences);
  }

  const mutation = useMutation({
    mutationFn: (p: Partial<NotificationPreferences>) => updateNotificationPreferences(p),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['notification-preferences'] });
      setDirty(false);
    },
  });

  const update = (key: keyof NotificationPreferences, value: boolean) => {
    setPrefs(prev => ({ ...prev, [key]: value }));
    setDirty(true);
  };

  const updateCustom = (key: string, value: boolean) => {
    setPrefs(prev => ({
      ...prev,
      custom: { ...prev.custom, [key]: value ? 'true' : 'false' },
    }));
    setDirty(true);
  };

  const customBool = (key: string) => prefs.custom[key] === 'true';

  if (isLoading) {
    return (
      <Card className="border-white/5 bg-zinc-900/70">
        <CardContent className="p-6 text-sm text-zinc-400">Loading preferences...</CardContent>
      </Card>
    );
  }

  return (
    <Card className="border-white/5 bg-zinc-900/70">
      <CardHeader className="pb-2">
        <CardTitle className="text-sm font-medium text-zinc-400">Notification Preferences</CardTitle>
      </CardHeader>
      <CardContent className="space-y-4 pb-5">
        <div>
          <h4 className="mb-1 text-xs font-semibold uppercase tracking-wider text-zinc-500">General</h4>
          <Toggle label="Push Notifications" description="Enable all push notifications" checked={prefs.pushEnabled} onChange={v => update('pushEnabled', v)} />
        </div>

        <div className="border-t border-white/5 pt-3">
          <h4 className="mb-1 text-xs font-semibold uppercase tracking-wider text-zinc-500">Device Alerts</h4>
          <Toggle label="Panic Alarm" description="Alert when panic alarm is triggered" checked={prefs.panicAlertsEnabled} onChange={v => update('panicAlertsEnabled', v)} />
          <Toggle label="Disconnect Alerts" description="Alert when a monitored device disconnects" checked={prefs.disconnectAlertsEnabled} onChange={v => update('disconnectAlertsEnabled', v)} />
          <Toggle label="Left Safe Zone" description="Alert when device leaves geofence" checked={customBool('leftSafeZone')} onChange={v => updateCustom('leftSafeZone', v)} />
          <Toggle label="Low Battery" description="Alert when device battery is low" checked={customBool('lowBattery')} onChange={v => updateCustom('lowBattery', v)} />
        </div>

        <div className="border-t border-white/5 pt-3">
          <h4 className="mb-1 text-xs font-semibold uppercase tracking-wider text-zinc-500">Health & Fitness</h4>
          <Toggle label="Workout Reminders" description="Remind you to log workouts" checked={customBool('workoutReminders')} onChange={v => updateCustom('workoutReminders', v)} />
          <Toggle label="Meal Reminders" description="Remind you to log meals" checked={customBool('mealReminders')} onChange={v => updateCustom('mealReminders', v)} />
          <Toggle label="Water Reminders" description="Remind you to drink water" checked={customBool('waterReminders')} onChange={v => updateCustom('waterReminders', v)} />
        </div>

        <div className="border-t border-white/5 pt-3">
          <h4 className="mb-1 text-xs font-semibold uppercase tracking-wider text-zinc-500">Marketing</h4>
          <Toggle label="Promotions & Offers" description="Receive promotional notifications" checked={customBool('promotions')} onChange={v => updateCustom('promotions', v)} />
        </div>

        {dirty && (
          <Button
            className="mt-2 w-full bg-emerald-600 text-white hover:bg-emerald-700"
            onClick={() => mutation.mutate(prefs)}
            disabled={mutation.isPending}
          >
            {mutation.isPending ? 'Saving...' : 'Save Preferences'}
          </Button>
        )}

        {mutation.isError && (
          <p className="text-xs text-red-400">{(mutation.error as Error).message}</p>
        )}
      </CardContent>
    </Card>
  );
}
