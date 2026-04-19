/**
 * Landing page entrypoint (RALPH backlog item #36).
 *
 * Thin shell around the A/B framework: `useLandingVariant` decides whether
 * the visitor sees `<LandingV1 />` (control) or `<LandingV2 />` (benefits-
 * forward variant) based on cookie bucketing and an optional `?variant=…`
 * query override. Page-level SEO/chrome lives inside each variant so that
 * meaningful layout changes are self-contained.
 *
 * While the hook is resolving on first client render we render the control
 * (v1) so that the user never sees a blank frame — v1 is the current shipped
 * page and cheap to repaint if the hook flips to v2 a tick later.
 */
import LandingV1 from './landing/LandingV1';
import LandingV2 from './landing/LandingV2';
import { useLandingVariant } from '@/hooks/useLandingVariant';

export default function LandingPage() {
  const { variant } = useLandingVariant();
  if (variant === 'v2') {
    return <LandingV2 />;
  }
  return <LandingV1 />;
}
