import { useQuery, useQueryClient } from '@tanstack/react-query';
import { useEffect, useState, type FormEvent } from 'react';
import { toast } from 'sonner';
import HeatmapCalendar from '@/components/account/HeatmapCalendar';
import MedicationDoseDialog from '@/components/account/MedicationDoseDialog';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import {
  createCycle,
  getCycles,
  getCycleMonthSummary,
  type Cycle,
  type CycleStatus,
  type CycleType,
} from '@/lib/api';

function statusBadgeClass(status: CycleStatus): string {
  switch (status) {
    case 'active':
      return 'border-emerald-700 text-emerald-400';
    case 'planned':
      return 'border-cyan-700 text-cyan-300';
    case 'paused':
      return 'border-amber-700 text-amber-300';
    case 'completed':
      return 'border-zinc-600 text-zinc-300';
    case 'archived':
      return 'border-zinc-700 text-zinc-500';
    default:
      return 'border-zinc-700 text-zinc-400';
  }
}

function formatDate(value: string | null): string {
  if (!value) {
    return 'Present';
  }
  return new Date(value).toLocaleDateString('en-US', {
    month: 'short',
    day: 'numeric',
    year: 'numeric',
  });
}

function formatCycleWindow(cycle: Cycle): string {
  return `${formatDate(cycle.startDate)} → ${formatDate(cycle.endDate)}`;
}

function toInputDateValue(date: Date): string {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, '0');
  const day = String(date.getDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
}

function toIsoDate(value: string): string {
  const parsed = new Date(`${value}T12:00:00`);
  if (Number.isNaN(parsed.getTime())) {
    throw new Error('Choose a valid date.');
  }
  return parsed.toISOString();
}

const typeOptions: Array<{ value: CycleType; label: string }> = [
  { value: 'peptide', label: 'Peptide' },
  { value: 'steroid', label: 'Steroid' },
  { value: 'mixed', label: 'Mixed' },
  { value: 'other', label: 'Other' },
];

const statusOptions: Array<{ value: CycleStatus; label: string }> = [
  { value: 'planned', label: 'Planned' },
  { value: 'active', label: 'Active' },
  { value: 'paused', label: 'Paused' },
  { value: 'completed', label: 'Completed' },
  { value: 'archived', label: 'Archived' },
];

