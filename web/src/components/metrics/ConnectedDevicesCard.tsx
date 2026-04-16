import { Link } from 'react-router-dom';
import { Badge } from '@/components/ui/badge';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';

interface DeviceItem {
  _id: string;
  name: string;
  nickname: string | null;
  type: string;
  status: string;
  isFavorite: boolean;
  lastSeenAt: string | null;
  healthCapable: boolean;
}

function deviceIcon(type: string) {
  switch (type) {
    case 'earbuds': return '🎧';
    case 'watch': return '⌚';
    case 'tracker': return '📍';
    case 'belt': return '🏋️';
    case 'bag': return '🎒';
    default: return '📱';
  }
}

function statusBadgeClass(status: string) {
  switch (status) {
    case 'connected':
    case 'monitoring':
    case 'reconnected':
    case 'active':
      return 'border-emerald-400/30 bg-emerald-400/10 text-emerald-300';
    case 'lost':
      return 'border-red-400/30 bg-red-400/10 text-red-300';
    case 'disconnected':
    case 'inactive':
      return 'border-amber-400/30 bg-amber-400/10 text-amber-300';
    default:
      return 'border-zinc-400/30 bg-zinc-400/10 text-zinc-300';
  }
}

function formatLastSeen(isoString: string | null) {
  if (!isoString) return 'Never';
  return new Intl.DateTimeFormat('en-US', {
    month: 'short',
    day: 'numeric',
    hour: 'numeric',
    minute: '2-digit',
  }).format(new Date(isoString));
}

export default function ConnectedDevicesCard({ devices }: { devices: DeviceItem[] }) {
  if (devices.length === 0) {
    return (
      <Card className="border-white/5 bg-zinc-900/70">
        <CardHeader className="pb-2">
          <CardTitle className="text-sm font-medium text-zinc-400">Connected Devices</CardTitle>
        </CardHeader>
        <CardContent className="pb-5">
          <p className="text-sm text-zinc-500">No devices registered. Pair a device from the iOS app.</p>
        </CardContent>
      </Card>
    );
  }

  return (
    <Card className="border-white/5 bg-zinc-900/70">
      <CardHeader className="pb-2">
        <CardTitle className="text-sm font-medium text-zinc-400">
          Connected Devices ({devices.length})
        </CardTitle>
      </CardHeader>
      <CardContent className="space-y-3 pb-5">
        {devices.map((device) => (
          <Link
            key={device._id}
            to={`/devices/${device._id}`}
            className="flex items-center gap-3 rounded-lg border border-white/5 bg-zinc-950 p-3 transition-colors hover:border-emerald-500/30"
          >
            <span className="text-xl">{deviceIcon(device.type)}</span>
            <div className="flex-1 min-w-0">
              <div className="flex items-center gap-2">
                <span className="truncate text-sm font-medium text-zinc-200">
                  {device.nickname || device.name}
                </span>
                {device.isFavorite && (
                  <span className="text-xs text-amber-400">&#9733;</span>
                )}
                {device.healthCapable && (
                  <span className="text-xs text-red-400">&#x2764;</span>
                )}
              </div>
              <span className="text-xs text-zinc-500">
                Last seen: {formatLastSeen(device.lastSeenAt)}
              </span>
            </div>
            <Badge variant="outline" className={`text-[10px] ${statusBadgeClass(device.status)}`}>
              {device.status}
            </Badge>
          </Link>
        ))}
      </CardContent>
    </Card>
  );
}
