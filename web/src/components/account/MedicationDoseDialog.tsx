import { useQuery, useQueryClient } from '@tanstack/react-query';
import { useEffect, useState, type FormEvent } from 'react';
import { toast } from 'sonner';
import { Button } from '@/components/ui/button';
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
  createMedicationDose,
  getCycles,
  type Cycle,
  type MedicationDoseCategory,
  type MedicationDoseUnit,
} from '@/lib/api';

interface MedicationDoseDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  defaultDateKey?: string;
  defaultCycleId?: string | null;
  title?: string;
  description?: string;
  onSaved?: () => void;
}

const categoryOptions: Array<{ value: MedicationDoseCategory; label: string }> = [
  { value: 'steroid', label: 'Steroid' },
  { value: 'peptide', label: 'Peptide' },
  { value: 'oralMedication', label: 'Oral Medication' },
];

const doseUnitOptions: MedicationDoseUnit[] = ['mg', 'mcg', 'iu', 'ml', 'units'];

const fieldClassName =
  'w-full rounded-lg border border-zinc-700 bg-zinc-950 px-3 py-2 text-sm text-white outline-none transition focus:border-emerald-500';

function pad(value: number): string {
  return String(value).padStart(2, '0');
}

function toLocalDateTimeValue(date: Date): string {
  return [
    date.getFullYear(),
    pad(date.getMonth() + 1),
    pad(date.getDate()),
  ].join('-')
    + `T${pad(date.getHours())}:${pad(date.getMinutes())}`;
}

function defaultOccurredAtValue(dateKey?: string): string {
  if (dateKey) {
    return `${dateKey}T12:00`;
  }

  return toLocalDateTimeValue(new Date());
}

function dateKeyFromLocalDateTimeValue(value: string): string | null {
  const [dateKey] = value.split('T');
  return /^\d{4}-\d{2}-\d{2}$/.test(dateKey ?? '') ? dateKey : null;
}

function toIsoString(value: string): string {
  const parsed = new Date(value);
  if (Number.isNaN(parsed.getTime())) {
    throw new Error('Choose a valid date and time.');
  }

  return parsed.toISOString();
}

