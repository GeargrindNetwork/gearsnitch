import { Router, type Request, type Response } from 'express';
import { Types } from 'mongoose';
import { z } from 'zod';
import { StatusCodes } from 'http-status-codes';
import { isAuthenticated, type JwtPayload } from '../../middleware/auth.js';
import { validateBody } from '../../middleware/validate.js';
import { successResponse, errorResponse } from '../../utils/response.js';
import { ECGRecord, type ECGRhythm, type ECGAnomalyKind } from './model.js';

// ECG metadata API. Stores summary fields only — the raw waveform lives on
// device (and in HealthKit where Apple allows). See module.ts header for the
// storage rationale.

const router = Router();

const RHYTHMS = [
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
] as const satisfies readonly ECGRhythm[];

const ANOMALY_KINDS = [
  'pvc',
  'pac',
  'pause',
  'droppedBeat',
  'wideQRS',
] as const satisfies readonly ECGAnomalyKind[];

const anomalySchema = z.object({
  kind: z.enum(ANOMALY_KINDS),
  count: z.number().int().min(0).max(1000).optional(),
  durationMs: z.number().min(0).max(60_000).optional(),
  percentage: z.number().min(0).max(1).optional(),
});

const classificationSchema = z.object({
  rhythm: z.enum(RHYTHMS),
  heartRate: z.number().int().min(0).max(300),
  confidence: z.number().min(0).max(1),
  anomalies: z.array(anomalySchema).max(50).default([]),
  clinicalNote: z.string().max(1000).optional().default(''),
});

const createRecordSchema = z.object({
  recordedAt: z.string().datetime(),
  durationSec: z.number().min(0).max(600),
  sampleCount: z.number().int().min(0).max(1_000_000),
  leadLabel: z.string().max(32).optional().default('Lead I'),
  classification: classificationSchema,
});

function serialize(record: Record<string, any>) {
  return {
    _id: String(record._id),
    userId: String(record.userId),
    recordedAt: record.recordedAt?.toISOString?.() ?? record.recordedAt,
    durationSec: record.durationSec,
    sampleCount: record.sampleCount,
    leadLabel: record.leadLabel,
    classification: {
      rhythm: record.classification?.rhythm,
      heartRate: record.classification?.heartRate,
      confidence: record.classification?.confidence,
      anomalies: record.classification?.anomalies ?? [],
      clinicalNote: record.classification?.clinicalNote ?? '',
    },
    createdAt: record.createdAt?.toISOString?.() ?? record.createdAt,
    updatedAt: record.updatedAt?.toISOString?.() ?? record.updatedAt,
  };
}

// POST /api/v1/ecg/records — create new metadata record
router.post(
  '/records',
  isAuthenticated,
  validateBody(createRecordSchema),
  async (req: Request, res: Response) => {
    try {
      const user = req.user as JwtPayload;
      const body = req.body as z.infer<typeof createRecordSchema>;
      const doc = await ECGRecord.create({
        userId: new Types.ObjectId(user.sub),
        recordedAt: new Date(body.recordedAt),
        durationSec: body.durationSec,
        sampleCount: body.sampleCount,
        leadLabel: body.leadLabel,
        classification: body.classification,
      });
      successResponse(res, serialize(doc.toObject()), StatusCodes.CREATED);
    } catch (err) {
      errorResponse(
        res,
        StatusCodes.INTERNAL_SERVER_ERROR,
        'Failed to create ECG record',
        (err as Error).message,
      );
    }
  },
);

// GET /api/v1/ecg/records — history list (paginated)
router.get('/records', isAuthenticated, async (req: Request, res: Response) => {
  try {
    const user = req.user as JwtPayload;
    const page = Math.max(1, parseInt(req.query.page as string, 10) || 1);
    const limit = Math.min(100, Math.max(1, parseInt(req.query.limit as string, 10) || 25));
    const skip = (page - 1) * limit;

    const filter = { userId: new Types.ObjectId(user.sub) };
    const [records, total] = await Promise.all([
      ECGRecord.find(filter).sort({ recordedAt: -1 }).skip(skip).limit(limit).lean(),
      ECGRecord.countDocuments(filter),
    ]);

    successResponse(
      res,
      records.map(serialize),
      StatusCodes.OK,
      { page, limit, total, totalPages: Math.ceil(total / limit) },
    );
  } catch (err) {
    errorResponse(
      res,
      StatusCodes.INTERNAL_SERVER_ERROR,
      'Failed to load ECG records',
      (err as Error).message,
    );
  }
});

// GET /api/v1/ecg/records/:id — single record (user-scoped)
router.get('/records/:id', isAuthenticated, async (req: Request, res: Response) => {
  try {
    const user = req.user as JwtPayload;
    const id = String(req.params.id);
    if (!Types.ObjectId.isValid(id)) {
      errorResponse(res, StatusCodes.BAD_REQUEST, 'Invalid ECG record id');
      return;
    }
    const record = await ECGRecord.findOne({
      _id: new Types.ObjectId(id),
      userId: new Types.ObjectId(user.sub),
    }).lean();
    if (!record) {
      errorResponse(res, StatusCodes.NOT_FOUND, 'ECG record not found');
      return;
    }
    successResponse(res, serialize(record));
  } catch (err) {
    errorResponse(
      res,
      StatusCodes.INTERNAL_SERVER_ERROR,
      'Failed to load ECG record',
      (err as Error).message,
    );
  }
});

// DELETE /api/v1/ecg/records/:id
router.delete('/records/:id', isAuthenticated, async (req: Request, res: Response) => {
  try {
    const user = req.user as JwtPayload;
    const id = String(req.params.id);
    if (!Types.ObjectId.isValid(id)) {
      errorResponse(res, StatusCodes.BAD_REQUEST, 'Invalid ECG record id');
      return;
    }
    const deleted = await ECGRecord.findOneAndDelete({
      _id: new Types.ObjectId(id),
      userId: new Types.ObjectId(user.sub),
    });
    if (!deleted) {
      errorResponse(res, StatusCodes.NOT_FOUND, 'ECG record not found');
      return;
    }
    successResponse(res, { deleted: true });
  } catch (err) {
    errorResponse(
      res,
      StatusCodes.INTERNAL_SERVER_ERROR,
      'Failed to delete ECG record',
      (err as Error).message,
    );
  }
});

export default router;
