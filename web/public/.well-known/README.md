This directory holds well-known URI files served at `/.well-known/` by the production web host.

Current required contents:

- `apple-developer-domain-association.txt` — provided by Apple when you add
  `gearsnitch.com` as a Domain under the Services ID `com.gearsnitch.web`
  at https://developer.apple.com/account/resources/identifiers/list.
  Apple fetches this file from `https://gearsnitch.com/.well-known/apple-developer-domain-association.txt`
  to verify domain ownership. Without it, the Sign in with Apple popup
  silently loops back to the Apple sign-in page.

Do not commit tokens, keys, or secrets to this directory other than the
verification files Apple explicitly tells you to publish here.
