import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { Link, Navigate, useNavigate, useSearchParams } from 'react-router-dom';
import { Apple, Loader2, ShieldCheck } from 'lucide-react';
import Header from '@/components/layout/Header';
import Footer from '@/components/layout/Footer';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { api } from '@/lib/api';
import { useAuth, type AuthUser } from '@/lib/auth';

interface OAuthSignInResponse {
  accessToken: string;
  refreshToken: string;
  user: AuthUser;
}

interface GoogleCredentialResponse {
  credential?: string;
}

interface AppleName {
  firstName?: string;
  lastName?: string;
}

interface AppleSignInResponse {
  authorization?: {
    code?: string;
    id_token?: string;
  };
  user?: {
    name?: AppleName;
  };
}

declare global {
  interface Window {
    google?: {
      accounts?: {
        id?: {
          initialize: (config: {
            client_id: string;
            callback: (response: GoogleCredentialResponse) => void;
            auto_select?: boolean;
            ux_mode?: 'popup' | 'redirect';
          }) => void;
          renderButton: (
            element: HTMLElement,
            options: Record<string, string | number | boolean>,
          ) => void;
        };
      };
    };
    AppleID?: {
      auth?: {
        init: (config: {
          clientId: string;
          scope: string;
          redirectURI: string;
          state: string;
          usePopup: boolean;
        }) => void;
        signIn: () => Promise<AppleSignInResponse>;
      };
    };
  }
}

function getConfiguredEnvValue(value: string | undefined): string {
  const normalized = value?.trim();
  if (!normalized || normalized === 'placeholder') {
    return '';
  }

  return normalized;
}

const GOOGLE_CLIENT_ID = getConfiguredEnvValue(import.meta.env.VITE_GOOGLE_CLIENT_ID);
const APPLE_SERVICE_ID = getConfiguredEnvValue(import.meta.env.VITE_APPLE_SERVICE_ID);

const scriptCache = new Map<string, Promise<void>>();

function loadScript(src: string, id: string): Promise<void> {
  const cached = scriptCache.get(id);
  if (cached) {
    return cached;
  }

  const promise = new Promise<void>((resolve, reject) => {
    const existing = document.getElementById(id) as HTMLScriptElement | null;
    if (existing) {
      resolve();
      return;
    }

    const script = document.createElement('script');
    script.id = id;
    script.src = src;
    script.async = true;
    script.onload = () => resolve();
    script.onerror = () => reject(new Error(`Failed to load script: ${src}`));
    document.head.appendChild(script);
  });

  scriptCache.set(id, promise);
  return promise;
}

function formatErrorMessage(error: unknown, fallback: string): string {
  return error instanceof Error && error.message ? error.message : fallback;
}

function GoogleSignInButton({
  onCredential,
  onError,
}: {
  onCredential: (credential: string) => Promise<void>;
  onError: (message: string) => void;
}) {
  const buttonRef = useRef<HTMLDivElement | null>(null);

  useEffect(() => {
    if (!GOOGLE_CLIENT_ID || !buttonRef.current) {
      return;
    }

    let cancelled = false;

    void loadScript('https://accounts.google.com/gsi/client', 'google-identity-services')
      .then(() => {
        const googleId = window.google?.accounts?.id;
        if (cancelled || !buttonRef.current || !googleId) {
          return;
        }

        googleId.initialize({
          client_id: GOOGLE_CLIENT_ID,
          callback: (response) => {
            if (!response.credential) {
              onError('Google did not return an ID token.');
              return;
            }

            void onCredential(response.credential);
          },
          auto_select: false,
          ux_mode: 'popup',
        });

        buttonRef.current.innerHTML = '';
        googleId.renderButton(buttonRef.current, {
          theme: 'outline',
          size: 'large',
          shape: 'pill',
          width: Math.max(buttonRef.current.clientWidth, 320),
          text: 'continue_with',
        });
      })
      .catch((error) => {
        onError(formatErrorMessage(error, 'Failed to load Google Sign-In.'));
      });

    return () => {
      cancelled = true;
    };
  }, [onCredential, onError]);

  if (!GOOGLE_CLIENT_ID) {
    return (
      <div className="rounded-xl border border-dashed border-zinc-700 bg-zinc-950/80 px-4 py-5 text-sm text-zinc-500">
        Google browser sign-in is disabled until `VITE_GOOGLE_CLIENT_ID` is configured.
      </div>
    );
  }

  return <div ref={buttonRef} className="min-h-11 w-full" />;
}

