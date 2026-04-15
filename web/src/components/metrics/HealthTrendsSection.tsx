import { useQuery } from '@tanstack/react-query';
import { useState } from 'react';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { getHealthTrends } from '@/lib/api';

const ZONE_COLORS: Record<string, string> = {
  rest: '#6b7280',
  light: '#3b82f6',
  fatBurn: '#10b981',
  cardio: '#f97316',
  peak: '#ef4444',
};

function zoneLabel(zone: string) {
  const map: Record<string, string> = { rest: 'Rest', light: 'Light', fatBurn: 'Fat Burn', cardio: 'Cardio', peak: 'Peak' };
  return map[zone] || zone;
}

function SimpleBarChart({ data, color, height = 120 }: { data: { value: number }[]; color: string; height?: number }) {
  if (data.length === 0) return null;
  const max = Math.max(...data.map((d) => d.value), 1);

  return (
    <div className="flex items-end gap-[2px]" style={{ height }}>
      {data.map((d, i) => (
        <div
          key={i}
          className="flex-1 rounded-t-sm"
          style={{
            height: `${(d.value / max) * 100}%`,
            backgroundColor: color,
            opacity: 0.7,
            minHeight: d.value > 0 ? 2 : 0,
          }}
        />
      ))}
    </div>
  );
}

function SimpleLineChart({ data, color, height = 120 }: { data: { value: number }[]; color: string; height?: number }) {
  if (data.length < 2) return null;
  const max = Math.max(...data.map((d) => d.value));
  const min = Math.min(...data.map((d) => d.value));
  const range = max - min || 1;

  const points = data.map((d, i) => {
    const x = (i / (data.length - 1)) * 100;
    const y = 100 - ((d.value - min) / range) * 100;
    return `${x},${y}`;
  });

  const areaPoints = [...points, `100,100`, `0,100`].join(' ');

  return (
    <svg viewBox="0 0 100 100" preserveAspectRatio="none" style={{ height, width: '100%' }}>
      <polygon points={areaPoints} fill={color} opacity="0.15" />
      <polyline points={points.join(' ')} fill="none" stroke={color} strokeWidth="1.5" vectorEffect="non-scaling-stroke" />
    </svg>
  );
}

function ScatterPlot({ data, height = 160 }: { data: { bpm: number; zone: string }[]; height?: number }) {
  if (data.length === 0) return null;
  const maxBpm = Math.max(...data.map((d) => d.bpm));
  const minBpm = Math.min(...data.map((d) => d.bpm));
  const range = maxBpm - minBpm || 1;

  return (
    <svg viewBox="0 0 100 100" preserveAspectRatio="none" style={{ height, width: '100%' }}>
      {data.map((d, i) => {
        const x = (i / (data.length - 1)) * 100;
        const y = 100 - ((d.bpm - minBpm) / range) * 100;
        return (
          <circle
            key={i}
            cx={x}
            cy={y}
            r="0.8"
            fill={ZONE_COLORS[d.zone] || '#ef4444'}
          />
        );
      })}
    </svg>
  );
}

function StatPill({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex flex-col items-center rounded-lg border border-white/5 bg-zinc-950 px-3 py-2">
      <span className="text-sm font-semibold text-zinc-200">{value}</span>
      <span className="text-[10px] text-zinc-500">{label}</span>
    </div>
  );
}