function CreateCycleDialog({
  open,
  onOpenChange,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
}) {
  const queryClient = useQueryClient();
  const [name, setName] = useState('');
  const [type, setType] = useState<CycleType>('other');
  const [status, setStatus] = useState<CycleStatus>('planned');
  const [startDate, setStartDate] = useState(toInputDateValue(new Date()));
  const [endDate, setEndDate] = useState('');
  const [notes, setNotes] = useState('');
  const [isSaving, setIsSaving] = useState(false);

  useEffect(() => {
    if (!open) {
      return;
    }

    setName('');
    setType('other');
    setStatus('planned');
    setStartDate(toInputDateValue(new Date()));
    setEndDate('');
    setNotes('');
  }, [open]);

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();

    if (!name.trim()) {
      toast.error('Enter a cycle name.');
      return;
    }
    if (endDate && endDate < startDate) {
      toast.error('End date must be on or after the start date.');
      return;
    }

    setIsSaving(true);

    try {
      await createCycle({
        name: name.trim(),
        type,
        status,
        startDate: toIsoDate(startDate),
        endDate: endDate ? toIsoDate(endDate) : null,
        timezone: Intl.DateTimeFormat().resolvedOptions().timeZone || 'UTC',
        notes: notes.trim() || null,
        tags: [],
        compounds: [],
      });

      await queryClient.invalidateQueries({ queryKey: ['cycles'] });
      toast.success('Cycle created.');
      onOpenChange(false);
    } catch (error) {
      toast.error(error instanceof Error ? error.message : 'Failed to create cycle.');
    } finally {
      setIsSaving(false);
    }
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="border-zinc-800 bg-zinc-900 text-zinc-100 sm:max-w-lg">
        <DialogHeader>
          <DialogTitle>Create Cycle</DialogTitle>
          <DialogDescription className="text-zinc-400">
            Start a new cycle from the same surface where you already review status and activity.
          </DialogDescription>
        </DialogHeader>

        <form className="space-y-4" onSubmit={handleSubmit}>
          <div className="space-y-2">
            <Label htmlFor="cycle-name">Name</Label>
            <Input
              id="cycle-name"
              value={name}
              onChange={(event) => setName(event.target.value)}
              placeholder="e.g. Spring recomp"
              className="border-zinc-700 bg-zinc-950 text-white"
            />
          </div>

          <div className="grid gap-4 sm:grid-cols-2">
            <div className="space-y-2">
              <Label htmlFor="cycle-type">Type</Label>
              <select
                id="cycle-type"
                value={type}
                onChange={(event) => setType(event.target.value as CycleType)}
                className="w-full rounded-lg border border-zinc-700 bg-zinc-950 px-3 py-2 text-sm text-white outline-none transition focus:border-emerald-500"
              >
                {typeOptions.map((option) => (
                  <option key={option.value} value={option.value} className="bg-zinc-950">
                    {option.label}
                  </option>
                ))}
              </select>
            </div>

            <div className="space-y-2">
              <Label htmlFor="cycle-status">Status</Label>
              <select
                id="cycle-status"
                value={status}
                onChange={(event) => setStatus(event.target.value as CycleStatus)}
                className="w-full rounded-lg border border-zinc-700 bg-zinc-950 px-3 py-2 text-sm text-white outline-none transition focus:border-emerald-500"
              >
                {statusOptions.map((option) => (
                  <option key={option.value} value={option.value} className="bg-zinc-950">
                    {option.label}
                  </option>
                ))}
              </select>
            </div>
          </div>

          <div className="grid gap-4 sm:grid-cols-2">
            <div className="space-y-2">
              <Label htmlFor="cycle-start-date">Start Date</Label>
              <Input
                id="cycle-start-date"
                type="date"
                value={startDate}
                onChange={(event) => setStartDate(event.target.value)}
                className="border-zinc-700 bg-zinc-950 text-white"
              />
            </div>

            <div className="space-y-2">
              <Label htmlFor="cycle-end-date">End Date</Label>
              <Input
                id="cycle-end-date"
                type="date"
                value={endDate}
                onChange={(event) => setEndDate(event.target.value)}
                className="border-zinc-700 bg-zinc-950 text-white"
              />
            </div>
          </div>

          <div className="space-y-2">
            <Label htmlFor="cycle-notes">Notes</Label>
            <textarea
              id="cycle-notes"
              value={notes}
              onChange={(event) => setNotes(event.target.value)}
              rows={3}
              placeholder="Optional notes, goals, or protocol summary"
              className="w-full rounded-lg border border-zinc-700 bg-zinc-950 px-3 py-2 text-sm text-white outline-none transition focus:border-emerald-500"
            />
          </div>

          <DialogFooter showCloseButton>
            <Button
              type="submit"
              className="bg-emerald-400 text-black hover:bg-emerald-300"
              disabled={isSaving}
            >
              {isSaving ? 'Saving...' : 'Create Cycle'}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}

