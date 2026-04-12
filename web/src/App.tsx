import { BrowserRouter, Routes, Route } from 'react-router-dom';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { useEffect } from 'react';
import { initGA, trackPageView } from './lib/analytics';
import { useLocation } from 'react-router-dom';
import { Toaster } from './components/ui/sonner';
import { AuthProvider, RequireAuth } from './lib/auth';

import LandingPage from './pages/LandingPage';
import StorePage from './pages/StorePage';
import AccountPage from './pages/AccountPage';
import SignInPage from './pages/SignInPage';
import MetricsPage from './pages/MetricsPage';
import PrivacyPolicyPage from './pages/PrivacyPolicyPage';
import TermsOfServicePage from './pages/TermsOfServicePage';
import SupportPage from './pages/SupportPage';
import DeleteAccountPage from './pages/DeleteAccountPage';
import NotFoundPage from './pages/NotFoundPage';
import RunMapPage from './pages/RunMapPage';

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
      <AuthProvider>
        <BrowserRouter>
          <PageTracker />
          <Routes>
            <Route path="/" element={<LandingPage />} />
            <Route path="/store/*" element={<StorePage />} />
            <Route path="/sign-in" element={<SignInPage />} />
            <Route
              path="/account/*"
              element={(
                <RequireAuth>
                  <AccountPage />
                </RequireAuth>
              )}
            />
            <Route
              path="/metrics"
              element={(
                <RequireAuth>
                  <MetricsPage />
                </RequireAuth>
              )}
            />
            <Route
              path="/runs"
              element={(
                <RequireAuth>
                  <RunMapPage />
                </RequireAuth>
              )}
            />
            <Route path="/privacy" element={<PrivacyPolicyPage />} />
            <Route path="/terms" element={<TermsOfServicePage />} />
            <Route path="/support" element={<SupportPage />} />
            <Route path="/delete-account" element={<DeleteAccountPage />} />
            <Route path="*" element={<NotFoundPage />} />
          </Routes>
          <Toaster />
        </BrowserRouter>
      </AuthProvider>
    </QueryClientProvider>
  );
}