export default function SignInPage() {
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  const { status, isAuthenticated, completeOAuthSignIn } = useAuth();
  const [activeProvider, setActiveProvider] = useState<'google' | 'apple' | null>(null);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  const redirectTarget = useMemo(
    () => searchParams.get('redirect') || '/account',
    [searchParams],
  );

  const appleRedirectUri = useMemo(
    () => import.meta.env.VITE_APPLE_REDIRECT_URI || `${window.location.origin}/sign-in`,
    [],
  );

  const finalizeSignIn = useCallback(
    async (data: OAuthSignInResponse) => {
      const success = await completeOAuthSignIn({
        accessToken: data.accessToken,
        user: data.user,
      });

      if (!success) {
        throw new Error('Failed to finalize the browser session.');
      }

      navigate(redirectTarget, { replace: true });
    },
    [completeOAuthSignIn, navigate, redirectTarget],
  );

  const handleGoogleCredential = useCallback(
    async (credential: string) => {
      setActiveProvider('google');
      setErrorMessage(null);

      try {
        const res = await api.post<OAuthSignInResponse>('/auth/oauth/google', {
          idToken: credential,
        });

        if (!res.success || !res.data) {
          throw new Error(res.error?.message ?? 'Google sign-in failed.');
        }

        await finalizeSignIn(res.data);
      } catch (error) {
        setErrorMessage(formatErrorMessage(error, 'Google sign-in failed.'));
      } finally {
        setActiveProvider(null);
      }
    },
    [finalizeSignIn],
  );

  const handleAppleSignIn = useCallback(async () => {
    if (!APPLE_SERVICE_ID) {
      setErrorMessage('Apple browser sign-in is disabled until `VITE_APPLE_SERVICE_ID` is configured.');
      return;
    }

    setActiveProvider('apple');
    setErrorMessage(null);

    try {
      await loadScript(
        'https://appleid.cdn-apple.com/appleauth/static/jsapi/appleid/1/en_US/appleid.auth.js',
        'apple-sign-in-js',
      );

      const appleAuth = window.AppleID?.auth;
      if (!appleAuth) {
        throw new Error('Apple Sign-In SDK is unavailable.');
      }

      appleAuth.init({
        clientId: APPLE_SERVICE_ID,
        scope: 'name email',
        redirectURI: appleRedirectUri,
        state: crypto.randomUUID(),
        usePopup: true,
      });

      const response = await appleAuth.signIn();
      const identityToken = response.authorization?.id_token;
      const authorizationCode = response.authorization?.code;

      if (!identityToken || !authorizationCode) {
        throw new Error('Apple did not return a complete authorization payload.');
      }

      const fullName = [
        response.user?.name?.firstName,
        response.user?.name?.lastName,
      ]
        .filter((part): part is string => !!part)
        .join(' ')
        .trim();

      const res = await api.post<OAuthSignInResponse>('/auth/oauth/apple', {
        identityToken,
        authorizationCode,
        fullName: fullName || undefined,
      });

      if (!res.success || !res.data) {
        throw new Error(res.error?.message ?? 'Apple sign-in failed.');
      }

      await finalizeSignIn(res.data);
    } catch (error) {
      setErrorMessage(formatErrorMessage(error, 'Apple sign-in failed.'));
    } finally {
      setActiveProvider(null);
    }
  }, [appleRedirectUri, finalizeSignIn]);

  useEffect(() => {
    if (status !== 'unauthenticated') {
      setErrorMessage(null);
    }
  }, [status]);

  if (status === 'bootstrapping') {
    return (
      <div className="min-h-screen bg-zinc-950 text-zinc-100">
        <Header />
        <section className="px-6 py-24 pt-28 lg:px-8">
          <div className="mx-auto max-w-3xl">
            <Card className="border-zinc-800 bg-zinc-900/50">
              <CardContent className="flex items-center justify-center gap-3 py-16 text-zinc-400">
                <Loader2 className="h-5 w-5 animate-spin" />
                Checking for an existing browser session...
              </CardContent>
            </Card>
          </div>
        </section>
        <Footer />
      </div>
    );
  }

  if (isAuthenticated) {
    return <Navigate to={redirectTarget} replace />;
  }

  return (
    <div className="min-h-screen bg-zinc-950 text-zinc-100">
      <Header />

      <section className="px-6 py-20 pt-28 lg:px-8">
        <div className="mx-auto grid max-w-5xl gap-8 lg:grid-cols-[1.1fr_0.9fr]">
          <div className="space-y-6">
            <Badge variant="outline" className="border-cyan-700/70 text-cyan-300">
              Browser Account Access
            </Badge>
            <div className="space-y-4">
              <h1 className="text-4xl font-bold tracking-tight text-white sm:text-5xl">
                Sign in to your GearSnitch account
              </h1>
              <p className="max-w-2xl text-lg text-zinc-400">
                Use the same Apple or Google identity you already connected in the
                iOS app. New accounts are provisioned from iPhone first, then the web
                app restores your browser session from a secure refresh cookie.
              </p>
            </div>

            <div className="grid gap-4 sm:grid-cols-2">
              <Card className="border-zinc-800 bg-zinc-900/40">
                <CardContent className="flex items-start gap-3 pt-6">
                  <ShieldCheck className="mt-0.5 h-5 w-5 text-emerald-400" />
                  <div className="space-y-1">
                    <p className="font-medium text-white">Secure session bootstrap</p>
                    <p className="text-sm text-zinc-400">
                      The web app restores access through the backend refresh-cookie flow,
                      not a long-lived browser token in storage.
                    </p>
                  </div>
                </CardContent>
              </Card>
              <Card className="border-zinc-800 bg-zinc-900/40">
                <CardContent className="flex items-start gap-3 pt-6">
                  <div className="mt-1 h-3 w-3 rounded-full bg-cyan-300" />
                  <div className="space-y-1">
                    <p className="font-medium text-white">Shared account data</p>
                    <p className="text-sm text-zinc-400">
                      Profile, orders, devices, and activity calendar stay aligned with the
                      live account records created and maintained by the native app.
                    </p>
                  </div>
                </CardContent>
              </Card>
            </div>
          </div>

          <Card className="border-zinc-800 bg-zinc-900/50">
            <CardHeader className="space-y-3">
              <CardTitle>Choose a provider</CardTitle>
              <p className="text-sm text-zinc-400">
                After sign-in, you’ll be redirected back to{' '}
                <code className="rounded bg-zinc-950 px-1.5 py-0.5 text-zinc-300">
                  {redirectTarget}
                </code>
                .
              </p>
            </CardHeader>
            <CardContent className="space-y-4">
              <GoogleSignInButton
                onCredential={handleGoogleCredential}
                onError={setErrorMessage}
              />

              <Button
                type="button"
                variant="outline"
                className="h-11 w-full justify-center border-zinc-700 bg-zinc-950 text-zinc-100 hover:bg-zinc-900"
                onClick={() => void handleAppleSignIn()}
                disabled={activeProvider !== null || !APPLE_SERVICE_ID}
              >
                {activeProvider === 'apple' ? (
                  <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                ) : (
                  <Apple className="mr-2 h-4 w-4" />
                )}
                Continue with Apple
              </Button>

              {!APPLE_SERVICE_ID && (
                <p className="text-xs text-zinc-500">
                  Apple browser sign-in needs `VITE_APPLE_SERVICE_ID` and a matching redirect URI.
                </p>
              )}

              {activeProvider === 'google' && (
                <p className="text-sm text-cyan-300">Exchanging your Google credential...</p>
              )}

              {errorMessage && (
                <div className="rounded-xl border border-red-900/70 bg-red-950/40 px-4 py-3 text-sm text-red-200">
                  {errorMessage}
                </div>
              )}

              <p className="text-xs leading-6 text-zinc-500">
                Trouble signing in? Make sure the account was created in the iOS app first,
                your web OAuth client IDs match this origin, and the API can set secure auth
                cookies for the browser.
              </p>

              <p className="text-sm text-zinc-500">
                Need the marketing site instead?{' '}
                <Link to="/" className="text-cyan-300 hover:text-cyan-200">
                  Back to the homepage
                </Link>
                .
              </p>
            </CardContent>
          </Card>
        </div>
      </section>

      <Footer />
    </div>
  );
}
