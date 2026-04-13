import { cn } from '@/lib/utils';

interface DayEntry {
  date: string; // YYYY-MM-DD
  count: number;
  gymVisits?: number;
  mealsLogged?: number;
  purchasesMade?: number;
  waterIntakeMl?: number;
  workoutsCompleted?: number;
  runsCompleted?: number;
  medication?: {
    entryCount: number;
    totalDoseMg: number;
    categoryDoseMg: {
      steroid: number;
      peptide: number;
      oralMedication: number;
    };
    hasMedication: boolean;
  };
}

interface HeatmapCalendarProps {
  data: DayEntry[];
  year: number;
  month: number; // 1-12
  selectedDate?: string | null;
  onSelectDate?: (date: string) => void;
}

const WEEKDAY_LABELS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

function intensityClass(count: number): string {
  if (count === 0) return 'bg-zinc-800';
  if (count <= 1) return 'bg-emerald-900/60';
  if (count <= 3) return 'bg-emerald-700/70';
  if (count <= 5) return 'bg-emerald-500/80';
  return 'bg-emerald-400';
}

function formatDose(value: number): string {
  if (value === 0) return '0 mg';
  if (value >= 10) return `${value.toFixed(0)} mg`;
  return `${value.toFixed(1)} mg`;
}

export default function HeatmapCalendar({
  data,
  year,
  month,
  selectedDate = null,
  onSelectDate,
}: HeatmapCalendarProps) {
  const firstDay = new Date(year, month - 1, 1);
  const daysInMonth = new Date(year, month, 0).getDate();
  const startDow = firstDay.getDay(); // 0 = Sunday

  const entryMap = new Map<string, DayEntry>();
  for (const entry of data) {
    entryMap.set(entry.date, entry);
  }

  const monthName = firstDay.toLocaleString('default', { month: 'long' });
  const hasMedicationMarkers = data.some((entry) => entry.medication?.hasMedication);

  // Build grid cells: leading empties + day cells
  const cells: (number | null)[] = [];
  for (let i = 0; i < startDow; i++) cells.push(null);
  for (let d = 1; d <= daysInMonth; d++) cells.push(d);

  return (
    <div>
      <p className="mb-3 text-sm font-medium text-zinc-400">
        {monthName} {year}
      </p>

      {/* Weekday labels */}
      <div className="mb-1 grid grid-cols-7 gap-1">
        {WEEKDAY_LABELS.map((label) => (
          <span key={label} className="text-center text-[10px] font-medium text-zinc-500">
            {label}
          </span>
        ))}
      </div>

      {/* Day grid */}
      <div className="grid grid-cols-7 gap-1">
        {cells.map((day, i) => {
          if (day === null) {
            return <div key={`empty-${i}`} className="aspect-square" />;
          }

          const dateStr = `${year}-${String(month).padStart(2, '0')}-${String(day).padStart(2, '0')}`;
          const entry = entryMap.get(dateStr);
          const count = entry?.count ?? 0;
          const activitySignals: string[] = [];

          if ((entry?.gymVisits ?? 0) > 0) activitySignals.push(`${entry?.gymVisits} gym visit${entry?.gymVisits === 1 ? '' : 's'}`);
          if ((entry?.workoutsCompleted ?? 0) > 0) activitySignals.push(`${entry?.workoutsCompleted} workout${entry?.workoutsCompleted === 1 ? '' : 's'}`);
          if ((entry?.runsCompleted ?? 0) > 0) activitySignals.push(`${entry?.runsCompleted} run${entry?.runsCompleted === 1 ? '' : 's'}`);
          if ((entry?.mealsLogged ?? 0) > 0) activitySignals.push(`${entry?.mealsLogged} meal${entry?.mealsLogged === 1 ? '' : 's'}`);
          if ((entry?.waterIntakeMl ?? 0) > 0) activitySignals.push('water logged');
          if ((entry?.purchasesMade ?? 0) > 0) activitySignals.push(`${entry?.purchasesMade} purchase${entry?.purchasesMade === 1 ? '' : 's'}`);
          if (entry?.medication?.hasMedication) {
            activitySignals.push(
              `${entry.medication.entryCount} medication dose${entry.medication.entryCount === 1 ? '' : 's'} (${formatDose(entry.medication.totalDoseMg)})`,
            );
          }
          const title = activitySignals.length > 0
            ? `${dateStr}: ${activitySignals.join(' • ')}`
            : `${dateStr}: no logged activity`;
          const isSelected = selectedDate === dateStr;

          return (
            <button
              key={dateStr}
              type="button"
              title={title}
              onClick={() => onSelectDate?.(dateStr)}
              className={cn(
                'relative aspect-square rounded-sm transition-colors',
                intensityClass(count),
                onSelectDate ? 'cursor-pointer hover:ring-2 hover:ring-emerald-300/40 focus-visible:ring-2 focus-visible:ring-emerald-300/60 focus-visible:outline-none' : 'cursor-default',
                isSelected ? 'ring-2 ring-cyan-300' : null,
              )}
            >
              <span className="absolute bottom-1 left-1 text-[9px] font-medium text-zinc-200/80">
                {day}
              </span>
              {entry?.medication?.hasMedication ? (
                <span className="absolute right-1 top-1 h-1.5 w-1.5 rounded-full bg-amber-300 shadow-[0_0_0_2px_rgba(24,24,27,0.8)]" />
              ) : null}
            </button>
          );
        })}
      </div>

      {/* Legend */}
      <div className="mt-3 flex flex-wrap items-center gap-1.5 text-[10px] text-zinc-500">
        <span>Less</span>
        <div className="h-2.5 w-2.5 rounded-sm bg-zinc-800" />
        <div className="h-2.5 w-2.5 rounded-sm bg-emerald-900/60" />
        <div className="h-2.5 w-2.5 rounded-sm bg-emerald-700/70" />
        <div className="h-2.5 w-2.5 rounded-sm bg-emerald-500/80" />
        <div className="h-2.5 w-2.5 rounded-sm bg-emerald-400" />
        <span>More</span>
        {hasMedicationMarkers ? (
          <>
            <span className="ml-3">Dose logged</span>
            <div className="h-2.5 w-2.5 rounded-full bg-amber-300" />
          </>
        ) : null}
      </div>
    </div>
  );
}
