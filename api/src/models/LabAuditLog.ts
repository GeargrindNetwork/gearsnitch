import mongoose, { Schema, Document, Types } from 'mongoose';

/**
 * LabAuditLog — HIPAA-style access log for every /api/v1/labs/* hit.
 *
 * Stored fields are deliberately metadata-only: user, route, method, ip,
 * UA, status, timestamp, optional orderId. NO request/response bodies,
 * NO patient names, NO test results. The middleware that writes these
 * entries is responsible for enforcing that discipline at the source.
 *
 * Retention is left to a future data-lifecycle PR (HIPAA guidance: 6
 * years). A TTL index is intentionally NOT applied here.
 */
export interface ILabAuditLog extends Document {
  _id: Types.ObjectId;
  userId?: Types.ObjectId;
  /** Route template or raw path — e.g. "/api/v1/labs/tests". Never PHI. */
  route: string;
  method: string;
  /** Provider-issued order id, if the request touches a specific order. */
  orderId?: string;
  /** Configured LAB_PROVIDER at the time of the request. */
  providerId?: string;
  /** Remote IP (may be X-Forwarded-For when trust-proxy is set). */
  ip?: string;
  userAgent?: string;
  /** HTTP status written back to the client. */
  statusCode?: number;
  /** Correlation id — shared with the request logger. */
  requestId?: string;
  /** Wall clock when the request was received. */
  createdAt: Date;
  updatedAt: Date;
}

const LabAuditLogSchema = new Schema<ILabAuditLog>(
  {
    userId: { type: Schema.Types.ObjectId, ref: 'User', required: false },
    route: { type: String, required: true },
    method: { type: String, required: true },
    orderId: { type: String },
    providerId: { type: String },
    ip: { type: String },
    userAgent: { type: String },
    statusCode: { type: Number },
    requestId: { type: String },
  },
  { timestamps: true, collection: 'lab_audit_logs' },
);

LabAuditLogSchema.index({ userId: 1, createdAt: -1 });
LabAuditLogSchema.index({ orderId: 1, createdAt: -1 });

export const LabAuditLog = mongoose.model<ILabAuditLog>(
  'LabAuditLog',
  LabAuditLogSchema,
);
