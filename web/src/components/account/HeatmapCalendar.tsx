import { cn } from '@/lib/utils';

interface DayEntry {
  date: string; // YYYY-MM-DD
  count: number;
}

interface HeatmapCalendarProps {
  data: DayEntry[];
  year: number;
  month: number; // 1-12
}

const WEEKDAY_LABELS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

function intensityClass(count: number): string {
  if (count === 0) return 'bg-zinc-800';
  if (count <= 1) return 'bg-emerald-900/60';
  if (count <= 3) return 'bg-emerald-700/70';
  if (count <= 5) return 'bg-emerald-500/80';
  return 'bg-emerald-400';
}

export default function HeatmapCalendar({ data, year, month }: HeatmapCalendarProps) {
  const firstDay = new Date(year, month - 1, 1);
  const daysInMonth = new Date(year, month, 0).getDate();
  const startDow = firstDay.getDay(); // 0 = Sunday

  const countMap = new Map<string, number>();
  for (const entry of data) {
    countMap.set(entry.date, entry.count);
  }

  const monthName = firstDay.toLocaleString('default', { month: 'long' });

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
          const count = countMap.get(dateStr) ?? 0;

          return (
            <div
              key={dateStr}
              title={`${dateStr}: ${count} session${count !== 1 ? 's' : ''}`}
              className={cn(
                'aspect-square rounded-sm transition-colors',
                intensityClass(count),
              )}
            />
          );
        })}
      </div>

      {/* Legend */}
      <div className="mt-3 flex items-center gap-1.5 text-[10px] text-zinc-500">
        <span>Less</span>
        <div className="h-2.5 w-2.5 rounded-sm bg-zinc-800" />
        <div className="h-2.5 w-2.5 rounded-sm bg-emerald-900/60" />
        <div className="h-2.5 w-2.5 rounded-sm bg-emerald-700/70" />
        <div className="h-2.5 w-2.5 rounded-sm bg-emerald-500/80" />
        <div className="h-2.5 w-2.5 rounded-sm bg-emerald-400" />
        <span>More</span>
      </div>
    </div>
  );
}
