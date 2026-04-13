import { Types } from 'mongoose';
import { StatusCodes } from 'http-status-codes';
import { StoreCart } from '../../models/StoreCart.js';
import { StoreCategory } from '../../models/StoreCategory.js';
import { StoreOrder } from '../../models/StoreOrder.js';
import { StoreProduct } from '../../models/StoreProduct.js';

const TAX_RATE = 0.0825;
const FLAT_SHIPPING = 5.99;

export class StoreServiceError extends Error {
  constructor(
    readonly statusCode: number,
    message: string,
  ) {
    super(message);
    this.name = 'StoreServiceError';
  }
}

interface ProductResponse {
  _id: string;
  sku: string;
  slug: string;
  name: string;
  description: string;
  price: number;
  currency: string;
  category: string;
  imageURLs: string[];
  inStock: boolean;
  inventory: number;
  complianceWarnings: string[];
  createdAt: Date;
  updatedAt: Date;
}

interface CartItemResponse {
  _id: string;
  productId: string;
  sku: string;
  name: string;
  price: number;
  quantity: number;
  imageURL: string | null;
}

interface CartResponse {
  _id: string;
  items: CartItemResponse[];
  subtotal: number;
  tax: number;
  shipping: number;
  total: number;
  currency: string;
  itemCount: number;
  updatedAt: Date | null;
}

interface OrderItemResponse {
  productId: string;
  sku: string;
  name: string;
  quantity: number;
  price: number;
  lineTotal: number;
}

interface OrderResponse {
  _id: string;
  orderNumber: string;
  status: string;
  total: number;
  subtotal: number;
  tax: number;
  shipping: number;
  currency: string;
  itemCount: number;
  items: OrderItemResponse[];
  createdAt: Date;
  updatedAt: Date;
}

interface AddToCartInput {
  productId: string;
  quantity: number;
}

interface UpdateCartItemInput {
  productId: string;
  quantity: number;
}

function assertObjectId(value: string, fieldName: string): Types.ObjectId {
  if (!Types.ObjectId.isValid(value)) {
    throw new StoreServiceError(
      StatusCodes.BAD_REQUEST,
      `${fieldName} must be a valid ObjectId`,
    );
  }

  return new Types.ObjectId(value);
}

function buildComplianceWarnings(product: {
  compliance?: {
    requiresAgeConfirmation?: boolean;
    jurisdictionAllowlist?: string[];
    jurisdictionBlocklist?: string[];
    termsRequired?: boolean;
    medicalDisclaimerRequired?: boolean;
  };
}): string[] {
  const warnings: string[] = [];
  const compliance = product.compliance;

  if (!compliance) {
    return warnings;
  }

  if (compliance.requiresAgeConfirmation) {
    warnings.push('Must be 21 or older to purchase.');
  }

  if (compliance.termsRequired) {
    warnings.push('Additional purchase terms must be accepted before checkout.');
  }

  if (compliance.medicalDisclaimerRequired) {
    warnings.push(
      'Research-use product. Consult a qualified professional before use.',
    );
  }

  if ((compliance.jurisdictionAllowlist ?? []).length > 0) {
    warnings.push('Shipping is limited to approved jurisdictions.');
  }

  if ((compliance.jurisdictionBlocklist ?? []).length > 0) {
    warnings.push('This item cannot be shipped to all jurisdictions.');
  }

  return warnings;
}

function serializeProduct(
  product: InstanceType<typeof StoreProduct>,
  categoryName: string,
): ProductResponse {
  return {
    _id: String(product._id),
    sku: product.sku,
    slug: product.slug,
    name: product.name,
    description: product.description ?? '',
    price: product.price,
    currency: product.currency,
    category: categoryName,
    imageURLs: product.images,
    inStock: product.inventory > 0,
    inventory: product.inventory,
    complianceWarnings: buildComplianceWarnings(product),
    createdAt: product.createdAt,
    updatedAt: product.updatedAt,
  };
}

