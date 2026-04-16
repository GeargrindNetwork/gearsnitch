import mongoose, { Schema, Document, Types } from 'mongoose';

export interface IContent extends Document {
  _id: Types.ObjectId;
  slug: string;
  type: 'article' | 'tip' | 'legal' | 'featured';
  title: string;
  body: string;
  summary?: string;
  imageUrl?: string;
  published: boolean;
  publishedAt?: Date;
  tags: string[];
  sortOrder: number;
  createdAt: Date;
  updatedAt: Date;
}

const ContentSchema = new Schema<IContent>(
  {
    slug: { type: String, required: true, unique: true, trim: true },
    type: {
      type: String,
      enum: ['article', 'tip', 'legal', 'featured'],
      required: true,
    },
    title: { type: String, required: true, trim: true },
    body: { type: String, required: true },
    summary: { type: String, trim: true },
    imageUrl: { type: String },
    published: { type: Boolean, default: false },
    publishedAt: { type: Date },
    tags: [{ type: String, trim: true }],
    sortOrder: { type: Number, default: 0 },
  },
  { timestamps: true }
);

ContentSchema.index({ type: 1, published: 1, sortOrder: 1 });
ContentSchema.index({ slug: 1 }, { unique: true });

export const Content = mongoose.model<IContent>('Content', ContentSchema);
