import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { Card, CardContent, CardFooter } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import Header from '@/components/layout/Header';
import Footer from '@/components/layout/Footer';
import StripeCheckout from '@/components/checkout/StripeCheckout';
import { api } from '@/lib/api';
import { useAuth } from '@/lib/auth';

interface StoreProduct {
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
}

interface StoreCart {
  _id: string;
  subtotal: number;
  tax: number;
  shipping: number;
  total: number;
  currency: string;
  itemCount: number;
}

function badgeForProduct(product: StoreProduct) {
  if (!product.inStock) {
    return { label: 'Sold Out', className: 'border-red-500/50 text-red-400 text-xs' };
  }

  if (product.complianceWarnings.length > 0) {
    return { label: 'Restricted', className: 'border-amber-500/50 text-amber-400 text-xs' };
  }

  if (product.inventory <= 5) {
    return { label: 'Low Stock', className: 'border-emerald-500/50 text-emerald-400 text-xs' };
  }

  return null;
}

export default function StorePage() {
  const navigate = useNavigate();
  const { isAuthenticated } = useAuth();

  const [products, setProducts] = useState<StoreProduct[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [pageError, setPageError] = useState<string | null>(null);
  const [busyProductId, setBusyProductId] = useState<string | null>(null);
  const [checkoutProduct, setCheckoutProduct] = useState<StoreProduct | null>(null);
  const [checkoutCart, setCheckoutCart] = useState<StoreCart | null>(null);
  const [checkoutOpen, setCheckoutOpen] = useState(false);

  useEffect(() => {
    let active = true;

    async function loadProducts() {
      setIsLoading(true);
      setPageError(null);

      const res = await api.get<StoreProduct[]>('/store/products');
      if (!active) {
        return;
      }

      if (!res.success || !res.data) {
        setPageError(res.error?.message ?? 'Could not load the GearSnitch store.');
        setProducts([]);
        setIsLoading(false);
        return;
      }

      setProducts(res.data);
      setIsLoading(false);
    }

    void loadProducts();

    return () => {
      active = false;
    };
  }, []);

  async function openCheckout(product: StoreProduct) {
    if (!isAuthenticated) {
      navigate(`/sign-in?redirect=${encodeURIComponent('/store')}`);
      return;
    }

    setBusyProductId(product._id);
    setPageError(null);

    const res = await api.post<StoreCart>('/store/cart', {
      productId: product._id,
      quantity: 1,
    });

    if (!res.success || !res.data) {
      setPageError(res.error?.message ?? 'Could not prepare your checkout session.');
      setBusyProductId(null);
      return;
    }

    setCheckoutProduct(product);
    setCheckoutCart(res.data);
    setCheckoutOpen(true);
    setBusyProductId(null);
  }

  function closeCheckout() {
    setCheckoutOpen(false);
    setCheckoutProduct(null);
    setCheckoutCart(null);
  }

  return (
    <div className="dark min-h-screen bg-zinc-950 text-zinc-100">
      <Header />

      <section className="px-6 py-16 lg:px-8">
        <div className="mx-auto max-w-6xl">
          <div className="mb-12">
            <h1 className="text-3xl font-bold tracking-tight">GearSnitch Store</h1>
            <p className="mt-2 text-zinc-400">
              Premium peptide products with backend-backed catalog and checkout flows.
            </p>
          </div>

          {pageError && (
            <div className="mb-6 rounded-lg border border-red-500/30 bg-red-500/10 px-4 py-3 text-sm text-red-200">
              {pageError}
            </div>
          )}

          {isLoading ? (
            <div className="rounded-lg border border-zinc-800 bg-zinc-900/40 px-6 py-12 text-center text-zinc-400">
              Loading store catalog...
            </div>
          ) : (
            <div className="grid grid-cols-1 gap-6 sm:grid-cols-2 lg:grid-cols-3">
              {products.map((product) => {
                const badge = badgeForProduct(product);
                const isBusy = busyProductId === product._id;

                return (
                  <Card
                    key={product._id}
                    className="flex flex-col border-zinc-800 bg-zinc-900/50 transition-colors hover:border-zinc-700"
                  >
                    <CardContent className="flex-1 p-6">
                      <div className="mb-3 flex items-start justify-between gap-3">
                        <span className="text-xs uppercase tracking-wider text-zinc-500">
                          {product.category}
                        </span>
                        {badge && (
                          <Badge variant="outline" className={badge.className}>
                            {badge.label}
                          </Badge>
                        )}
                      </div>

                      <h3 className="text-lg font-semibold text-zinc-100">{product.name}</h3>
                      <p className="mt-2 text-sm leading-relaxed text-zinc-400">
                        {product.description}
                      </p>

                      {product.complianceWarnings.length > 0 && (
                        <ul className="mt-4 space-y-1 text-xs text-amber-300">
                          {product.complianceWarnings.map((warning) => (
                            <li key={warning}>{warning}</li>
                          ))}
                        </ul>
                      )}
                    </CardContent>

                    <CardFooter className="flex items-center justify-between p-6 pt-0">
                      <span className="text-xl font-bold text-zinc-100">
                        ${product.price.toFixed(2)}
                      </span>
                      <Button
                        size="sm"
                        className="bg-emerald-600 text-white hover:bg-emerald-500"
                        disabled={!product.inStock || isBusy}
                        onClick={() => void openCheckout(product)}
                      >
                        {isBusy ? 'Preparing...' : product.inStock ? 'Buy Now' : 'Unavailable'}
                      </Button>
                    </CardFooter>
                  </Card>
                );
              })}
            </div>
          )}

          <div className="mt-12 rounded-lg border border-zinc-800 bg-zinc-900/30 p-6 text-center">
            <p className="text-sm text-zinc-500">
              All products are for research purposes only. Must be 21+ to purchase.
              Jurisdiction restrictions and additional compliance checks may apply.
            </p>
          </div>
        </div>
      </section>

      <Dialog
        open={checkoutOpen}
        onOpenChange={(open) => {
          if (!open) {
            closeCheckout();
          }
        }}
      >
        <DialogContent className="border-zinc-700 bg-zinc-900 sm:max-w-md">
          <DialogHeader>
            <DialogTitle className="text-zinc-100">
              {checkoutProduct ? `Checkout — ${checkoutProduct.name}` : 'Checkout'}
            </DialogTitle>
            <DialogDescription className="text-zinc-400">
              Review your shipping details and complete payment with Apple Pay, Google Pay, or card.
            </DialogDescription>
          </DialogHeader>

          {checkoutProduct && checkoutCart && (
            <div className="space-y-4">
              <div className="rounded-lg border border-zinc-800 bg-zinc-950/60 p-4 text-sm text-zinc-300">
                <div className="flex items-center justify-between">
                  <span>Subtotal</span>
                  <span>${checkoutCart.subtotal.toFixed(2)}</span>
                </div>
                <div className="mt-2 flex items-center justify-between">
                  <span>Tax</span>
                  <span>${checkoutCart.tax.toFixed(2)}</span>
                </div>
                <div className="mt-2 flex items-center justify-between">
                  <span>Shipping</span>
                  <span>${checkoutCart.shipping.toFixed(2)}</span>
                </div>
                <div className="mt-3 flex items-center justify-between border-t border-zinc-800 pt-3 font-semibold text-zinc-100">
                  <span>Total</span>
                  <span>${checkoutCart.total.toFixed(2)}</span>
                </div>
              </div>

              <StripeCheckout
                cartId={checkoutCart._id}
                amount={checkoutCart.total}
                currency={checkoutCart.currency.toLowerCase()}
                label={checkoutProduct.name}
                onSuccess={() => {
                  window.setTimeout(closeCheckout, 2000);
                }}
                onError={(message) => {
                  setPageError(message);
                }}
                onCancel={closeCheckout}
              />
            </div>
          )}
        </DialogContent>
      </Dialog>

      <Footer />
    </div>
  );
}
