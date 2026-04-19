import { ThemeProvider as NextThemesProvider } from 'next-themes';
import { MoonIcon, SunIcon } from 'lucide-react';
import { useSyncExternalStore, type ReactNode } from 'react';
import { Button } from '@/components/ui/button';
import { cn } from '@/lib/utils';
import { useTheme } from '@/lib/use-theme';

/**
 * Theme storage key + provider.
 *
 * The dark-mode variant in `index.css` is keyed to the `.dark` class on the
 * root element. An inline bootstrap script in `index.html` reads this same key
 * before React mounts to avoid a flash-of-wrong-theme (FOUC). Keep in sync.
 *
 * Default is "dark" to preserve the current brand look — users on light-mode
 * systems still land on the dark theme unless they explicitly toggle.
 */
const STORAGE_KEY = 'gearsnitch.theme';

export function ThemeProvider({ children }: { children: ReactNode }) {
  return (
    <NextThemesProvider
      attribute="class"
      defaultTheme="dark"
      enableSystem
      storageKey={STORAGE_KEY}
      disableTransitionOnChange
      themes={['light', 'dark']}
    >
      {children}
    </NextThemesProvider>
  );
}

// Mount subscription — avoids calling setState inside an effect.
const subscribeMount = (notify: () => void) => {
  const handle = requestAnimationFrame(notify);
  return () => cancelAnimationFrame(handle);
};
const getMountSnapshot = () => true;
const getServerMountSnapshot = () => false;

function useMounted(): boolean {
  return useSyncExternalStore(subscribeMount, getMountSnapshot, getServerMountSnapshot);
}

/**
 * Small icon button that flips between light and dark.
 * Renders a placeholder of identical size before mount to avoid layout shift
 * / hydration mismatch while next-themes resolves the active theme.
 */
export function ThemeToggle({ className }: { className?: string }) {
  const { theme, resolvedTheme, setTheme } = useTheme();
  const mounted = useMounted();

  if (!mounted) {
    return (
      <span
        className={cn(
          'inline-flex h-8 w-8 items-center justify-center rounded-md',
          className,
        )}
        aria-hidden="true"
      />
    );
  }

  const current = theme === 'system' ? resolvedTheme : theme;
  const nextTheme = current === 'dark' ? 'light' : 'dark';
  const label = `Switch to ${nextTheme} mode`;

  return (
    <Button
      type="button"
      variant="ghost"
      size="icon-sm"
      aria-label={label}
      title={label}
      onClick={() => setTheme(nextTheme)}
      className={cn(
        'text-zinc-400 hover:text-foreground focus-visible:ring-ring',
        className,
      )}
    >
      {current === 'dark' ? (
        <SunIcon className="size-4" aria-hidden="true" />
      ) : (
        <MoonIcon className="size-4" aria-hidden="true" />
      )}
      <span className="sr-only">{label}</span>
    </Button>
  );
}
