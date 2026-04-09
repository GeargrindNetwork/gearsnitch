import mongoose, { Schema, Document, Types } from 'mongoose';

export interface IStoreProductCompliance {
  requiresAgeConfirmation?: boolean;
  jurisdictionAllowlist?: string[];
  jurisdictionBlocklist?: string[];
  termsRequired?: boolean;
  medicalDisclaimerRequired?: boolean;
}

export interface IStoreProduct extends Document {
  _id: Types.ObjectId;
  sku: string;
  name: string;
  slug: string;
  description?: string;
  categoryId: Types.ObjectId;
  price: number;
  currency: string;
  inventory: number;
  active: boolean;
  images: string[];
  compliance: IStoreProductCompliance;
  createdAt: Date;
  updatedAt: Date;
}

const StoreProductSchema = new Schema<IStoreProduct>(
  {
    sku: { type: String, required: true },
    name: { type: String, required: true },
    slug: { type: String, required: true },
    description: { type: String },
    categoryId: {
      type: Schema.Types.ObjectId,
      ref: 'StoreCategory',
      required: true,
    },
    price: { type: Number, required: true },
    currency: { type: String, default: 'USD' },
    inventory: { type: Number, default: 0 },
    active: { type: Boolean, default: true },
    images: { type: [String], default: [] },
    compliance: {
      requiresAgeConfirmation: { type: Boolean },
      jurisdictionAllowlist: { type: [String] },
      jurisdictionBlocklist: { type: [String] },
      termsRequired: { type: Boolean },
      medicalDisclaimerRequired: { type: Boolean },
    },
  },
  { timestamps: true }
);

StoreProductSchema.index({ sku: 1 }, { unique: true });
StoreProductSchema.index({ slug: 1 }, { unique: true });
StoreProductSchema.index({ active: 1, categoryId: 1 });
StoreProductSchema.index(
  { name: 'text', description: 'text' },
  { weights: { name: 10, description: 5 } }
);

export const StoreProduct = mongoose.model<IStoreProduct>(
  'StoreProduct',
  StoreProductSchema
);
