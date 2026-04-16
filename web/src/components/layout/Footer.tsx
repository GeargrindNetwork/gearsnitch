import { Link } from 'react-router-dom';
import { Separator } from '@/components/ui/separator';
import { APP_RELEASE } from '@/lib/release-meta';

export default function Footer() {
  return (
    <footer className="border-t border-white/5 bg-zinc-950">
      <div className="mx-auto max-w-7xl px-4 py-12 sm:px-6 lg:px-8">
        <div className="grid grid-cols-2 gap-8 md:grid-cols-4">
          {/* Brand */}
          <div className="col-span-2 md:col-span-1">
            <Link to="/" className="flex items-center gap-2">
              <div className="flex h-8 w-8 items-center justify-center rounded-lg bg-gradient-to-br from-cyan-400 to-emerald-400">
                <svg viewBox="0 0 24 24" className="h-5 w-5 text-black" fill="none" stroke="currentColor" strokeWidth="2.5">
                  <path d="M12 2L2 7l10 5 10-5-10-5zM2 17l10 5 10-5M2 12l10 5 10-5" />
                </svg>
              </div>
              <span className="text-lg font-bold text-white">
                Gear<span className="text-cyan-400">Snitch</span>
              </span>
            </Link>
            <p className="mt-3 text-sm text-zinc-500">
              Know your gear. Track your grind.
            </p>
          </div>

          {/* Product */}
          <div>
            <h3 className="mb-3 text-sm font-semibold uppercase tracking-wider text-zinc-400">Product</h3>
            <ul className="space-y-2 text-sm">
              <li><a href="/#features" className="text-zinc-500 transition-colors hover:text-white">Features</a></li>
              <li><Link to="/store" className="text-zinc-500 transition-colors hover:text-white">Store</Link></li>
              <li><a href="#download" className="text-zinc-500 transition-colors hover:text-white">Download</a></li>
            </ul>
          </div>

          {/* Company */}
          <div>
            <h3 className="mb-3 text-sm font-semibold uppercase tracking-wider text-zinc-400">Company</h3>
            <ul className="space-y-2 text-sm">
              <li><Link to="/support" className="text-zinc-500 transition-colors hover:text-white">Support</Link></li>
              <li><a href="mailto:hello@gearsnitch.com" className="text-zinc-500 transition-colors hover:text-white">Contact</a></li>
            </ul>
          </div>

          {/* Legal */}
          <div>
            <h3 className="mb-3 text-sm font-semibold uppercase tracking-wider text-zinc-400">Legal</h3>
            <ul className="space-y-2 text-sm">
              <li><Link to="/privacy" className="text-zinc-500 transition-colors hover:text-white">Privacy Policy</Link></li>
              <li><Link to="/terms" className="text-zinc-500 transition-colors hover:text-white">Terms of Service</Link></li>
              <li><Link to="/support" className="text-zinc-500 transition-colors hover:text-white">Support</Link></li>
            </ul>
          </div>
        </div>

        <Separator className="my-8 bg-white/5" />

        <div className="flex flex-col items-center justify-between gap-4 sm:flex-row">
          <div className="space-y-1 text-center sm:text-left">
            <p className="text-sm text-zinc-600">
              &copy; {new Date().getFullYear()} GearSnitch. All rights reserved.
            </p>
            <p className="text-xs text-zinc-700">
              Web {APP_RELEASE.version}
              {APP_RELEASE.gitSha ? ` • ${APP_RELEASE.gitSha}` : ''}
            </p>
          </div>
          <div className="flex gap-4">
            <a href="https://github.com/GeargrindNetwork/gearsnitch" target="_blank" rel="noopener noreferrer" className="text-zinc-600 transition-colors hover:text-white" aria-label="GitHub">
              <svg className="h-5 w-5" fill="currentColor" viewBox="0 0 24 24"><path d="M12 .297c-6.63 0-12 5.373-12 12 0 5.303 3.438 9.8 8.205 11.385.6.113.82-.258.82-.577 0-.285-.01-1.04-.015-2.04-3.338.724-4.042-1.61-4.042-1.61C4.422 18.07 3.633 17.7 3.633 17.7c-1.087-.744.084-.729.084-.729 1.205.084 1.838 1.236 1.838 1.236 1.07 1.835 2.809 1.305 3.495.998.108-.776.417-1.305.76-1.605-2.665-.3-5.466-1.332-5.466-5.93 0-1.31.465-2.38 1.235-3.22-.135-.303-.54-1.523.105-3.176 0 0 1.005-.322 3.3 1.23.96-.267 1.98-.399 3-.405 1.02.006 2.04.138 3 .405 2.28-1.552 3.285-1.23 3.285-1.23.645 1.653.24 2.873.12 3.176.765.84 1.23 1.91 1.23 3.22 0 4.61-2.805 5.625-5.475 5.92.42.36.81 1.096.81 2.22 0 1.606-.015 2.896-.015 3.286 0 .315.21.69.825.57C20.565 22.092 24 17.592 24 12.297c0-6.627-5.373-12-12-12"/></svg>
            </a>
            <a href="mailto:hello@gearsnitch.com" className="text-zinc-600 transition-colors hover:text-white" aria-label="Email">
              <svg className="h-5 w-5" fill="currentColor" viewBox="0 0 24 24"><path d="M12 12.713l-11.985-9.713h23.97l-11.985 9.713zm-5.425-1.822l-6.575-5.329v12.501l6.575-7.172zm10.85 0l6.575 7.172v-12.501l-6.575 5.329zm-1.557 1.261l-3.868 3.135-3.868-3.135-8.11 8.848h23.956l-8.11-8.848z"/></svg>
            </a>
          </div>
        </div>
      </div>
    </footer>
  );
}
