import { Badge } from '@/components/ui/badge';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import type { MedicationYearGraphResponse } from '@/lib/api';

const CHART_WIDTH = 960;
const CHART_HEIGHT = 260;
const PADDING = {
  top: 16,
  right: 20,
  bottom: 34,
  left: 42,
};

const SERIES = [
  { key: 'steroid', label: 'Steroid', color: '#22d3ee', dash: undefined },
  { key: 'peptide', label: 'Peptide', color: '#f59e0b', dash: '10 6' },
  { key: 'oralMedication', label: 'Oral', color: '#34d399', dash: '4 5' },
] as const;

function formatDose(value: number): string {
  if (value >= 10) {
    return `${value.toFixed(0)} mg`;
  }

  if (value === 0) {
    return '0 mg';
  }

  return `${value.toFixed(1)} mg`;
}

function monthAnchorLabel(day: number): string {
  if (day <= 1) return 'Jan';
  if (day <= 91) return 'Apr';
  if (day <= 182) return 'Jul';
  if (day <= 274) return 'Oct';
  return 'Dec';
}

function buildLinePath(values: number[], endDay: number, yMax: number): string {
  if (values.length === 0 || endDay <= 1 || yMax <= 0) {
    return '';
  }

  const drawableWidth = CHART_WIDTH - PADDING.left - PADDING.right;
  const drawableHeight = CHART_HEIGHT - PADDING.top - PADDING.bottom;

  return values
    .map((value, index) => {
      const day = index + 1;
      const x = PADDING.left + ((day - 1) / Math.max(endDay - 1, 1)) * drawableWidth;
      const clampedValue = Math.min(Math.max(value, 0), yMax);
      const y = PADDING.top + (1 - clampedValue / yMax) * drawableHeight;
      return `${index === 0 ? 'M' : 'L'} ${x.toFixed(2)} ${y.toFixed(2)}`;
    })
    .join(' ');
}

function yPosition(value: number, yMax: number): number {
  const drawableHeight = CHART_HEIGHT - PADDING.top - PADDING.bottom;
  return PADDING.top + (1 - value / yMax) * drawableHeight;
}

function xPosition(day: number, endDay: number): number {
  const drawableWidth = CHART_WIDTH - PADDING.left - PADDING.right;
  return PADDING.left + ((day - 1) / Math.max(endDay - 1, 1)) * drawableWidth;
}

export default function MedicationYearGraphCard({
  graph,
}: {
  graph: MedicationYearGraphResponse;
}) {
  const yMax = Math.max(graph.axis.yMg.max, 1);
  const endDay = Math.max(graph.axis.x.endDay, 1);
  const peakDoseMg = Math.max(
    0,
    ...graph.series.steroidMgByDay,
    ...graph.series.peptideMgByDay,
    ...graph.series.oralMedicationMgByDay,
  );
  const hasAnyDose = peakDoseMg > 0 || graph.totalsMg.all > 0;

  return (
    <Card className="border-white/5 bg-zinc-900/70">
      <CardHeader className="flex flex-col gap-4 lg:flex-row lg:items-start lg:justify-between">
        <div>
          <div className="flex items-center gap-3">
            <CardTitle className="text-base font-semibold text-white">
              Medication Dose Graph
            </CardTitle>
            <Badge
              variant="secondary"
              className="border border-amber-500/20 bg-amber-500/10 text-amber-300"
            >
              Day 1–{graph.axis.x.endDay} / 0–20 mg
            </Badge>
          </div>
          <p className="mt-2 max-w-2xl text-sm text-zinc-400">
            Daily dose totals split into steroid, peptide, and oral medication series for{' '}
            {graph.year}. The chart keeps a fixed 20 mg ceiling so trends stay comparable across the
            year.
          </p>
        </div>

        <div className="grid grid-cols-3 gap-3">
          {SERIES.map((series) => (
            <div
              key={series.key}
              className="rounded-2xl border border-white/8 bg-zinc-950/70 px-4 py-3"
            >
              <p className="text-[11px] uppercase tracking-[0.18em] text-zinc-500">
                {series.label}
              </p>
              <p className="mt-2 text-lg font-semibold text-white">
                {formatDose(graph.totalsMg[series.key])}
              </p>
            </div>
          ))}
        </div>
      </CardHeader>

      <CardContent>
        {hasAnyDose ? (
          <div className="space-y-4">
            <div className="overflow-hidden rounded-2xl border border-white/8 bg-zinc-950/70 p-4">
              <svg viewBox={`0 0 ${CHART_WIDTH} ${CHART_HEIGHT}`} className="h-72 w-full">
                {[0, 5, 10, 15, 20].map((value) => (
                  <g key={value}>
                    <line
                      x1={PADDING.left}
                      x2={CHART_WIDTH - PADDING.right}
                      y1={yPosition(value, yMax)}
                      y2={yPosition(value, yMax)}
                      stroke="rgba(255,255,255,0.08)"
                      strokeWidth="1"
                    />
                    <text
                      x={PADDING.left - 10}
                      y={yPosition(value, yMax) + 4}
                      fill="rgba(161,161,170,0.9)"
                      fontSize="11"
                      textAnchor="end"
                    >
                      {value}
                    </text>
                  </g>
                ))}

                {[1, 91, 182, 274, endDay].map((day) => (
                  <g key={day}>
                    <line
                      x1={xPosition(day, endDay)}
                      x2={xPosition(day, endDay)}
                      y1={PADDING.top}
                      y2={CHART_HEIGHT - PADDING.bottom}
                      stroke="rgba(255,255,255,0.06)"
                      strokeWidth="1"
                    />
                    <text
                      x={xPosition(day, endDay)}
                      y={CHART_HEIGHT - 10}
                      fill="rgba(161,161,170,0.9)"
                      fontSize="11"
                      textAnchor="middle"
                    >
                      {monthAnchorLabel(day)}
                    </text>
                  </g>
                ))}

                {SERIES.map((series) => {
                  const values = graph.series[`${series.key}MgByDay` as const];
                  const path = buildLinePath(values, endDay, yMax);

                  return (
                    <path
                      key={series.key}
                      d={path}
                      fill="none"
                      stroke={series.color}
                      strokeWidth="3"
                      strokeLinecap="round"
                      strokeLinejoin="round"
                      strokeDasharray={series.dash}
                    />
                  );
                })}
              </svg>
            </div>

            <div className="flex flex-wrap items-center gap-4 text-xs text-zinc-400">
              {SERIES.map((series) => (
                <div key={series.key} className="flex items-center gap-2">
                  <span
                    className="h-2.5 w-8 rounded-full"
                    style={{
                      backgroundColor: series.color,
                      opacity: 0.95,
                    }}
                  />
                  <span>{series.label}</span>
                </div>
              ))}
              <span className="ml-auto">
                Total logged this year: <span className="font-semibold text-white">{formatDose(graph.totalsMg.all)}</span>
              </span>
            </div>

            {peakDoseMg > graph.axis.yMg.max ? (
              <p className="text-xs text-amber-300">
                Daily values above {graph.axis.yMg.max} mg are clipped in the graph to preserve the
                fixed y-axis requested for year-over-year comparison.
              </p>
            ) : null}
          </div>
        ) : (
          <div className="rounded-2xl border border-white/8 bg-zinc-950/70 px-5 py-6 text-sm text-zinc-400">
            No medication doses have been logged for {graph.year} yet.
          </div>
        )}
      </CardContent>
    </Card>
  );
}
