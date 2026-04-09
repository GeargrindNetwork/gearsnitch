import { BrowserRouter, Routes, Route } from 'react-router-dom';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { useEffect } from 'react';
import { initGA, trackPageView } from './lib/analytics';
import { useLocation } from 'react-router-dom';
import { Toaster } from './components/ui/sonner';

import LandingPage from './pages/LandingPage';
import StorePage from './pages/StorePage';
import AccountPage from './pages/AccountPage';
import NotFoundPage from './pages/NotFoundPage';

const queryClient = new QueryClient();

function PageTracker() {
  const location = useLocation();
  useEffect(() => { trackPageView(location.pathname); }, [location]);
  return null;
}

export default function App() {
  useEffect(() => { initGA(); }, []);

  return (
    <QueryClientProvider client={queryClient}>
      <BrowserRouter>
        <PageTracker />
        <Routes>
          <Route path="/" element={<LandingPage />} />
          <Route path="/store/*" element={<StorePage />} />
          <Route path="/account/*" element={<AccountPage />} />
          <Route path="*" element={<NotFoundPage />} />
        </Routes>
        <Toaster />
      </BrowserRouter>
    </QueryClientProvider>
  );
}
