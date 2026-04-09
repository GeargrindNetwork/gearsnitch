import mongoose, { Schema, Document, Types } from 'mongoose';

export interface IStoreCartItem {
  productId: Types.ObjectId;
  sku: string;
  name: string;
  quantity: number;
  unitPrice: number;
  lineTotal: number;
}

export interface IStoreCart extends Document {
  _id: Types.ObjectId;
  userId: Types.ObjectId;
  items: IStoreCartItem[];
  currency: string;
  subtotal: number;
  createdAt: Date;
  updatedAt: Date;
}

const StoreCartItemSchema = new Schema<IStoreCartItem>(
  {
    productId: {
      type: Schema.Types.ObjectId,
      ref: 'StoreProduct',
      required: true,
    },
    sku: { type: String, required: true },
    name: { type: String, required: true },
    quantity: { type: Number, required: true },
    unitPrice: { type: Number, required: true },
    lineTotal: { type: Number, required: true },
  },
  { _id: false }
);

const StoreCartSchema = new Schema<IStoreCart>(
  {
    userId: { type: Schema.Types.ObjectId, ref: 'User', required: true },
    items: { type: [StoreCartItemSchema], default: [] },
    currency: { type: String, default: 'USD' },
    subtotal: { type: Number, default: 0 },
  },
  { timestamps: true }
);

StoreCartSchema.index({ userId: 1 }, { unique: true });

export const StoreCart = mongoose.model<IStoreCart>('StoreCart', StoreCartSchema);
