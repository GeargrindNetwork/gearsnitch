import { Link } from 'react-router-dom';
import { Button } from '@/components/ui/button';
import Header from '@/components/layout/Header';
import Footer from '@/components/layout/Footer';

export default function NotFoundPage() {
  return (
    <div className="dark min-h-screen bg-black text-white">
      <Header />
      <section className="flex min-h-[60vh] flex-col items-center justify-center px-4 pt-16">
        <p className="bg-gradient-to-r from-cyan-400 to-emerald-400 bg-clip-text text-8xl font-extrabold text-transparent">
          404
        </p>
        <h1 className="mt-4 text-2xl font-bold">Page Not Found</h1>
        <p className="mt-2 text-zinc-400">
          The page you're looking for doesn't exist or has been moved.
        </p>
        <Link to="/" className="mt-8">
          <Button className="bg-gradient-to-r from-cyan-500 to-emerald-500 font-semibold text-black hover:from-cyan-400 hover:to-emerald-400">
            Back to Home
          </Button>
        </Link>
      </section>
      <Footer />
    </div>
  );
}
