import mongoose, { Schema, Document, Types } from 'mongoose';

// ECGRecord — lightweight metadata for a single on-device ECG recording.
//
// Full waveform samples are NOT stored server-side. At 512 Hz × 30 s a
// recording is ~15k samples; that's too much per-row for a metric we can
// fetch on-demand from the phone when a user opens a detail view. The
// on-device archive + HealthKit are the canonical home for the waveform.
//
// Indexed on (userId, recordedAt desc) for history-list queries.

export type ECGRhythm =
  | 'sinusRhythm'
  | 'sinusBradycardia'
  | 'sinusTachycardia'
  | 'atrialFibrillation'
  | 'atrialFlutter'
  | 'firstDegreeAVBlock'
  | 'mobitzI'
  | 'mobitzII'
  | 'completeHeartBlock'
  | 'pvc'
  | 'pac'
  | 'ventricularTachycardia'
  | 'supraventricularTachycardia'
  | 'indeterminate';

export type ECGAnomalyKind = 'pvc' | 'pac' | 'pause' | 'droppedBeat' | 'wideQRS';

export interface IECGAnomaly {
  kind: ECGAnomalyKind;
  count?: number;
  durationMs?: number;
  percentage?: number;
}

export interface IECGClassification {
  rhythm: ECGRhythm;
  heartRate: number;
  confidence: number;
  anomalies: IECGAnomaly[];
  clinicalNote?: string;
}

export interface IECGRecord extends Document {
  _id: Types.ObjectId;
  userId: Types.ObjectId;
  recordedAt: Date;
  durationSec: number;
  sampleCount: number;
  leadLabel: string;
  classification: IECGClassification;
  createdAt: Date;
  updatedAt: Date;
}

const ECGAnomalySchema = new Schema<IECGAnomaly>(
  {
    kind: {
      type: String,
      enum: ['pvc', 'pac', 'pause', 'droppedBeat', 'wideQRS'],
      required: true,
    },
    count: { type: Number },
    durationMs: { type: Number },
    percentage: { type: Number },
  },
  { _id: false },
);

const ECGClassificationSchema = new Schema<IECGClassification>(
  {
    rhythm: {
      type: String,
      enum: [
        'sinusRhythm',
        'sinusBradycardia',
        'sinusTachycardia',
        'atrialFibrillation',
        'atrialFlutter',
        'firstDegreeAVBlock',
        'mobitzI',
        'mobitzII',
        'completeHeartBlock',
        'pvc',
        'pac',
        'ventricularTachycardia',
        'supraventricularTachycardia',
        'indeterminate',
      ],
      required: true,
    },
    heartRate: { type: Number, required: true, min: 0, max: 300 },
    confidence: { type: Number, required: true, min: 0, max: 1 },
    anomalies: { type: [ECGAnomalySchema], default: [] },
    clinicalNote: { type: String, default: '' },
  },
  { _id: false },
);

const ECGRecordSchema = new Schema<IECGRecord>(
  {
    userId: { type: Schema.Types.ObjectId, ref: 'User', required: true },
    recordedAt: { type: Date, required: true },
    durationSec: { type: Number, required: true, min: 0, max: 600 },
    sampleCount: { type: Number, required: true, min: 0 },
    leadLabel: { type: String, default: 'Lead I' },
    classification: { type: ECGClassificationSchema, required: true },
  },
  { timestamps: true },
);

ECGRecordSchema.index({ userId: 1, recordedAt: -1 });

export const ECGRecord = mongoose.model<IECGRecord>('ECGRecord', ECGRecordSchema);
