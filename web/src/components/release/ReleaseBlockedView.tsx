import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';

interface ReleaseBlockedViewProps {
  title: string;
  message: string;
  currentVersion: string;
  requiredVersion?: string | null;
  releaseNotes?: string[];
  primaryActionLabel: string;
  onPrimaryAction: () => void;
  secondaryActionLabel?: string;
  onSecondaryAction?: () => void;
}

export default function ReleaseBlockedView({
  title,
  message,
  currentVersion,
  requiredVersion,
  releaseNotes = [],
  primaryActionLabel,
  onPrimaryAction,
  secondaryActionLabel,
  onSecondaryAction,
}: ReleaseBlockedViewProps) {
  return (
    <div className="min-h-screen bg-zinc-950 px-6 py-24 text-zinc-100 lg:px-8">
      <div className="mx-auto max-w-2xl">
        <Card className="border-zinc-800 bg-zinc-900/70 shadow-2xl shadow-cyan-950/20">
          <CardHeader className="space-y-3">
            <p className="text-xs font-semibold uppercase tracking-[0.24em] text-cyan-400">
              Version Gate
            </p>
            <CardTitle className="text-3xl font-semibold text-white">{title}</CardTitle>
            <p className="text-sm leading-6 text-zinc-400">{message}</p>
          </CardHeader>
          <CardContent className="space-y-6">
            <div className="grid gap-3 sm:grid-cols-2">
              <div className="rounded-2xl border border-zinc-800 bg-zinc-950/70 p-4">
                <p className="text-xs uppercase tracking-[0.2em] text-zinc-500">Current</p>
                <p className="mt-2 text-lg font-medium text-white">{currentVersion}</p>
              </div>
              <div className="rounded-2xl border border-zinc-800 bg-zinc-950/70 p-4">
                <p className="text-xs uppercase tracking-[0.2em] text-zinc-500">Required</p>
                <p className="mt-2 text-lg font-medium text-white">{requiredVersion ?? 'Latest available'}</p>
              </div>
            </div>

            {releaseNotes.length > 0 ? (
              <div className="rounded-2xl border border-zinc-800 bg-zinc-950/70 p-4">
                <p className="text-xs uppercase tracking-[0.2em] text-zinc-500">Release Notes</p>
                <ul className="mt-3 space-y-2 text-sm leading-6 text-zinc-300">
                  {releaseNotes.map((note) => (
                    <li key={note} className="flex gap-2">
                      <span className="mt-2 h-1.5 w-1.5 rounded-full bg-emerald-400" />
                      <span>{note}</span>
                    </li>
                  ))}
                </ul>
              </div>
            ) : null}

            <div className="flex flex-col gap-3 sm:flex-row">
              <Button
                className="bg-gradient-to-r from-cyan-400 to-emerald-400 text-black hover:from-cyan-300 hover:to-emerald-300"
                onClick={onPrimaryAction}
              >
                {primaryActionLabel}
              </Button>
              {secondaryActionLabel && onSecondaryAction ? (
                <Button variant="outline" className="border-zinc-700 text-zinc-200" onClick={onSecondaryAction}>
                  {secondaryActionLabel}
                </Button>
              ) : null}
            </div>
          </CardContent>
        </Card>
      </div>
    </div>
  );
}
