import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { useState } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import Header from '@/components/layout/Header';
import Footer from '@/components/layout/Footer';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import {
  Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter,
} from '@/components/ui/dialog';
import { getDeviceDetail, getDeviceEvents, getDeviceShares, shareDevice, removeDeviceShare, updateDevice, deleteDevice, updateDeviceStatus } from '@/lib/api';

function statusColor(status: string) {
  switch (status) {
    case 'connected': case 'monitoring': case 'reconnected': case 'active':
      return 'border-emerald-400/30 bg-emerald-400/10 text-emerald-300';
    case 'lost':
      return 'border-red-400/30 bg-red-400/10 text-red-300';
    case 'disconnected': case 'inactive':
      return 'border-amber-400/30 bg-amber-400/10 text-amber-300';
    default:
      return 'border-zinc-400/30 bg-zinc-400/10 text-zinc-300';
  }
}

function formatDate(iso: string | null) {
  if (!iso) return 'Never';
  return new Intl.DateTimeFormat('en-US', { month: 'short', day: 'numeric', year: 'numeric', hour: 'numeric', minute: '2-digit' }).format(new Date(iso));
}

function signalLabel(rssi: number | null) {
  if (rssi === null) return 'N/A';
  if (rssi >= -50) return `Excellent (${rssi} dBm)`;
  if (rssi >= -70) return `Good (${rssi} dBm)`;
  if (rssi >= -90) return `Fair (${rssi} dBm)`;
  return `Weak (${rssi} dBm)`;
}

function InfoRow({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex items-center justify-between border-b border-white/5 px-4 py-3 last:border-b-0">
      <span className="text-sm text-zinc-400">{label}</span>
      <span className="text-sm font-medium text-zinc-200">{value}</span>
    </div>
  );
}

