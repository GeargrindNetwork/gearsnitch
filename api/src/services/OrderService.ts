import { Types } from 'mongoose';
import { StoreCart } from '../models/StoreCart.js';
import { StoreOrder, type IStoreOrder } from '../models/StoreOrder.js';

const TAX_RATE = 0.0825;
const FLAT_SHIPPING_CENTS = 599;

export class OrderService {
  /**
   * Create an order by snapshotting the cart contents.
   * Clears the cart after the order is created.
   */
  async createFromCart(
    userId: string,
    cartId: string,
    paymentIntentId: string,
    shippingAddress: {
      line1: string;
      line2?: string;
      city: string;
      state: string;
      postalCode: string;
      country: string;
    },
  ): Promise<IStoreOrder> {
    const cart = await StoreCart.findOne({
      _id: new Types.ObjectId(cartId),
      userId: new Types.ObjectId(userId),
    });

    if (!cart || cart.items.length === 0) {
      throw new Error('Cart is empty or does not exist');
    }

    const subtotalCents = Math.round(cart.subtotal * 100);
    const taxCents = Math.round(subtotalCents * TAX_RATE);
    const shippingCents = FLAT_SHIPPING_CENTS;
    const totalCents = subtotalCents + taxCents + shippingCents;

    const orderNumber = await this.generateOrderNumber();

    const order = await StoreOrder.create({
      userId: new Types.ObjectId(userId),
      orderNumber,
      paymentIntentId,
      status: 'pending',
      items: cart.items.map((item) => ({
        productId: item.productId,
        sku: item.sku,
        name: item.name,
        quantity: item.quantity,
        unitPrice: item.unitPrice,
        lineTotal: item.lineTotal,
      })),
      subtotal: subtotalCents / 100,
      tax: taxCents / 100,
      shipping: shippingCents / 100,
      total: totalCents / 100,
      currency: cart.currency,
      shippingAddress,
    });

    // Clear the cart
    cart.items = [];
    cart.subtotal = 0;
    await cart.save();

    return order;
  }

  /**
   * Update order status by ID.
   */
  async updateStatus(
    orderId: string,
    status: IStoreOrder['status'],
  ): Promise<IStoreOrder> {
    const order = await StoreOrder.findByIdAndUpdate(
      orderId,
      { status },
      { new: true },
    );

    if (!order) {
      throw new Error('Order not found');
    }

    return order;
  }

  /**
   * Get paginated orders for a user.
   */
  async getByUser(
    userId: string,
    page: number = 1,
    limit: number = 20,
  ): Promise<{ orders: IStoreOrder[]; total: number }> {
    const skip = (page - 1) * limit;

    const [orders, total] = await Promise.all([
      StoreOrder.find({ userId: new Types.ObjectId(userId) })
        .sort({ createdAt: -1 })
        .skip(skip)
        .limit(limit),
      StoreOrder.countDocuments({ userId: new Types.ObjectId(userId) }),
    ]);

    return { orders, total };
  }

  /**
   * Get a single order by ID, scoped to the requesting user.
   */
  async getById(orderId: string, userId: string): Promise<IStoreOrder> {
    const order = await StoreOrder.findOne({
      _id: new Types.ObjectId(orderId),
      userId: new Types.ObjectId(userId),
    });

    if (!order) {
      throw new Error('Order not found');
    }

    return order;
  }

  /**
   * Generate a sequential order number in the format GS-XXXXXX.
   */
  private async generateOrderNumber(): Promise<string> {
    const count = await StoreOrder.countDocuments();
    const seq = (count + 1).toString().padStart(6, '0');
    return `GS-${seq}`;
  }
}