export class StoreService {
  private async ensureSeedData(): Promise<void> {
    let category = await StoreCategory.findOne({ slug: 'training-gear' });

    if (!category) {
      category = await StoreCategory.create({
        name: 'Training Gear',
        slug: 'training-gear',
        sortOrder: 10,
        active: true,
      });
    }

    await StoreProduct.findOneAndUpdate(
      { sku: 'GS-JUMPROPE-001' },
      {
        $set: {
          name: 'GearSnitch Speed Jump Rope',
          slug: 'gearsnitch-speed-jump-rope',
          description:
            'Adjustable speed jump rope for warm-ups, conditioning, and travel workouts.',
          categoryId: category._id,
          price: 24.99,
          currency: 'USD',
          inventory: 50,
          active: true,
          images: [
            'https://cdn.gearsnitch.app/store/products/jump-rope.png',
          ],
          compliance: {},
        },
        $setOnInsert: {
          sku: 'GS-JUMPROPE-001',
        },
      },
      {
        new: true,
        upsert: true,
      },
    );
  }

  async listProducts(): Promise<ProductResponse[]> {
    await this.ensureSeedData();

    const products = await StoreProduct.find({ active: true }).sort({
      createdAt: -1,
    });

    const categoryIds = Array.from(
      new Set(products.map((product) => String(product.categoryId))),
    ).map((id) => new Types.ObjectId(id));

    const categories = await StoreCategory.find({
      _id: { $in: categoryIds },
    });

    const categoryMap = new Map(
      categories.map((category) => [String(category._id), category.name]),
    );

    return products.map((product) =>
      serializeProduct(
        product,
        categoryMap.get(String(product.categoryId)) ?? 'Uncategorized',
      ),
    );
  }

  async getProductByReference(reference: string): Promise<ProductResponse> {
    await this.ensureSeedData();

    const product = Types.ObjectId.isValid(reference)
      ? await StoreProduct.findOne({
          _id: new Types.ObjectId(reference),
          active: true,
        })
      : await StoreProduct.findOne({
          $or: [{ slug: reference }, { sku: reference }],
          active: true,
        });

    if (!product) {
      throw new StoreServiceError(StatusCodes.NOT_FOUND, 'Product not found');
    }

    const category = await StoreCategory.findById(product.categoryId);

    return serializeProduct(product, category?.name ?? 'Uncategorized');
  }

  async getCart(userId: string): Promise<CartResponse> {
    const cart = await this.findOrCreateCart(userId);
    return this.serializeCart(cart);
  }

  async addToCart(userId: string, input: AddToCartInput): Promise<CartResponse> {
    const productId = assertObjectId(input.productId, 'productId');
    const quantity = Math.max(1, Math.trunc(input.quantity));

    const product = await StoreProduct.findOne({
      _id: productId,
      active: true,
    });

    if (!product) {
      throw new StoreServiceError(StatusCodes.NOT_FOUND, 'Product not found');
    }

    if (product.inventory <= 0) {
      throw new StoreServiceError(StatusCodes.CONFLICT, 'Product is out of stock');
    }

    const cart = await this.findOrCreateCart(userId);
    const existingItem = cart.items.find(
      (item) => String(item.productId) === String(product._id),
    );

    if (existingItem) {
      existingItem.quantity += quantity;
      existingItem.lineTotal = existingItem.quantity * existingItem.unitPrice;
    } else {
      cart.items.push({
        productId: product._id,
        sku: product.sku,
        name: product.name,
        quantity,
        unitPrice: product.price,
        lineTotal: product.price * quantity,
      });
    }

    cart.subtotal = this.computeSubtotal(cart.items);
    await cart.save();

    return this.serializeCart(cart);
  }

  async updateCartItem(
    userId: string,
    input: UpdateCartItemInput,
  ): Promise<CartResponse> {
    const productId = assertObjectId(input.productId, 'productId');
    const cart = await this.findOrCreateCart(userId);
    const item = cart.items.find(
      (cartItem) => String(cartItem.productId) === String(productId),
    );

    if (!item) {
      throw new StoreServiceError(StatusCodes.NOT_FOUND, 'Cart item not found');
    }

    if (input.quantity <= 0) {
      cart.items = cart.items.filter(
        (cartItem) => String(cartItem.productId) !== String(productId),
      );
    } else {
      item.quantity = Math.trunc(input.quantity);
      item.lineTotal = item.quantity * item.unitPrice;
    }

    cart.subtotal = this.computeSubtotal(cart.items);
    await cart.save();

    return this.serializeCart(cart);
  }

