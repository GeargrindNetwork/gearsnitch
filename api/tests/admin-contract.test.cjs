const fs = require('node:fs');
const path = require('node:path');

const apiRoot = path.join(__dirname, '..');

function read(relativePath) {
  return fs.readFileSync(path.join(apiRoot, relativePath), 'utf8');
}

describe('admin module contract', () => {
  const routes = read('src/modules/admin/routes.ts');

  test('all admin routes require authentication AND admin role', () => {
    expect(routes).toContain("router.use(isAuthenticated, hasRole(['admin']))");
  });

  test('all 501 stubs have been removed', () => {
    expect(routes).not.toContain('not yet implemented');
    expect(routes).not.toMatch(/,\s*501\s*\)/);
  });

  test('GET /admin/users supports pagination and search', () => {
    expect(routes).toContain("router.get('/users',");
    expect(routes).toContain('page');
    expect(routes).toContain('limit');
    expect(routes).toContain('search');
    expect(routes).toContain('totalPages');
  });

  test('GET /admin/users escapes regex input to prevent NoSQL injection', () => {
    expect(routes).toMatch(/replace\(\/\[\.\*\+\?\^\$\{\}\(\)\|\[\\\]\\\\\]\/g/);
  });

  test('GET /admin/stats aggregates user, device, session, and subscription counts', () => {
    expect(routes).toContain("router.get('/stats',");
    expect(routes).toContain('User.countDocuments');
    expect(routes).toContain('Device.countDocuments');
    expect(routes).toContain('GymSession.countDocuments');
    expect(routes).toContain('Subscription.countDocuments');
  });

  test('PATCH /admin/users/:id validates request body with Zod', () => {
    expect(routes).toContain("router.patch('/users/:id',");
    expect(routes).toContain('validateBody(updateUserSchema)');
  });

  test('DELETE /admin/users/:id performs soft delete', () => {
    expect(routes).toContain("router.delete('/users/:id',");
    expect(routes).toContain("status: 'deleted'");
    expect(routes).toContain('deletedAt: new Date()');
  });

  test('DELETE prevents self-deletion', () => {
    expect(routes).toContain('Cannot delete your own admin account');
  });

  test('status update schema allows active/suspended/banned', () => {
    expect(routes).toContain("z.enum(['active', 'suspended', 'banned'])");
  });
});
