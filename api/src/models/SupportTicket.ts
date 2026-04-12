import mongoose, { Schema, Document, Types } from 'mongoose';

export interface ISupportTicket extends Document {
  _id: Types.ObjectId;
  userId: Types.ObjectId | null;
  name: string;
  email: string;
  subject: string;
  message: string;
  status: 'open' | 'resolved' | 'closed';
  source: 'web' | 'ios' | 'email';
  createdAt: Date;
  updatedAt: Date;
}

const SupportTicketSchema = new Schema<ISupportTicket>(
  {
    userId: { type: Schema.Types.ObjectId, ref: 'User', default: null },
    name: { type: String, required: true },
    email: { type: String, required: true },
    subject: { type: String, required: true },
    message: { type: String, required: true },
    status: {
      type: String,
      enum: ['open', 'resolved', 'closed'],
      default: 'open',
    },
    source: {
      type: String,
      enum: ['web', 'ios', 'email'],
      default: 'web',
    },
  },
  { timestamps: true },
);

SupportTicketSchema.index({ userId: 1, createdAt: -1 });
SupportTicketSchema.index({ email: 1, createdAt: -1 });
SupportTicketSchema.index({ status: 1, createdAt: -1 });

export const SupportTicket = mongoose.model<ISupportTicket>(
  'SupportTicket',
  SupportTicketSchema,
);
