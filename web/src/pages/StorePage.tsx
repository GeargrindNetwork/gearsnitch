import { Card, CardContent, CardFooter } from '../components/ui/card';
import { Button } from '../components/ui/button';
import { Badge } from '../components/ui/badge';
import Header from '../components/layout/Header';
import Footer from '../components/layout/Footer';

const placeholderProducts = [
  {
    id: '1',
    name: 'BPC-157',
    slug: 'bpc-157',
    price: 49.99,
    category: 'Peptides',
    description: 'Body Protection Compound — supports tissue recovery and gut health.',
    badge: 'Popular',
  },
  {
    id: '2',
    name: 'TB-500',
    slug: 'tb-500',
    price: 54.99,
    category: 'Peptides',
    description: 'Thymosin Beta-4 — promotes healing, flexibility, and reduced inflammation.',
    badge: null,
  },
  {
    id: '3',
    name: 'CJC-1295 / Ipamorelin',
    slug: 'cjc-1295-ipamorelin',
    price: 79.99,
    category: 'Peptides',
    description: 'Growth hormone secretagogue blend for recovery and body composition.',
    badge: 'New',
  },
  {
    id: '4',
    name: 'GHK-Cu',
    slug: 'ghk-cu',
    price: 44.99,
    category: 'Peptides',
    description: 'Copper peptide — skin rejuvenation, wound healing, and anti-aging.',
    badge: null,
  },
  {
    id: '5',
    name: 'Selank',
    slug: 'selank',
    price: 39.99,
    category: 'Peptides',
    description: 'Nootropic peptide — reduces anxiety, improves focus and cognitive function.',
    badge: null,
  },
  {
    id: '6',
    name: 'PT-141',
    slug: 'pt-141',
    price: 64.99,
    category: 'Peptides',
    description: 'Bremelanotide — supports sexual health and libido enhancement.',
    badge: 'Restricted',
  },
];

export default function StorePage() {
  return (
    <div className="min-h-screen bg-zinc-950 text-zinc-100">
      <Header />

      <section className="px-6 py-16 lg:px-8">
        <div className="mx-auto max-w-6xl">
          <div className="mb-12">
            <h1 className="text-3xl font-bold tracking-tight">GearSnitch Store</h1>
            <p className="mt-2 text-zinc-400">
              Premium peptide products — lab-tested, compliance-verified, shipped discreetly.
            </p>
          </div>

          <div className="grid grid-cols-1 gap-6 sm:grid-cols-2 lg:grid-cols-3">
            {placeholderProducts.map((product) => (
              <Card
                key={product.id}
                className="border-zinc-800 bg-zinc-900/50 hover:border-zinc-700 transition-colors flex flex-col"
              >
                <CardContent className="p-6 flex-1">
                  <div className="flex items-start justify-between mb-3">
                    <span className="text-xs text-zinc-500 uppercase tracking-wider">
                      {product.category}
                    </span>
                    {product.badge && (
                      <Badge
                        variant="outline"
                        className={
                          product.badge === 'Restricted'
                            ? 'border-amber-500/50 text-amber-400 text-xs'
                            : 'border-emerald-500/50 text-emerald-400 text-xs'
                        }
                      >
                        {product.badge}
                      </Badge>
                    )}
                  </div>
                  <h3 className="text-lg font-semibold text-zinc-100">{product.name}</h3>
                  <p className="mt-2 text-sm text-zinc-400 leading-relaxed">{product.description}</p>
                </CardContent>
                <CardFooter className="p-6 pt-0 flex items-center justify-between">
                  <span className="text-xl font-bold text-zinc-100">
                    ${product.price.toFixed(2)}
                  </span>
                  <Button
                    size="sm"
                    className="bg-emerald-600 hover:bg-emerald-500 text-white"
                  >
                    Add to Cart
                  </Button>
                </CardFooter>
              </Card>
            ))}
          </div>

          <div className="mt-12 p-6 rounded-lg border border-zinc-800 bg-zinc-900/30 text-center">
            <p className="text-sm text-zinc-500">
              All products are for research purposes only. Must be 21+ to purchase.
              Consult a healthcare professional before use. Jurisdiction restrictions may apply.
            </p>
          </div>
        </div>
      </section>

      <Footer />
    </div>
  );
}
