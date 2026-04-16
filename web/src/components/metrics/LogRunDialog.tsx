import { useState } from 'react';
import { useMutation, useQueryClient } from '@tanstack/react-query';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import {
  Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter,
} from '@/components/ui/dialog';
import { createRun, completeRun } from '@/lib/api';

export default function LogRunDialog({ open, onOpenChange }: { open: boolean; onOpenChange: (v: boolean) => void }) {
  const queryClient = useQueryClient();
  const [date, setDate] = useState(new Date().toISOString().slice(0, 10));
  const [startTime, setStartTime] = useState('07:00');
  const [durationMin, setDurationMin] = useState('30');
  const [distanceKm, setDistanceKm] = useState('');
  const [notes, setNotes] = useState('');
  const [error, setError] = useState<string | null>(null);

  const mutation = useMutation({
    mutationFn: async () => {
      const startedAt = new Date(`${date}T${startTime}:00`).toISOString();
      const durationSeconds = Math.round(parseFloat(durationMin) * 60);
      const endedAt = new Date(new Date(startedAt).getTime() + durationSeconds * 1000).toISOString();
      const distanceMeters = distanceKm ? parseFloat(distanceKm) * 1000 : undefined;

      const run = await createRun({ startedAt, notes: notes || undefined });
      await completeRun(run._id, { endedAt, durationSeconds, distanceMeters });
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['runs'] });
      queryClient.invalidateQueries({ queryKey: ['workout-metrics-overview'] });
      queryClient.invalidateQueries({ queryKey: ['health-trends'] });
      onOpenChange(false);
      resetForm();
    },
    onError: (err: Error) => {
      setError(err.message);
    },
  });

  const resetForm = () => {
    setDate(new Date().toISOString().slice(0, 10));
    setStartTime('07:00');
    setDurationMin('30');
    setDistanceKm('');
    setNotes('');
    setError(null);
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="border-zinc-800 bg-zinc-900 text-zinc-100">
        <DialogHeader>
          <DialogTitle>Log a Run</DialogTitle>
        </DialogHeader>

        <div className="space-y-4">
          <div className="grid grid-cols-2 gap-3">
            <div>
              <Label className="text-zinc-400">Date</Label>
              <Input type="date" value={date} onChange={e => setDate(e.target.value)} className="border-zinc-700 bg-zinc-950 text-white" />
            </div>
            <div>
              <Label className="text-zinc-400">Start Time</Label>
              <Input type="time" value={startTime} onChange={e => setStartTime(e.target.value)} className="border-zinc-700 bg-zinc-950 text-white" />
            </div>
          </div>

          <div className="grid grid-cols-2 gap-3">
            <div>
              <Label className="text-zinc-400">Duration (minutes)</Label>
              <Input type="number" min="1" value={durationMin} onChange={e => setDurationMin(e.target.value)} placeholder="30" className="border-zinc-700 bg-zinc-950 text-white" />
            </div>
            <div>
              <Label className="text-zinc-400">Distance (km)</Label>
              <Input type="number" min="0" step="0.01" value={distanceKm} onChange={e => setDistanceKm(e.target.value)} placeholder="5.0" className="border-zinc-700 bg-zinc-950 text-white" />
            </div>
          </div>

          <div>
            <Label className="text-zinc-400">Notes (optional)</Label>
            <Input value={notes} onChange={e => setNotes(e.target.value)} placeholder="Morning run, felt great" className="border-zinc-700 bg-zinc-950 text-white" />
          </div>

          {error && <p className="text-xs text-red-400">{error}</p>}
        </div>

        <DialogFooter>
          <Button variant="outline" onClick={() => onOpenChange(false)}>Cancel</Button>
          <Button className="bg-emerald-600 text-white hover:bg-emerald-700" onClick={() => mutation.mutate()} disabled={mutation.isPending || !durationMin}>
            {mutation.isPending ? 'Logging...' : 'Log Run'}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
