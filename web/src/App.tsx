import { BrowserRouter, Routes, Route } from 'react-router-dom';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { useEffect, type ReactNode } from 'react';
import { initGA, trackPageView } from './lib/analytics';
import { useLocation } from 'react-router-dom';
import { Toaster } from './components/ui/sonner';
import { AuthProvider, RequireAuth, RequireAdmin } from './lib/auth';
import { ReleaseProvider, RequireSupportedRelease } from './lib/release';
import { ErrorBoundary } from './components/ErrorBoundary';

import LandingPage from './pages/LandingPage';
import StorePage from './pages/StorePage';
import AccountPage from './pages/AccountPage';
import SignInPage from './pages/SignInPage';
import SubscribePage from './pages/SubscribePage';
import SubscriptionSuccessPage from './pages/SubscriptionSuccessPage';
import MetricsPage from './pages/MetricsPage';
import PrivacyPolicyPage from './pages/PrivacyPolicyPage';
import TermsOfServicePage from './pages/TermsOfServicePage';
import SupportPage from './pages/SupportPage';
import DeleteAccountPage from './pages/DeleteAccountPage';
import NotFoundPage from './pages/NotFoundPage';
import RunMapPage from './pages/RunMapPage';
import DeviceDetailPage from './pages/DeviceDetailPage';
import LabsPage from './pages/LabsPage';
import ReferralsPage from './pages/ReferralsPage';
import CaloriesPage from './pages/CaloriesPage';
import AlertsPage from './pages/AlertsPage';
import AdminPage from './pages/AdminPage';

const queryClient = new QueryClient();

function PageTracker() {
  const location = useLocation();
  useEffect(() => { trackPageView(location.pathname); }, [location]);
  return null;
}

function ProtectedAppRoute({ children }: { children: ReactNode }) {
  return (
    <RequireAuth>
      <RequireSupportedRelease>{children}</RequireSupportedRelease>
    </RequireAuth>
  );
}

export default function App() {
  useEffect(() => { initGA(); }, []);

  return (
    <ErrorBoundary>
      <QueryClientProvider client={queryClient}>
        <AuthProvider>
          <ReleaseProvider>
            <BrowserRouter>
              <PageTracker />
              <ErrorBoundary>
                <Routes>
              <Route path="/" element={<LandingPage />} />
              <Route path="/store/*" element={<StorePage />} />
              <Route path="/sign-in" element={<SignInPage />} />
              <Route path="/subscribe" element={<SubscribePage />} />
              <Route
                path="/account/subscription/success"
                element={(
                  <ProtectedAppRoute>
                    <SubscriptionSuccessPage />
                  </ProtectedAppRoute>
                )}
              />
              <Route
                path="/account/*"
                element={(
                  <ProtectedAppRoute>
                    <AccountPage />
                  </ProtectedAppRoute>
                )}
              />
              <Route
                path="/metrics"
                element={(
                  <ProtectedAppRoute>
                    <MetricsPage />
                  </ProtectedAppRoute>
                )}
              />
              <Route
                path="/runs"
                element={(
                  <ProtectedAppRoute>
                    <RunMapPage />
                  </ProtectedAppRoute>
                )}
              />
              <Route
                path="/devices/:id"
                element={(
                  <ProtectedAppRoute>
                    <DeviceDetailPage />
                  </ProtectedAppRoute>
                )}
              />
              <Route
                path="/labs"
                element={(
                  <ProtectedAppRoute>
                    <LabsPage />
                  </ProtectedAppRoute>
                )}
              />
              <Route
                path="/referrals"
                element={(
                  <ProtectedAppRoute>
                    <ReferralsPage />
                  </ProtectedAppRoute>
                )}
              />
              <Route
                path="/calories"
                element={(
                  <ProtectedAppRoute>
                    <CaloriesPage />
                  </ProtectedAppRoute>
                )}
              />
              <Route
                path="/alerts"
                element={(
                  <ProtectedAppRoute>
                    <AlertsPage />
                  </ProtectedAppRoute>
                )}
              />
              <Route
                path="/admin"
                element={(
                  <RequireAdmin>
                    <AdminPage />
                  </RequireAdmin>
                )}
              />
              <Route path="/privacy" element={<PrivacyPolicyPage />} />
              <Route path="/terms" element={<TermsOfServicePage />} />
              <Route path="/support" element={<SupportPage />} />
              <Route path="/delete-account" element={<DeleteAccountPage />} />
                  <Route path="*" element={<NotFoundPage />} />
                </Routes>
              </ErrorBoundary>
              <Toaster />
            </BrowserRouter>
          </ReleaseProvider>
        </AuthProvider>
      </QueryClientProvider>
    </ErrorBoundary>
  );
}
