import { useMemo } from 'react';

export interface RoutePoint {
  latitude: number;
  longitude: number;
}

export interface RouteBounds {
  minLatitude: number;
  maxLatitude: number;
  minLongitude: number;
  maxLongitude: number;
}

interface RunRoutePreviewProps {
  points?: RoutePoint[];
  bounds?: RouteBounds | null;
  status?: 'active' | 'completed';
  className?: string;
}

interface ProjectedPath {
  polyline: string;
  start?: { x: number; y: number };
  end?: { x: number; y: number };
}

const WIDTH = 960;
const HEIGHT = 560;
const PADDING = 52;

function computeBounds(points: RoutePoint[]): RouteBounds | null {
  if (points.length === 0) {
    return null;
  }

  let minLatitude = points[0].latitude;
  let maxLatitude = points[0].latitude;
  let minLongitude = points[0].longitude;
  let maxLongitude = points[0].longitude;

  for (const point of points) {
    minLatitude = Math.min(minLatitude, point.latitude);
    maxLatitude = Math.max(maxLatitude, point.latitude);
    minLongitude = Math.min(minLongitude, point.longitude);
    maxLongitude = Math.max(maxLongitude, point.longitude);
  }

  return {
    minLatitude,
    maxLatitude,
    minLongitude,
    maxLongitude,
  };
}

function buildPath(points: RoutePoint[], bounds: RouteBounds): ProjectedPath | null {
  if (points.length === 0) {
    return null;
  }

  const latitudeSpan = Math.max(bounds.maxLatitude - bounds.minLatitude, 0.0005);
  const longitudeSpan = Math.max(bounds.maxLongitude - bounds.minLongitude, 0.0005);
  const usableWidth = WIDTH - PADDING * 2;
  const usableHeight = HEIGHT - PADDING * 2;
  const scale = Math.min(usableWidth / longitudeSpan, usableHeight / latitudeSpan);
  const drawnWidth = longitudeSpan * scale;
  const drawnHeight = latitudeSpan * scale;
  const offsetX = (WIDTH - drawnWidth) / 2;
  const offsetY = (HEIGHT - drawnHeight) / 2;

  const project = (point: RoutePoint) => ({
    x: offsetX + (point.longitude - bounds.minLongitude) * scale,
    y: HEIGHT - (offsetY + (point.latitude - bounds.minLatitude) * scale),
  });

  const projected = points.map(project);
  return {
    polyline: projected.map((point) => `${point.x},${point.y}`).join(' '),
    start: projected[0],
    end: projected[projected.length - 1],
  };
}

export default function RunRoutePreview({
  points = [],
  bounds,
  status = 'completed',
  className,
}: RunRoutePreviewProps) {
  const resolvedBounds = useMemo(() => bounds ?? computeBounds(points), [bounds, points]);
  const projected = useMemo(
    () => (resolvedBounds ? buildPath(points, resolvedBounds) : null),
    [points, resolvedBounds],
  );

  if (!points.length || !projected) {
    return (
      <div
        className={[
          'relative overflow-hidden rounded-3xl border border-white/8 bg-zinc-950/80',
          className ?? '',
        ].join(' ')}
      >
        <div className="absolute inset-0 bg-[radial-gradient(circle_at_top,_rgba(34,211,238,0.16),_transparent_42%),radial-gradient(circle_at_bottom_right,_rgba(16,185,129,0.14),_transparent_38%)]" />
        <div className="relative flex aspect-[16/10] items-center justify-center px-8 text-center">
          <div>
            <p className="text-sm font-medium uppercase tracking-[0.24em] text-zinc-500">Route Preview</p>
            <p className="mt-3 text-sm text-zinc-400">
              GPS points will appear here after the run syncs completed route data.
            </p>
          </div>
        </div>
      </div>
    );
  }

  return (
    <div
      className={[
        'relative overflow-hidden rounded-3xl border border-white/8 bg-zinc-950/80',
        className ?? '',
      ].join(' ')}
    >
      <div className="absolute inset-0 bg-[radial-gradient(circle_at_top_left,_rgba(34,211,238,0.18),_transparent_34%),radial-gradient(circle_at_bottom_right,_rgba(16,185,129,0.14),_transparent_36%)]" />
      <div className="absolute inset-0 bg-[linear-gradient(to_right,rgba(255,255,255,0.04)_1px,transparent_1px),linear-gradient(to_bottom,rgba(255,255,255,0.04)_1px,transparent_1px)] bg-[size:72px_72px]" />
      <div className="absolute inset-x-0 top-0 h-px bg-gradient-to-r from-transparent via-cyan-400/60 to-transparent" />
      <div className="relative aspect-[16/10]">
        <svg
          viewBox={`0 0 ${WIDTH} ${HEIGHT}`}
          className="h-full w-full"
          role="img"
          aria-label="Run route preview"
        >
          <defs>
            <linearGradient id="route-stroke" x1="0%" y1="0%" x2="100%" y2="100%">
              <stop offset="0%" stopColor="#22d3ee" />
              <stop offset="100%" stopColor="#10b981" />
            </linearGradient>
            <filter id="route-glow">
              <feGaussianBlur stdDeviation="8" result="blur" />
              <feMerge>
                <feMergeNode in="blur" />
                <feMergeNode in="SourceGraphic" />
              </feMerge>
            </filter>
          </defs>
          <polyline
            points={projected.polyline}
            fill="none"
            stroke="url(#route-stroke)"
            strokeWidth="18"
            strokeLinecap="round"
            strokeLinejoin="round"
            opacity="0.24"
            filter="url(#route-glow)"
          />
          <polyline
            points={projected.polyline}
            fill="none"
            stroke="url(#route-stroke)"
            strokeWidth="7"
            strokeLinecap="round"
            strokeLinejoin="round"
          />
          {projected.start ? (
            <>
              <circle cx={projected.start.x} cy={projected.start.y} r="14" fill="#09090b" stroke="#22d3ee" strokeWidth="4" />
              <circle cx={projected.start.x} cy={projected.start.y} r="5" fill="#22d3ee" />
            </>
          ) : null}
          {projected.end ? (
            <>
              <circle
                cx={projected.end.x}
                cy={projected.end.y}
                r="16"
                fill="#09090b"
                stroke={status === 'active' ? '#f59e0b' : '#10b981'}
                strokeWidth="4"
              />
              <circle cx={projected.end.x} cy={projected.end.y} r="6" fill={status === 'active' ? '#f59e0b' : '#10b981'} />
            </>
          ) : null}
        </svg>

        <div className="absolute left-4 top-4 rounded-full border border-white/10 bg-black/55 px-3 py-1.5 text-[11px] uppercase tracking-[0.24em] text-zinc-300 backdrop-blur">
          {status === 'active' ? 'Live Route' : 'Captured Route'}
        </div>
      </div>
    </div>
  );
}
