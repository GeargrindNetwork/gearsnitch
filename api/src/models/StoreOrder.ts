import mongoose, { Schema, Document, Types } from 'mongoose';

export interface IStoreOrderItem {
  productId: Types.ObjectId;
  sku: string;
  name: string;
  quantity: number;
  unitPrice: number;
  lineTotal: number;
}

export interface IShippingAddress {
  line1: string;
  line2?: string;
  city: string;
  state: string;
  postalCode: string;
  country: string;
}

export interface IStoreOrder extends Document {
  _id: Types.ObjectId;
  userId: Types.ObjectId;
  sourceCartId?: Types.ObjectId;
  orderNumber: string;
  paymentIntentId?: string;
  status: 'pending' | 'paid' | 'fulfilled' | 'cancelled' | 'refunded';
  items: IStoreOrderItem[];
  subtotal: number;
  tax: number;
  shipping: number;
  total: number;
  currency: string;
  shippingAddress: IShippingAddress;
  complianceAccepted?: boolean;
  createdAt: Date;
  updatedAt: Date;
}

const StoreOrderItemSchema = new Schema<IStoreOrderItem>(
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

const ShippingAddressSchema = new Schema<IShippingAddress>(
  {
    line1: { type: String, required: true },
    line2: { type: String },
    city: { type: String, required: true },
    state: { type: String, required: true },
    postalCode: { type: String, required: true },
    country: { type: String, required: true },
  },
  { _id: false }
);

const StoreOrderSchema = new Schema<IStoreOrder>(
  {
    userId: { type: Schema.Types.ObjectId, ref: 'User', required: true },
    sourceCartId: { type: Schema.Types.ObjectId, ref: 'StoreCart' },
    orderNumber: { type: String, required: true },
    paymentIntentId: { type: String },
    status: {
      type: String,
      enum: ['pending', 'paid', 'fulfilled', 'cancelled', 'refunded'],
      default: 'pending',
    },
    items: { type: [StoreOrderItemSchema], default: [] },
    subtotal: { type: Number, required: true },
    tax: { type: Number, required: true },
    shipping: { type: Number, required: true },
    total: { type: Number, required: true },
    currency: { type: String, default: 'USD' },
    shippingAddress: { type: ShippingAddressSchema, required: true },
    complianceAccepted: { type: Boolean },
  },
  { timestamps: true }
);

StoreOrderSchema.index({ orderNumber: 1 }, { unique: true });
StoreOrderSchema.index({ userId: 1, createdAt: -1 });
StoreOrderSchema.index({ status: 1 });
StoreOrderSchema.index({ paymentIntentId: 1 }, { sparse: true });
StoreOrderSchema.index({ userId: 1, sourceCartId: 1, status: 1 }, { sparse: true });

export const StoreOrder = mongoose.model<IStoreOrder>(
  'StoreOrder',
  StoreOrderSchema
);
