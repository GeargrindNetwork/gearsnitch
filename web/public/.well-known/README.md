This directory holds well-known URI files served at `/.well-known/` by the production web host.

Current required contents:

- `apple-developer-domain-association.txt` — Sign in with Apple domain verification.
  Provided by Apple when you add `gearsnitch.com` as a Domain under the Services ID
  `com.gearsnitch.web` at
  https://developer.apple.com/account/resources/identifiers/list.
  Apple fetches this file from
  `https://gearsnitch.com/.well-known/apple-developer-domain-association.txt`
  to verify domain ownership. Without it, the Sign in with Apple popup
  silently loops back to the Apple sign-in page.

- `apple-developer-merchantid-domain-association` — Apple Pay (web) domain
  verification. Fetched from Stripe's canonical URL
  (`https://stripe.com/files/apple-pay/apple-developer-merchantid-domain-association`)
  for any merchant using Stripe as the Apple Pay payment processor. Required
  before `stripe apple_pay_domains create --domain-name=gearsnitch.com`
  succeeds. Same file works for any subdomain you register.

Do not commit tokens, keys, or secrets to this directory other than the
verification files Apple / Stripe explicitly tell you to publish here.