export default function DeviceDetailPage() {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const [showDelete, setShowDelete] = useState(false);
  const [showRename, setShowRename] = useState(false);
  const [showShare, setShowShare] = useState(false);
  const [shareEmail, setShareEmail] = useState('');
  const [nickname, setNickname] = useState('');

  const { data: device, isLoading, error } = useQuery({
    queryKey: ['device-detail', id],
    queryFn: () => getDeviceDetail(id!),
    enabled: !!id,
  });

  const { data: shares } = useQuery({
    queryKey: ['device-shares', id],
    queryFn: () => getDeviceShares(id!),
    enabled: !!id,
  });

  const shareMutation = useMutation({
    mutationFn: (email: string) => shareDevice(id!, email),
    onSuccess: () => { queryClient.invalidateQueries({ queryKey: ['device-shares', id] }); setShowShare(false); setShareEmail(''); },
  });

  const unshareMutation = useMutation({
    mutationFn: (shareId: string) => removeDeviceShare(id!, shareId),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['device-shares', id] }),
  });

  const { data: events } = useQuery({
    queryKey: ['device-events', id],
    queryFn: () => getDeviceEvents(id!),
    enabled: !!id,
  });

  const updateMutation = useMutation({
    mutationFn: (body: { nickname?: string; isFavorite?: boolean }) => updateDevice(id!, body),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['device-detail', id] }),
  });

  const monitorMutation = useMutation({
    mutationFn: (newStatus: string) => updateDeviceStatus(id!, newStatus),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['device-detail', id] }),
  });

  const deleteMutation = useMutation({
    mutationFn: () => deleteDevice(id!),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['health-dashboard'] });
      navigate('/account');
    },
  });

  if (isLoading) {
    return (
      <div className="dark min-h-screen bg-black text-white">
        <Header />
        <main className="mx-auto max-w-3xl px-4 pb-16 pt-28">
          <p className="text-zinc-400">Loading device...</p>
        </main>
      </div>
    );
  }

  if (error || !device) {
    return (
      <div className="dark min-h-screen bg-black text-white">
        <Header />
        <main className="mx-auto max-w-3xl px-4 pb-16 pt-28">
          <p className="text-red-400">{(error as Error)?.message || 'Device not found'}</p>
          <Button variant="outline" className="mt-4" onClick={() => navigate('/account')}>Back</Button>
        </main>
      </div>
    );
  }

  const displayName = device.nickname?.trim() || device.name;

  return (
    <div className="dark min-h-screen bg-black text-white">
      <Header />
      <main className="mx-auto max-w-3xl space-y-6 px-4 pb-16 pt-28 sm:px-6">
        {/* Status Header */}
        <Card className="border-white/5 bg-zinc-900/70">
          <CardContent className="flex flex-col items-center gap-3 p-6">
            <div className="text-4xl">{device.type === 'earbuds' ? '🎧' : device.type === 'watch' ? '⌚' : '📍'}</div>
            <h1 className="text-xl font-bold text-white">{displayName}</h1>
            {device.nickname && <p className="text-xs text-zinc-500">{device.name}</p>}
            <Badge variant="outline" className={`text-xs ${statusColor(device.status)}`}>{device.status}</Badge>
            {device.lastSeenAt && <p className="text-xs text-zinc-500">Last seen: {formatDate(device.lastSeenAt)}</p>}
          </CardContent>
        </Card>

        {/* Bluetooth Info */}
        <Card className="border-white/5 bg-zinc-900/70">
          <CardHeader className="pb-2"><CardTitle className="text-sm text-zinc-400">Bluetooth Info</CardTitle></CardHeader>
          <CardContent className="p-0">
            <InfoRow label="Bluetooth ID" value={device.bluetoothIdentifier} />
            <InfoRow label="Signal" value={signalLabel(device.signalStrength)} />
            <InfoRow label="Firmware" value={device.firmwareVersion || 'Unknown'} />
            <InfoRow label="Type" value={device.type} />
            <InfoRow label="Added" value={formatDate(device.createdAt)} />
          </CardContent>
        </Card>

        {/* Controls */}
        <Card className="border-white/5 bg-zinc-900/70">
          <CardHeader className="pb-2"><CardTitle className="text-sm text-zinc-400">Controls</CardTitle></CardHeader>
          <CardContent className="space-y-3">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm font-medium text-zinc-200">Pinned Device</p>
                <p className="text-xs text-zinc-500">Pinned devices appear at the top</p>
              </div>
              <button
                type="button"
                role="switch"
                aria-checked={device.isFavorite}
                aria-label="Toggle pinned device"
                disabled={updateMutation.isPending}
                onClick={() => updateMutation.mutate({ isFavorite: !device.isFavorite })}
                className={`relative inline-flex h-6 w-11 rounded-full border-2 border-transparent transition-colors ${device.isFavorite ? 'bg-emerald-500' : 'bg-zinc-700'}`}
              >
                <span className={`inline-block h-5 w-5 rounded-full bg-white shadow transition-transform ${device.isFavorite ? 'translate-x-5' : 'translate-x-0'}`} />
              </button>
            </div>

            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm font-medium text-zinc-200">Active Monitoring</p>
                <p className="text-xs text-zinc-500">Alert on disconnect</p>
              </div>
              <button
                type="button"
                role="switch"
                aria-checked={device.isMonitoring}
                aria-label="Toggle active monitoring"
                disabled={monitorMutation.isPending}
                onClick={() => monitorMutation.mutate(device.isMonitoring ? 'connected' : 'monitoring')}
                className={`relative inline-flex h-6 w-11 rounded-full border-2 border-transparent transition-colors ${device.isMonitoring ? 'bg-emerald-500' : 'bg-zinc-700'}`}
              >
                <span className={`inline-block h-5 w-5 rounded-full bg-white shadow transition-transform ${device.isMonitoring ? 'translate-x-5' : 'translate-x-0'}`} />
              </button>
            </div>

            <Button variant="outline" className="w-full border-zinc-700 text-zinc-300" onClick={() => { setNickname(device.nickname || ''); setShowRename(true); }}>
              {device.nickname ? 'Edit Nickname' : 'Add Nickname'}
            </Button>
          </CardContent>
        </Card>

        {/* Event History */}
        {events && events.length > 0 && (
          <Card className="border-white/5 bg-zinc-900/70">
            <CardHeader className="pb-2"><CardTitle className="text-sm text-zinc-400">Event History</CardTitle></CardHeader>
            <CardContent className="space-y-2">
              {events.slice(0, 10).map((ev, i) => (
                <div key={i} className="flex items-center justify-between rounded-lg border border-white/5 bg-zinc-950 px-3 py-2">
                  <div className="flex items-center gap-2">
                    <span className={`h-2 w-2 rounded-full ${ev.action === 'connect' ? 'bg-emerald-500' : 'bg-red-500'}`} />
                    <span className="text-sm text-zinc-300">{ev.action === 'connect' ? 'Connected' : 'Disconnected'}</span>
                  </div>
                  <span className="text-xs text-zinc-500">{formatDate(ev.occurredAt)}</span>
                </div>
              ))}
            </CardContent>
          </Card>
        )}

        {/* Sharing */}
        <Card className="border-white/5 bg-zinc-900/70">
          <CardHeader className="pb-2">
            <div className="flex items-center justify-between">
              <CardTitle className="text-sm text-zinc-400">Shared With</CardTitle>
              <Button size="sm" className="h-7 bg-emerald-600 px-3 text-xs text-white" onClick={() => setShowShare(true)}>Share</Button>
            </div>
          </CardHeader>
          <CardContent className="space-y-2">
            {(!shares || shares.length === 0) ? (
              <p className="text-xs text-zinc-500">Not shared with anyone</p>
            ) : shares.map(s => (
              <div key={s._id} className="flex items-center justify-between rounded-lg border border-white/5 bg-zinc-950 px-3 py-2">
                <div>
                  <p className="text-sm text-zinc-200">{s.displayName || s.email}</p>
                  {s.displayName && <p className="text-xs text-zinc-500">{s.email}</p>}
                </div>
                <Button size="sm" variant="ghost" className="h-7 text-xs text-red-400" onClick={() => unshareMutation.mutate(s._id)}>Remove</Button>
              </div>
            ))}
          </CardContent>
        </Card>

        {/* Danger Zone */}
        <Button variant="destructive" className="w-full" onClick={() => setShowDelete(true)}>
          Delete Device
        </Button>
      </main>
      <Footer />

      {/* Delete Confirmation */}
      <Dialog open={showDelete} onOpenChange={setShowDelete}>
        <DialogContent className="border-zinc-800 bg-zinc-900 text-zinc-100">
          <DialogHeader>
            <DialogTitle>Delete {displayName}?</DialogTitle>
          </DialogHeader>
          <p className="text-sm text-zinc-400">This will permanently remove the device from your account. This cannot be undone.</p>
          <DialogFooter>
            <Button variant="outline" onClick={() => setShowDelete(false)}>Cancel</Button>
            <Button variant="destructive" onClick={() => deleteMutation.mutate()} disabled={deleteMutation.isPending}>
              {deleteMutation.isPending ? 'Deleting...' : 'Delete'}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Share Dialog */}
      <Dialog open={showShare} onOpenChange={setShowShare}>
        <DialogContent className="border-zinc-800 bg-zinc-900 text-zinc-100">
          <DialogHeader><DialogTitle>Share Device</DialogTitle></DialogHeader>
          <p className="text-sm text-zinc-400">Enter the email of the person you want to share this device with.</p>
          <Input value={shareEmail} onChange={e => setShareEmail(e.target.value)} placeholder="email@example.com" type="email" className="border-zinc-700 bg-zinc-950 text-white" />
          {shareMutation.isError && <p className="text-xs text-red-400">{(shareMutation.error as Error).message}</p>}
          <DialogFooter>
            <Button variant="outline" onClick={() => setShowShare(false)}>Cancel</Button>
            <Button className="bg-emerald-600 text-white" onClick={() => shareMutation.mutate(shareEmail)} disabled={!shareEmail || shareMutation.isPending}>
              {shareMutation.isPending ? 'Sharing...' : 'Share'}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Rename Dialog */}
      <Dialog open={showRename} onOpenChange={setShowRename}>
        <DialogContent className="border-zinc-800 bg-zinc-900 text-zinc-100">
          <DialogHeader>
            <DialogTitle>Edit Nickname</DialogTitle>
          </DialogHeader>
          <Input value={nickname} onChange={e => setNickname(e.target.value)} placeholder="Enter nickname" className="border-zinc-700 bg-zinc-950 text-white" />
          <DialogFooter>
            <Button variant="outline" onClick={() => setShowRename(false)}>Cancel</Button>
            <Button className="bg-emerald-600 text-white" onClick={() => { updateMutation.mutate({ nickname }); setShowRename(false); }}>Save</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}
