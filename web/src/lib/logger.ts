type LogLevel = 'debug' | 'info' | 'warn' | 'error';

type LogContext = Record<string, unknown>;

declare global {
  interface Window {
    __GEARSNITCH_LOG_BUFFER__?: Array<{
      ts: string;
      level: LogLevel;
      message: string;
      context: LogContext;
    }>;
  }
}

const LOG_PREFIX = '[GearSnitchWeb]';
const MAX_BUFFERED_LOGS = 200;
const CLIENT_LOG_URL = `${import.meta.env.VITE_API_URL || 'http://localhost:3001/api/v1'}/client-logs`;

function consoleMethod(level: LogLevel): 'debug' | 'info' | 'warn' | 'error' {
  return level;
}

function serializeReason(reason: unknown): unknown {
  if (reason instanceof Error) {
    return {
      name: reason.name,
      message: reason.message,
      stack: reason.stack,
    };
  }

  if (typeof reason === 'object' && reason !== null) {
    return reason;
  }

  return String(reason);
}

function emit(level: LogLevel, message: string, context: LogContext = {}) {
  const entry = {
    ts: new Date().toISOString(),
    level,
    message,
    context,
  };

  if (typeof window !== 'undefined') {
    window.__GEARSNITCH_LOG_BUFFER__ ??= [];
    window.__GEARSNITCH_LOG_BUFFER__!.push(entry);
    if (window.__GEARSNITCH_LOG_BUFFER__!.length > MAX_BUFFERED_LOGS) {
      window.__GEARSNITCH_LOG_BUFFER__!.shift();
    }
  }

  if (level === 'warn' || level === 'error') {
    forwardClientLog(entry);
  }

  console[consoleMethod(level)](LOG_PREFIX, entry);
}

function forwardClientLog(entry: {
  ts: string;
  level: LogLevel;
  message: string;
  context: LogContext;
}) {
  if (typeof window === 'undefined') {
    return;
  }

  const payload = JSON.stringify(entry);

  try {
    if (typeof navigator !== 'undefined' && typeof navigator.sendBeacon === 'function') {
      const blob = new Blob([payload], { type: 'application/json' });
      if (navigator.sendBeacon(CLIENT_LOG_URL, blob)) {
        return;
      }
    }

    void fetch(CLIENT_LOG_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: payload,
      keepalive: true,
    }).catch(() => undefined);
  } catch {
    // Never recurse by logging failures from the log forwarder itself.
  }
}

export const webLogger = {
  debug(message: string, context?: LogContext) {
    emit('debug', message, context);
  },
  info(message: string, context?: LogContext) {
    emit('info', message, context);
  },
  warn(message: string, context?: LogContext) {
    emit('warn', message, context);
  },
  error(message: string, context?: LogContext) {
    emit('error', message, context);
  },
};

export function installGlobalWebErrorLogging() {
  if (typeof window === 'undefined') {
    return;
  }

  window.addEventListener('error', (event) => {
    webLogger.error('Unhandled window error', {
      message: event.message,
      source: event.filename,
      line: event.lineno,
      column: event.colno,
      error: serializeReason(event.error),
    });
  });

  window.addEventListener('unhandledrejection', (event) => {
    webLogger.error('Unhandled promise rejection', {
      reason: serializeReason(event.reason),
    });
  });
}

export function createRequestId(): string {
  if (typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function') {
    return crypto.randomUUID();
  }

  return `web-${Date.now()}-${Math.random().toString(16).slice(2)}`;
}