export default function CyclesPanel() {
  const now = new Date();
  const year = now.getFullYear();
  const month = now.getMonth() + 1;
  const [isCycleDialogOpen, setCycleDialogOpen] = useState(false);
  const [isMedicationDialogOpen, setMedicationDialogOpen] = useState(false);

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

  return (
    <div className="space-y-6">
      <Card className="border-zinc-800 bg-zinc-900/50">
        <CardHeader>
          <div className="flex flex-wrap items-start justify-between gap-3">
            <div className="space-y-1">
              <CardTitle>Cycle Tracking</CardTitle>
              <p className="text-sm text-zinc-400">
                Create cycles and log medication without leaving this surface.
              </p>
            </div>

            <div className="flex flex-wrap gap-2">
              <Button
                variant="outline"
                className="border-zinc-700 text-zinc-200 hover:text-white"
                onClick={() => setMedicationDialogOpen(true)}
              >
                Log Medication
              </Button>
              <Button
                className="bg-emerald-400 text-black hover:bg-emerald-300"
                onClick={() => setCycleDialogOpen(true)}
              >
                Create Cycle
              </Button>
            </div>
          </div>
        </CardHeader>
        <CardContent className="grid gap-3 sm:grid-cols-3">
          <div className="rounded-lg border border-zinc-800 bg-zinc-950 px-4 py-3">
            <p className="text-xs uppercase tracking-[0.14em] text-zinc-500">Total Cycles</p>
            <p className="mt-2 text-2xl font-semibold text-white">{cycles.length}</p>
          </div>
          <div className="rounded-lg border border-zinc-800 bg-zinc-950 px-4 py-3">
            <p className="text-xs uppercase tracking-[0.14em] text-zinc-500">Active Cycles</p>
            <p className="mt-2 text-2xl font-semibold text-emerald-400">{activeCycles}</p>
          </div>
          <div className="rounded-lg border border-zinc-800 bg-zinc-950 px-4 py-3">
            <p className="text-xs uppercase tracking-[0.14em] text-zinc-500">Entries This Month</p>
            <p className="mt-2 text-2xl font-semibold text-cyan-300">
              {monthSummaryQuery.data?.totalEntries ?? 0}
            </p>
          </div>
        </CardContent>
      </Card>

      <Card className="border-zinc-800 bg-zinc-900/50">
        <CardHeader>
          <CardTitle>Monthly Activity</CardTitle>
        </CardHeader>
        <CardContent>
          {monthSummaryQuery.isLoading ? (
            <p className="text-sm text-zinc-500">Loading cycle activity...</p>
          ) : monthSummaryQuery.isError ? (
            <p className="text-sm text-zinc-500">
              Cycle month summaries are not available yet.
            </p>
          ) : (
            <div className="max-w-xs">
              <HeatmapCalendar data={monthSummaryQuery.data?.days ?? []} year={year} month={month} />
            </div>
          )}
        </CardContent>
      </Card>

      <Card className="border-zinc-800 bg-zinc-900/50">
        <CardHeader>
          <CardTitle>My Cycles</CardTitle>
        </CardHeader>
        <CardContent>
          {cyclesQuery.isLoading ? (
            <p className="text-sm text-zinc-500">Loading your cycles...</p>
          ) : cyclesQuery.isError ? (
            <p className="text-sm text-zinc-500">
              Cycle endpoints are still syncing. Check back shortly.
            </p>
          ) : cycles.length === 0 ? (
            <div className="space-y-3">
              <p className="text-sm text-zinc-400">
                No cycles logged yet. Start one here and the status tiles above will update immediately.
              </p>
              <Button
                variant="outline"
                className="border-zinc-700 text-zinc-200 hover:text-white"
                onClick={() => setCycleDialogOpen(true)}
              >
                Create Your First Cycle
              </Button>
            </div>
          ) : (
            <ul className="space-y-3">
              {cycles.map((cycle) => (
                <li key={cycle._id} className="rounded-lg border border-zinc-800 bg-zinc-950 px-4 py-3">
                  <div className="flex flex-wrap items-center justify-between gap-2">
                    <p className="text-sm font-medium text-white">{cycle.name}</p>
                    <Badge variant="outline" className={statusBadgeClass(cycle.status)}>
                      {cycle.status}
                    </Badge>
                  </div>
                  <p className="mt-1 text-xs uppercase tracking-[0.14em] text-zinc-500">{cycle.type}</p>
                  <p className="mt-2 text-xs text-zinc-400">{formatCycleWindow(cycle)}</p>
                </li>
              ))}
            </ul>
          )}
        </CardContent>
      </Card>

      <CreateCycleDialog open={isCycleDialogOpen} onOpenChange={setCycleDialogOpen} />
      <MedicationDoseDialog
        open={isMedicationDialogOpen}
        onOpenChange={setMedicationDialogOpen}
      />
    </div>
  );
}
