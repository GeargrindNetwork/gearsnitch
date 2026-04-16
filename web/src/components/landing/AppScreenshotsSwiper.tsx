import { useState, useEffect, useRef, type TouchEvent } from 'react';
import { Button } from '@/components/ui/button';

interface Screenshot {
  src: string;
  title: string;
  caption: string;
}

const SCREENSHOTS: Screenshot[] = [
  {
    src: '/screenshots/01-welcome.png',
    title: 'Welcome to GearSnitch',
    caption: 'Bluetooth gear monitoring, instant disconnect alerts, and gym-aware tracking — all in one app.',
  },
  {
    src: '/screenshots/02-signin.png',
    title: 'Sign in seamlessly',
    caption: 'Continue with Apple or Google. Your account syncs across iPhone, Apple Watch, and the web.',
  },
  {
    src: '/screenshots/03-location.png',
    title: 'Gym-aware tracking',
    caption: 'Location triggers automatic disconnect protection the moment you arrive at the gym.',
  },
];

export default function AppScreenshotsSwiper() {
  const [index, setIndex] = useState(0);
  const [autoplay, setAutoplay] = useState(true);
  const touchStartX = useRef<number | null>(null);

  const next = () => setIndex((i) => (i + 1) % SCREENSHOTS.length);
  const prev = () => setIndex((i) => (i - 1 + SCREENSHOTS.length) % SCREENSHOTS.length);

  // Autoplay every 5s, pause when user interacts
  useEffect(() => {
    if (!autoplay) return;
    const id = setInterval(next, 5000);
    return () => clearInterval(id);
  }, [autoplay]);

  const handleTouchStart = (e: TouchEvent) => {
    touchStartX.current = e.touches[0].clientX;
    setAutoplay(false);
  };

  const handleTouchEnd = (e: TouchEvent) => {
    if (touchStartX.current === null) return;
    const delta = e.changedTouches[0].clientX - touchStartX.current;
    if (delta > 40) prev();
    else if (delta < -40) next();
    touchStartX.current = null;
  };

  const current = SCREENSHOTS[index];

  return (
    <section
      className="relative overflow-hidden bg-zinc-950 py-16 sm:py-24"
      aria-label="App screenshots"
    >
      <div className="pointer-events-none absolute inset-0 bg-[radial-gradient(circle_at_top,_rgba(34,211,238,0.12),_transparent_50%)]" />

      <div className="relative mx-auto max-w-6xl px-4 sm:px-6 lg:px-8">
        <div className="mb-10 text-center">
          <h2 className="text-3xl font-bold text-white sm:text-4xl">See it in action</h2>
          <p className="mt-3 text-sm text-zinc-400 sm:text-base">
            Swipe or use the arrows to see GearSnitch on iPhone.
          </p>
        </div>

        <div className="flex items-center justify-center gap-4 sm:gap-8">
          {/* Prev arrow — hidden on small screens */}
          <Button
            variant="outline"
            size="icon"
            className="hidden h-12 w-12 shrink-0 rounded-full border-zinc-700 bg-zinc-900/70 text-zinc-300 hover:bg-zinc-800 sm:flex"
            onClick={() => { prev(); setAutoplay(false); }}
            aria-label="Previous screenshot"
          >
            <svg className="h-5 w-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
              <path d="M15 18l-6-6 6-6" />
            </svg>
          </Button>

          {/* Phone frame + screenshot */}
          <div
            className="relative flex-shrink-0"
            onTouchStart={handleTouchStart}
            onTouchEnd={handleTouchEnd}
          >
            <div className="relative mx-auto w-[260px] sm:w-[300px]">
              {/* Device frame shadow */}
              <div className="absolute inset-0 rounded-[2.5rem] bg-gradient-to-br from-cyan-400/20 to-emerald-400/20 blur-2xl" />

              {/* Phone bezel */}
              <div className="relative overflow-hidden rounded-[2.5rem] border-[10px] border-zinc-800 bg-black shadow-2xl">
                <img
                  key={current.src}
                  src={current.src}
                  alt={current.title}
                  className="block w-full animate-[fadeIn_0.4s_ease-out]"
                  loading="lazy"
                />
              </div>
            </div>
          </div>

          {/* Next arrow */}
          <Button
            variant="outline"
            size="icon"
            className="hidden h-12 w-12 shrink-0 rounded-full border-zinc-700 bg-zinc-900/70 text-zinc-300 hover:bg-zinc-800 sm:flex"
            onClick={() => { next(); setAutoplay(false); }}
            aria-label="Next screenshot"
          >
            <svg className="h-5 w-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
              <path d="M9 18l6-6-6-6" />
            </svg>
          </Button>
        </div>

        {/* Caption */}
        <div className="mt-8 text-center">
          <h3 className="text-xl font-semibold text-white">{current.title}</h3>
          <p className="mx-auto mt-2 max-w-lg text-sm text-zinc-400">{current.caption}</p>
        </div>

        {/* Pagination dots */}
        <div className="mt-6 flex justify-center gap-2">
          {SCREENSHOTS.map((_, i) => (
            <button
              key={i}
              onClick={() => { setIndex(i); setAutoplay(false); }}
              className={`h-2 rounded-full transition-all ${
                i === index ? 'w-8 bg-emerald-400' : 'w-2 bg-zinc-700 hover:bg-zinc-600'
              }`}
              aria-label={`Go to screenshot ${i + 1}`}
            />
          ))}
        </div>

        {/* Mobile-only arrow controls */}
        <div className="mt-6 flex justify-center gap-4 sm:hidden">
          <Button
            variant="outline"
            size="sm"
            className="border-zinc-700 bg-zinc-900/70 text-zinc-300"
            onClick={() => { prev(); setAutoplay(false); }}
          >
            &#8592; Previous
          </Button>
          <Button
            variant="outline"
            size="sm"
            className="border-zinc-700 bg-zinc-900/70 text-zinc-300"
            onClick={() => { next(); setAutoplay(false); }}
          >
            Next &#8594;
          </Button>
        </div>
      </div>

      <style>{`
        @keyframes fadeIn {
          from { opacity: 0; transform: translateY(6px); }
          to { opacity: 1; transform: translateY(0); }
        }
      `}</style>
    </section>
  );
}
