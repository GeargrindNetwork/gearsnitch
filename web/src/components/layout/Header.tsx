import { useState } from 'react';
import { Link } from 'react-router-dom';
import { Button } from '@/components/ui/button';
import { Sheet, SheetContent, SheetTrigger } from '@/components/ui/sheet';
import { useAuth } from '@/lib/auth';
import { ThemeToggle } from '@/lib/theme';

export default function Header() {
  const [open, setOpen] = useState(false);
  const { isAuthenticated } = useAuth();

  const navLinks = [
    { label: 'Features', href: '/#features' },
    { label: 'How It Works', href: '/#how-it-works' },
    { label: 'Store', href: '/store' },
    ...(isAuthenticated
      ? [
          { label: 'Dashboard', href: '/dashboard', route: true },
          { label: 'Runs', href: '/runs', route: true },
          { label: 'Metrics', href: '/metrics', route: true },
          { label: 'Calories', href: '/calories', route: true },
          { label: 'Alerts', href: '/alerts', route: true },
          { label: 'Referrals', href: '/referrals', route: true },
        ]
      : []),
  ];

  return (
    <header className="fixed top-0 left-0 right-0 z-50 border-b border-border/50 bg-background/80 backdrop-blur-xl">
      <div className="mx-auto flex h-16 max-w-7xl items-center justify-between px-4 sm:px-6 lg:px-8">
        {/* Logo */}
        <Link to="/" className="flex items-center gap-2">
          <div className="flex h-8 w-8 items-center justify-center rounded-lg bg-gradient-to-br from-cyan-400 to-emerald-400">
            <svg viewBox="0 0 24 24" className="h-5 w-5 text-black" fill="none" stroke="currentColor" strokeWidth="2.5">
              <path d="M12 2L2 7l10 5 10-5-10-5zM2 17l10 5 10-5M2 12l10 5 10-5" />
            </svg>
          </div>
          <span className="text-lg font-bold tracking-tight text-foreground">
            Gear<span className="text-cyan-500 dark:text-cyan-400">Snitch</span>
          </span>
        </Link>

        {/* Desktop Nav */}
        <nav className="hidden items-center gap-8 md:flex">
          {navLinks.map((link) => (
            link.route ? (
              <Link
                key={link.label}
                to={link.href}
                className="text-sm font-medium text-muted-foreground transition-colors hover:text-foreground"
              >
                {link.label}
              </Link>
            ) : (
              <a
                key={link.label}
                href={link.href}
                className="text-sm font-medium text-muted-foreground transition-colors hover:text-foreground"
              >
                {link.label}
              </a>
            )
          ))}
        </nav>

        {/* Desktop CTA */}
        <div className="hidden items-center gap-2 md:flex">
          <ThemeToggle />
          <Link to={isAuthenticated ? '/account' : '/sign-in'}>
            <Button variant="ghost" className="text-muted-foreground hover:text-foreground">
              {isAuthenticated ? 'My Account' : 'Sign In'}
            </Button>
          </Link>
          <a href="#download">
            <Button className="bg-gradient-to-r from-cyan-500 to-emerald-500 font-semibold text-black hover:from-cyan-400 hover:to-emerald-400">
              Download App
            </Button>
          </a>
        </div>

        {/* Mobile Menu */}
        <div className="flex items-center gap-1 md:hidden">
          <ThemeToggle />
          <Sheet open={open} onOpenChange={setOpen}>
            <SheetTrigger className="inline-flex h-10 w-10 items-center justify-center rounded-md text-muted-foreground hover:bg-muted hover:text-foreground">
              <svg viewBox="0 0 24 24" className="h-6 w-6" fill="none" stroke="currentColor" strokeWidth="2">
                <path d="M4 6h16M4 12h16M4 18h16" />
              </svg>
            </SheetTrigger>
            <SheetContent side="right" className="w-72 border-border bg-background">
              <nav className="mt-8 flex flex-col gap-4">
                {navLinks.map((link) => (
                  link.route ? (
                    <Link
                      key={link.label}
                      to={link.href}
                      onClick={() => setOpen(false)}
                      className="rounded-lg px-4 py-3 text-base font-medium text-muted-foreground transition-colors hover:bg-muted hover:text-foreground"
                    >
                      {link.label}
                    </Link>
                  ) : (
                    <a
                      key={link.label}
                      href={link.href}
                      onClick={() => setOpen(false)}
                      className="rounded-lg px-4 py-3 text-base font-medium text-muted-foreground transition-colors hover:bg-muted hover:text-foreground"
                    >
                      {link.label}
                    </a>
                  )
                ))}
                <div className="mt-4 border-t border-border pt-4">
                  <Link to={isAuthenticated ? '/account' : '/sign-in'} onClick={() => setOpen(false)}>
                    <Button variant="ghost" className="w-full justify-start text-muted-foreground">
                      {isAuthenticated ? 'My Account' : 'Sign In'}
                    </Button>
                  </Link>
                  <a href="#download" onClick={() => setOpen(false)}>
                    <Button className="mt-2 w-full bg-gradient-to-r from-cyan-500 to-emerald-500 font-semibold text-black">
                      Download App
                    </Button>
                  </a>
                </div>
              </nav>
            </SheetContent>
          </Sheet>
        </div>
      </div>
    </header>
  );
}
