import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';

interface HeartRateData {
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
}

const ZONE_CONFIG = [
  { key: 'rest', label: 'Rest', color: 'bg-zinc-500' },
  { key: 'light', label: 'Light', color: 'bg-blue-500' },
  { key: 'fatBurn', label: 'Fat Burn', color: 'bg-emerald-500' },
  { key: 'cardio', label: 'Cardio', color: 'bg-orange-500' },
  { key: 'peak', label: 'Peak', color: 'bg-red-500' },
] as const;

function zoneColor(bpm: number) {
  if (bpm < 100) return 'text-zinc-400';
  if (bpm < 120) return 'text-blue-400';
  if (bpm < 140) return 'text-emerald-400';
  if (bpm < 160) return 'text-orange-400';
  return 'text-red-400';
}

function zoneLabel(bpm: number) {
  if (bpm < 100) return 'Rest';
  if (bpm < 120) return 'Light';
  if (bpm < 140) return 'Fat Burn';
  if (bpm < 160) return 'Cardio';
  return 'Peak';
}

function formatTime(isoString: string) {
  return new Intl.DateTimeFormat('en-US', {
    hour: 'numeric',
    minute: '2-digit',
  }).format(new Date(isoString));
}

export default function HeartRateSummaryCard({ data }: { data: HeartRateData }) {
  if (!data.latest && !data.today) {
    return (
      <Card className="border-white/5 bg-zinc-900/70">
        <CardHeader className="pb-2">
          <CardTitle className="text-sm font-medium text-zinc-400">Heart Rate</CardTitle>
        </CardHeader>
        <CardContent className="pb-5">
          <p className="text-sm text-zinc-500">No heart rate data available. Connect AirPods Pro 3 or Apple Watch to start tracking.</p>
        </CardContent>
      </Card>
    );
  }

  return (
    <Card className="border-white/5 bg-zinc-900/70">
      <CardHeader className="pb-2">
        <CardTitle className="flex items-center gap-2 text-sm font-medium text-zinc-400">
          <span className="text-red-400">&#x2764;</span>
          Heart Rate
        </CardTitle>
      </CardHeader>
      <CardContent className="space-y-4 pb-5">
        {data.latest && (
          <div className="flex items-baseline gap-3">
            <span className={`text-4xl font-bold ${zoneColor(data.latest.bpm)}`}>
              {data.latest.bpm}
            </span>
            <span className="text-sm text-zinc-500">BPM</span>
            <span className={`ml-1 rounded-full px-2 py-0.5 text-xs font-medium ${zoneColor(data.latest.bpm)} bg-white/5`}>
              {zoneLabel(data.latest.bpm)}
            </span>
            <span className="ml-auto text-xs text-zinc-600">
              {formatTime(data.latest.recordedAt)}
            </span>
          </div>
        )}

        {data.today && (
          <>
            <div className="grid grid-cols-3 gap-3">
              <div className="rounded-lg border border-white/5 bg-zinc-950 p-3">
                <span className="text-xs text-zinc-500">Min</span>
                <p className="text-lg font-semibold text-zinc-300">{data.today.minBPM}</p>
              </div>
              <div className="rounded-lg border border-white/5 bg-zinc-950 p-3">
                <span className="text-xs text-zinc-500">Avg</span>
                <p className="text-lg font-semibold text-zinc-300">{Math.round(data.today.avgBPM)}</p>
              </div>
              <div className="rounded-lg border border-white/5 bg-zinc-950 p-3">
                <span className="text-xs text-zinc-500">Max</span>
                <p className="text-lg font-semibold text-zinc-300">{data.today.maxBPM}</p>
              </div>
            </div>

            <div className="space-y-2">
              <span className="text-xs font-medium uppercase tracking-wider text-zinc-500">Zone Distribution</span>
              <div className="flex h-3 w-full overflow-hidden rounded-full">
                {ZONE_CONFIG.map(({ key, color }) => {
                  const pct = data.today!.zoneDistribution[key as keyof typeof data.today.zoneDistribution];
                  if (pct <= 0) return null;
                  return <div key={key} className={`${color}`} style={{ width: `${pct}%` }} />;
                })}
              </div>
              <div className="flex flex-wrap gap-x-4 gap-y-1">
                {ZONE_CONFIG.map(({ key, label, color }) => {
                  const pct = data.today!.zoneDistribution[key as keyof typeof data.today.zoneDistribution];
                  if (pct <= 0) return null;
                  return (
                    <div key={key} className="flex items-center gap-1.5 text-xs text-zinc-400">
                      <span className={`inline-block h-2 w-2 rounded-full ${color}`} />
                      {label} {pct}%
                    </div>
                  );
                })}
              </div>
            </div>

            <p className="text-xs text-zinc-600">{data.today.sampleCount} samples today</p>
          </>
        )}
      </CardContent>
    </Card>
  );
}
