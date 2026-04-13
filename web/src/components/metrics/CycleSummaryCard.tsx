import { Link } from 'react-router-dom';
import { useQuery } from '@tanstack/react-query';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { getCycles, getCycleMonthSummary } from '@/lib/api';

export default function CycleSummaryCard() {
  const now = new Date();
  const year = now.getFullYear();
  const month = now.getMonth() + 1;

  const cyclesQuery = useQuery({
    queryKey: ['cycles'],
    queryFn: getCycles,
    retry: false,
  });

  const monthSummaryQuery = useQuery({
    queryKey: ['cycles', 'month-summary', year, month],
    queryFn: () => getCycleMonthSummary(year, month),
    retry: false,
  });

  const cycles = cyclesQuery.data ?? [];
  const activeCycles = cycles.filter((cycle) => cycle.status === 'active').length;
  const plannedCycles = cycles.filter((cycle) => cycle.status === 'planned').length;

  return (
    <Card className="border-white/5 bg-zinc-900/70">
      <CardHeader className="flex flex-row items-center justify-between gap-4">
        <div>
          <CardTitle className="text-base font-semibold text-white">Cycle Tracking</CardTitle>
          <p className="mt-1 text-sm text-zinc-400">
            Account-level peptide and steroid cycle summary.
          </p>
        </div>
        <Link to="/account">
          <Button variant="outline" className="border-white/10 bg-zinc-950/60 text-zinc-200 hover:bg-zinc-900">
            Open Account
          </Button>
        </Link>
      </CardHeader>
      <CardContent className="space-y-4">
        {cyclesQuery.isLoading ? (
          <p className="text-sm text-zinc-500">Loading cycle summary...</p>
        ) : cyclesQuery.isError ? (
          <p className="text-sm text-zinc-500">
            Cycle endpoints are still syncing. Metrics will populate when available.
          </p>
        ) : cycles.length === 0 ? (
          <p className="text-sm text-zinc-400">
            No cycles logged yet.
          </p>
        ) : (
          <>
            <div className="grid gap-3 sm:grid-cols-3">
              <div className="rounded-2xl border border-white/8 bg-zinc-950/70 p-4">
                <p className="text-[11px] uppercase tracking-[0.18em] text-zinc-500">Total Cycles</p>
                <p className="mt-2 text-2xl font-semibold text-white">{cycles.length}</p>
              </div>
              <div className="rounded-2xl border border-white/8 bg-zinc-950/70 p-4">
                <p className="text-[11px] uppercase tracking-[0.18em] text-zinc-500">Active</p>
                <p className="mt-2 text-2xl font-semibold text-emerald-300">{activeCycles}</p>
              </div>
              <div className="rounded-2xl border border-white/8 bg-zinc-950/70 p-4">
                <p className="text-[11px] uppercase tracking-[0.18em] text-zinc-500">Entries This Month</p>
                <p className="mt-2 text-2xl font-semibold text-cyan-300">
                  {monthSummaryQuery.data?.totalEntries ?? 0}
                </p>
              </div>
            </div>
            <div className="flex flex-wrap gap-2 text-xs">
              <Badge className="border border-emerald-400/20 bg-emerald-400/10 text-emerald-300">
                Active: {activeCycles}
              </Badge>
              <Badge className="border border-cyan-400/20 bg-cyan-400/10 text-cyan-300">
                Planned: {plannedCycles}
              </Badge>
              <Badge className="border border-white/10 bg-white/5 text-zinc-300">
                Month Active Cycles: {monthSummaryQuery.data?.activeCycles ?? 0}
              </Badge>
            </div>
          </>
        )}
      </CardContent>
    </Card>
  );
}