export default function MedicationDoseDialog({
  open,
  onOpenChange,
  defaultDateKey,
  defaultCycleId = null,
  title = 'Log Medication',
  description = 'Create a medication dose entry that will appear in your yearly graph and calendar overlays.',
  onSaved,
}: MedicationDoseDialogProps) {
  const queryClient = useQueryClient();
  const cyclesQuery = useQuery({
    queryKey: ['cycles', 'dialog-options'],
    queryFn: getCycles,
    enabled: open,
    retry: false,
  });

  const [cycleId, setCycleId] = useState<string>(defaultCycleId ?? '');
  const [category, setCategory] = useState<MedicationDoseCategory>('steroid');
  const [compoundName, setCompoundName] = useState('');
  const [doseValue, setDoseValue] = useState('');
  const [doseUnit, setDoseUnit] = useState<MedicationDoseUnit>('mg');
  const [occurredAt, setOccurredAt] = useState(defaultOccurredAtValue(defaultDateKey));
  const [notes, setNotes] = useState('');
  const [isSaving, setIsSaving] = useState(false);

  useEffect(() => {
    if (!open) {
      return;
    }

    setCycleId(defaultCycleId ?? '');
    setCategory('steroid');
    setCompoundName('');
    setDoseValue('');
    setDoseUnit('mg');
    setOccurredAt(defaultOccurredAtValue(defaultDateKey));
    setNotes('');
  }, [defaultCycleId, defaultDateKey, open]);

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();

    const numericDose = Number(doseValue);
    if (!compoundName.trim()) {
      toast.error('Enter a compound name.');
      return;
    }
    if (!Number.isFinite(numericDose) || numericDose < 0) {
      toast.error('Enter a valid dose amount.');
      return;
    }

    setIsSaving(true);

    try {
      const resolvedDateKey = dateKeyFromLocalDateTimeValue(occurredAt) ?? defaultDateKey;

      await createMedicationDose({
        cycleId: cycleId || null,
        dateKey: resolvedDateKey,
        category,
        compoundName: compoundName.trim(),
        dose: {
          value: numericDose,
          unit: doseUnit,
        },
        occurredAt: toIsoString(occurredAt),
        notes: notes.trim() || null,
        source: 'web',
      });

      await Promise.all([
        queryClient.invalidateQueries({ queryKey: ['medication-year-graph'] }),
        queryClient.invalidateQueries({ queryKey: ['calendar'] }),
      ]);

      toast.success('Medication dose logged.');
      onSaved?.();
      onOpenChange(false);
    } catch (error) {
      toast.error(error instanceof Error ? error.message : 'Failed to log medication.');
    } finally {
      setIsSaving(false);
    }
  }

  const cycles = cyclesQuery.data ?? [];

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="border-zinc-800 bg-zinc-900 text-zinc-100 sm:max-w-lg">
        <DialogHeader>
          <DialogTitle>{title}</DialogTitle>
          <DialogDescription className="text-zinc-400">
            {description}
          </DialogDescription>
        </DialogHeader>

        <form className="space-y-4" onSubmit={handleSubmit}>
          <div className="grid gap-4 sm:grid-cols-2">
            <div className="space-y-2">
              <Label htmlFor="medication-category">Category</Label>
              <select
                id="medication-category"
                value={category}
                onChange={(event) => setCategory(event.target.value as MedicationDoseCategory)}
                className={fieldClassName}
              >
                {categoryOptions.map((option) => (
                  <option key={option.value} value={option.value} className="bg-zinc-950">
                    {option.label}
                  </option>
                ))}
              </select>
            </div>

            <div className="space-y-2">
              <Label htmlFor="medication-cycle">Linked Cycle</Label>
              <select
                id="medication-cycle"
                value={cycleId}
                onChange={(event) => setCycleId(event.target.value)}
                className={fieldClassName}
              >
                <option value="" className="bg-zinc-950">No linked cycle</option>
                {cycles.map((cycle: Cycle) => (
                  <option key={cycle._id} value={cycle._id} className="bg-zinc-950">
                    {cycle.name}
                  </option>
                ))}
              </select>
            </div>
          </div>

          <div className="space-y-2">
            <Label htmlFor="medication-name">Compound Name</Label>
            <Input
              id="medication-name"
              value={compoundName}
              onChange={(event) => setCompoundName(event.target.value)}
              placeholder="e.g. Testosterone Cypionate"
              className="border-zinc-700 bg-zinc-950 text-white"
            />
          </div>

          <div className="grid gap-4 sm:grid-cols-[minmax(0,1fr)_140px]">
            <div className="space-y-2">
              <Label htmlFor="medication-dose">Dose</Label>
              <Input
                id="medication-dose"
                type="number"
                min="0"
                step="0.1"
                value={doseValue}
                onChange={(event) => setDoseValue(event.target.value)}
                placeholder="0"
                className="border-zinc-700 bg-zinc-950 text-white"
              />
            </div>

            <div className="space-y-2">
              <Label htmlFor="medication-unit">Unit</Label>
              <select
                id="medication-unit"
                value={doseUnit}
                onChange={(event) => setDoseUnit(event.target.value as MedicationDoseUnit)}
                className={fieldClassName}
              >
                {doseUnitOptions.map((unit) => (
                  <option key={unit} value={unit} className="bg-zinc-950">
                    {unit.toUpperCase()}
                  </option>
                ))}
              </select>
            </div>
          </div>

          <div className="space-y-2">
            <Label htmlFor="medication-occurred-at">Occurred At</Label>
            <Input
              id="medication-occurred-at"
              type="datetime-local"
              value={occurredAt}
              onChange={(event) => setOccurredAt(event.target.value)}
              className="border-zinc-700 bg-zinc-950 text-white"
            />
          </div>

          <div className="space-y-2">
            <Label htmlFor="medication-notes">Notes</Label>
            <textarea
              id="medication-notes"
              value={notes}
              onChange={(event) => setNotes(event.target.value)}
              placeholder="Optional notes, route details, or reminders"
              rows={3}
              className={fieldClassName}
            />
          </div>

          {cyclesQuery.isError ? (
            <p className="text-xs text-amber-300">
              Cycle options could not be loaded. You can still save this dose without linking it.
            </p>
          ) : null}

          <DialogFooter showCloseButton>
            <Button
              type="submit"
              className="bg-emerald-400 text-black hover:bg-emerald-300"
              disabled={isSaving}
            >
              {isSaving ? 'Saving...' : 'Save Dose'}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
