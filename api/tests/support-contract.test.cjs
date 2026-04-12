const fs = require('node:fs');
const path = require('node:path');

const apiRoot = path.join(__dirname, '..');

function read(relativePath) {
  return fs.readFileSync(path.join(apiRoot, relativePath), 'utf8');
}

describe('support center contract regression sweep', () => {
  const supportRoutes = read('src/modules/support/routes.ts');
  const authMiddleware = read('src/middleware/auth.ts');

  test('support ticket creation can attach the current user without forcing auth', () => {
    expect(authMiddleware).toContain('export async function attachUserIfPresent');
    expect(supportRoutes).toContain("router.post('/tickets', attachUserIfPresent");
    expect(supportRoutes).toContain('userId,');
    expect(supportRoutes).toContain('ticket: serializeTicket(created)');
  });

  test('support FAQ stays product-complete for both web and iOS clients', () => {
    expect(supportRoutes).toContain("router.get('/faq'");
    expect(supportRoutes).toContain('How do I connect my BLE fitness gear?');
    expect(supportRoutes).toContain('How do I manage my subscription?');
    expect(supportRoutes).toContain('What devices are compatible with GearSnitch?');
  });
});
