import mongoose, { Schema, Document, Types } from 'mongoose';

export interface IStoreCategory extends Document {
  _id: Types.ObjectId;
  name: string;
  slug: string;
  active: boolean;
  sortOrder: number;
  createdAt: Date;
  updatedAt: Date;
}

const StoreCategorySchema = new Schema<IStoreCategory>(
  {
    name: { type: String, required: true },
    slug: { type: String, required: true },
    active: { type: Boolean, default: true },
    sortOrder: { type: Number, default: 0 },
  },
  { timestamps: true }
);

StoreCategorySchema.index({ slug: 1 }, { unique: true });
StoreCategorySchema.index({ active: 1, sortOrder: 1 });

export const StoreCategory = mongoose.model<IStoreCategory>(
  'StoreCategory',
  StoreCategorySchema
);
