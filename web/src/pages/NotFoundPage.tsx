import { Link } from 'react-router-dom';
import { Button } from '../components/ui/button';

export default function NotFoundPage() {
  return (
    <div className="min-h-screen bg-zinc-950 text-zinc-100 flex items-center justify-center px-6">
      <div className="text-center">
        <p className="text-7xl font-bold text-emerald-500">404</p>
        <h1 className="mt-4 text-3xl font-bold tracking-tight">Page not found</h1>
        <p className="mt-4 text-zinc-400">
          The page you're looking for doesn't exist or has been moved.
        </p>
        <div className="mt-8">
          <Button asChild className="bg-emerald-600 hover:bg-emerald-500 text-white">
            <Link to="/">Go Home</Link>
          </Button>
        </div>
      </div>
    </div>
  );
}