  async removeCartItem(userId: string, productIdValue: string): Promise<CartResponse> {
    const productId = assertObjectId(productIdValue, 'productId');
    const cart = await this.findOrCreateCart(userId);

    cart.items = cart.items.filter(
      (item) => String(item.productId) !== String(productId),
    );
    cart.subtotal = this.computeSubtotal(cart.items);
    await cart.save();

    return this.serializeCart(cart);
  }

  async listOrders(
    userId: string,
    page: number = 1,
    limit: number = 20,
  ): Promise<{
    orders: OrderResponse[];
    page: number;
    limit: number;
    total: number;
    hasMore: boolean;
  }> {
    const normalizedPage = Math.max(1, page);
    const normalizedLimit = Math.min(50, Math.max(1, limit));
    const skip = (normalizedPage - 1) * normalizedLimit;

    const [orders, total] = await Promise.all([
      StoreOrder.find({ userId: new Types.ObjectId(userId) })
        .sort({ createdAt: -1 })
        .skip(skip)
        .limit(normalizedLimit),
      StoreOrder.countDocuments({ userId: new Types.ObjectId(userId) }),
    ]);

    return {
      orders: orders.map((order) => this.serializeOrder(order)),
      page: normalizedPage,
      limit: normalizedLimit,
      total,
      hasMore: skip + orders.length < total,
    };
  }

  private async findOrCreateCart(userId: string) {
    const normalizedUserId = assertObjectId(userId, 'userId');
    let cart = await StoreCart.findOne({ userId: normalizedUserId });

    if (!cart) {
      cart = await StoreCart.create({
        userId: normalizedUserId,
        items: [],
        currency: 'USD',
        subtotal: 0,
      });
    }

    return cart;
  }

  private async serializeCart(
    cart: InstanceType<typeof StoreCart>,
  ): Promise<CartResponse> {
    const productIds = cart.items.map((item) => item.productId);
    const products = await StoreProduct.find({ _id: { $in: productIds } });
    const productMap = new Map(
      products.map((product) => [String(product._id), product]),
    );

    const itemCount = cart.items.reduce((sum, item) => sum + item.quantity, 0);
    const shipping = itemCount > 0 ? FLAT_SHIPPING : 0;
    const tax = itemCount > 0 ? Number((cart.subtotal * TAX_RATE).toFixed(2)) : 0;
    const total = Number((cart.subtotal + tax + shipping).toFixed(2));

    return {
      _id: String(cart._id),
      items: cart.items.map((item) => ({
        _id: String(item.productId),
        productId: String(item.productId),
        sku: item.sku,
        name: item.name,
        price: item.unitPrice,
        quantity: item.quantity,
        imageURL: productMap.get(String(item.productId))?.images[0] ?? null,
      })),
      subtotal: cart.subtotal,
      tax,
      shipping,
      total,
      currency: cart.currency,
      itemCount,
      updatedAt: cart.updatedAt,
    };
  }

  private serializeOrder(order: InstanceType<typeof StoreOrder>): OrderResponse {
    return {
      _id: String(order._id),
      orderNumber: order.orderNumber,
      status: order.status,
      total: order.total,
      subtotal: order.subtotal,
      tax: order.tax,
      shipping: order.shipping,
      currency: order.currency,
      itemCount: order.items.reduce((sum, item) => sum + item.quantity, 0),
      items: order.items.map((item) => ({
        productId: String(item.productId),
        sku: item.sku,
        name: item.name,
        quantity: item.quantity,
        price: item.unitPrice,
        lineTotal: item.lineTotal,
      })),
      createdAt: order.createdAt,
      updatedAt: order.updatedAt,
    };
  }

  private computeSubtotal(
    items: Array<{
      quantity: number;
      unitPrice: number;
      lineTotal: number;
    }>,
  ): number {
    return items.reduce((sum, item) => {
      const lineTotal = item.quantity * item.unitPrice;
      item.lineTotal = lineTotal;
      return sum + lineTotal;
    }, 0);
  }
}
