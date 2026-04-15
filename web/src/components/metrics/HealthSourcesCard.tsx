import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';

interface HealthSource {
  name: string;
  type: string;
  lastDataAt: string | null;
  sampleCountToday: number;
}

function sourceIcon(type: string) {
  switch (type) {
    case 'airpods_pro': return '🎧';
    case 'apple_watch': return '⌚';
    case 'apple_health': return '💚';
    case 'manual': return '✏️';
    default: return '📊';
  }
}

function formatTime(isoString: string | null) {
  if (!isoString) return 'No data';
  return new Intl.DateTimeFormat('en-US', {
    hour: 'numeric',
    minute: '2-digit',
  }).format(new Date(isoString));
}

export default function HealthSourcesCard({ sources }: { sources: HealthSource[] }) {
  if (sources.length === 0) {
    return null;
  }

  return (
    <Card className="border-white/5 bg-zinc-900/70">
      <CardHeader className="pb-2">
        <CardTitle className="text-sm font-medium text-zinc-400">Health Data Sources</CardTitle>
      </CardHeader>
      <CardContent className="space-y-2 pb-5">
        {sources.map((source) => (
          <div
            key={source.type}
            className="flex items-center gap-3 rounded-lg border border-white/5 bg-zinc-950 px-3 py-2"
          >
            <span className="text-lg">{sourceIcon(source.type)}</span>
            <div className="flex-1">
              <span className="text-sm font-medium text-zinc-200">{source.name}</span>
              <p className="text-xs text-zinc-500">
                {source.sampleCountToday > 0
                  ? `${source.sampleCountToday} samples today`
                  : 'No samples today'}
              </p>
            </div>
            <span className="text-xs text-zinc-500">
              {formatTime(source.lastDataAt)}
            </span>
          </div>
        ))}
      </CardContent>
    </Card>
  );
}