export default function HealthTrendsSection() {
  const [days, setDays] = useState(30);
  const { data, isLoading } = useQuery({
    queryKey: ['health-trends', days],
    queryFn: () => getHealthTrends(days),
    staleTime: 60_000,
  });

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <h3 className="text-lg font-semibold text-white">Health Trends</h3>
        <div className="flex gap-1 rounded-lg bg-zinc-900 p-1">
          {[7, 30, 90].map((d) => (
            <Button
              key={d}
              variant={days === d ? 'default' : 'ghost'}
              size="sm"
              className={`h-7 px-3 text-xs ${days === d ? 'bg-emerald-600 text-white' : 'text-zinc-400'}`}
              onClick={() => setDays(d)}
            >
              {d}D
            </Button>
          ))}
        </div>
      </div>

      {isLoading ? (
        <Card className="border-white/5 bg-zinc-900/70">
          <CardContent className="p-8 text-sm text-zinc-400">Loading trends...</CardContent>
        </Card>
      ) : !data ? null : (
        <div className="grid gap-4 md:grid-cols-2">
          {/* Heart Rate Scatter */}
          <Card className="border-white/5 bg-zinc-900/70">
            <CardHeader className="pb-2">
              <CardTitle className="flex items-center gap-2 text-sm text-zinc-400">
                <span className="text-red-400">&#x2764;</span> Heart Rate Scatter
              </CardTitle>
            </CardHeader>
            <CardContent className="pb-4">
              {data.heartRateScatter.length > 0 ? (
                <>
                  <ScatterPlot data={data.heartRateScatter} />
                  <div className="mt-2 flex flex-wrap gap-3">
                    {Object.entries(ZONE_COLORS).map(([zone, color]) => (
                      <span key={zone} className="flex items-center gap-1 text-[10px] text-zinc-500">
                        <span className="inline-block h-2 w-2 rounded-full" style={{ backgroundColor: color }} />
                        {zoneLabel(zone)}
                      </span>
                    ))}
                  </div>
                </>
              ) : (
                <p className="py-8 text-center text-xs text-zinc-600">No heart rate data</p>
              )}
            </CardContent>
          </Card>

          {/* Resting HR */}
          <Card className="border-white/5 bg-zinc-900/70">
            <CardHeader className="pb-2">
              <CardTitle className="text-sm text-zinc-400">Resting Heart Rate</CardTitle>
            </CardHeader>
            <CardContent className="pb-4">
              {data.restingHeartRate.length > 1 ? (
                <>
                  <SimpleLineChart data={data.restingHeartRate} color="#ef4444" />
                  <div className="mt-2 grid grid-cols-3 gap-2">
                    <StatPill label="Avg" value={`${Math.round(data.restingHeartRate.reduce((s, p) => s + p.value, 0) / data.restingHeartRate.length)} bpm`} />
                    <StatPill label="Low" value={`${Math.round(Math.min(...data.restingHeartRate.map((p) => p.value)))} bpm`} />
                    <StatPill label="High" value={`${Math.round(Math.max(...data.restingHeartRate.map((p) => p.value)))} bpm`} />
                  </div>
                </>
              ) : (
                <p className="py-8 text-center text-xs text-zinc-600">Not enough data</p>
              )}
            </CardContent>
          </Card>

          {/* Workout Activity */}
          <Card className="border-white/5 bg-zinc-900/70">
            <CardHeader className="pb-2">
              <CardTitle className="text-sm text-zinc-400">Workout Activity</CardTitle>
            </CardHeader>
            <CardContent className="pb-4">
              {data.workoutTrend.length > 0 ? (
                <>
                  <SimpleBarChart data={data.workoutTrend.map((w) => ({ value: w.durationMinutes }))} color="#10b981" />
                  <div className="mt-2 grid grid-cols-3 gap-2">
                    <StatPill label="Sessions" value={`${data.workoutTrend.reduce((s, w) => s + w.count, 0)}`} />
                    <StatPill label="Total" value={`${Math.round(data.workoutTrend.reduce((s, w) => s + w.durationMinutes, 0))}m`} />
                    <StatPill label="Days" value={`${data.workoutTrend.length}`} />
                  </div>
                </>
              ) : (
                <p className="py-8 text-center text-xs text-zinc-600">No workout data</p>
              )}
            </CardContent>
          </Card>

          {/* Weight Trend */}
          <Card className="border-white/5 bg-zinc-900/70">
            <CardHeader className="pb-2">
              <CardTitle className="text-sm text-zinc-400">Weight</CardTitle>
            </CardHeader>
            <CardContent className="pb-4">
              {data.weightTrend.length > 1 ? (
                <>
                  <SimpleLineChart data={data.weightTrend} color="#10b981" />
                  <div className="mt-2 grid grid-cols-3 gap-2">
                    <StatPill label="Current" value={`${data.weightTrend[data.weightTrend.length - 1].value.toFixed(1)} ${data.weightTrend[0].unit}`} />
                    <StatPill label="Change" value={`${(data.weightTrend[data.weightTrend.length - 1].value - data.weightTrend[0].value) >= 0 ? '+' : ''}${(data.weightTrend[data.weightTrend.length - 1].value - data.weightTrend[0].value).toFixed(1)}`} />
                    <StatPill label="Entries" value={`${data.weightTrend.length}`} />
                  </div>
                </>
              ) : (
                <p className="py-8 text-center text-xs text-zinc-600">Not enough weight data</p>
              )}
            </CardContent>
          </Card>

          {/* Calories Burned */}
          <Card className="col-span-full border-white/5 bg-zinc-900/70">
            <CardHeader className="pb-2">
              <CardTitle className="text-sm text-zinc-400">Active Calories</CardTitle>
            </CardHeader>
            <CardContent className="pb-4">
              {data.caloriesTrend.length > 0 ? (
                <>
                  <SimpleBarChart data={data.caloriesTrend} color="#f97316" height={100} />
                  <div className="mt-2 grid grid-cols-3 gap-2">
                    <StatPill label="Total" value={`${Math.round(data.caloriesTrend.reduce((s, c) => s + c.value, 0))} kcal`} />
                    <StatPill label="Daily Avg" value={`${Math.round(data.caloriesTrend.reduce((s, c) => s + c.value, 0) / data.caloriesTrend.length)} kcal`} />
                    <StatPill label="Days" value={`${data.caloriesTrend.length}`} />
                  </div>
                </>
              ) : (
                <p className="py-8 text-center text-xs text-zinc-600">No calorie data</p>
              )}
            </CardContent>
          </Card>
        </div>
      )}
    </div>
  );
}
