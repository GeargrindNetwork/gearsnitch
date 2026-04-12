import { z } from 'zod'

export const EVENT_CHANNELS = [
  'events:device-status',
  'events:alert',
  'events:subscription',
  'events:referral',
  'events:store-order',
] as const

export type EventChannel = (typeof EVENT_CHANNELS)[number]

export const runtimeEventEnvelopeSchema = z.object({
  userId: z.string().min(1),
  target: z.enum(['user', 'devices']),
  eventName: z.string().min(1),
  payload: z.record(z.unknown()),
  emittedAt: z.string().datetime().optional(),
  dedupeKey: z.string().min(1).optional(),
})

export type RuntimeEventEnvelope = z.infer<typeof runtimeEventEnvelopeSchema>

export function parseRuntimeEvent(message: string): RuntimeEventEnvelope {
  return runtimeEventEnvelopeSchema.parse(JSON.parse(message))
}

export function roomForEvent(event: RuntimeEventEnvelope): string {
  return event.target === 'devices'
    ? `devices:${event.userId}`
    : `user:${event.userId}`
}
