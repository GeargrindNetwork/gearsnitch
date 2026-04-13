const fs = require('node:fs');
const path = require('node:path');

const apiRoot = path.join(__dirname, '..');

function read(relativePath) {
  return fs.readFileSync(path.join(apiRoot, relativePath), 'utf8');
}

describe('backend core services regression sweep', () => {
  const storeRoutes = read('src/modules/store/routes.ts');
  const deviceRoutes = read('src/modules/devices/routes.ts');
  const gymRoutes = read('src/modules/gyms/routes.ts');
  const userRoutes = read('src/modules/users/routes.ts');
  const workoutRoutes = read('src/modules/workouts/routes.ts');
  const runRoutes = read('src/modules/runs/routes.ts');
  const apiRoutes = read('src/routes/index.ts');

  test('store routes are wired to live services for catalog, cart, and orders', () => {
    expect(storeRoutes).toContain('storeService.listProducts(');
    expect(storeRoutes).toContain('storeService.getProductByReference(');
    expect(storeRoutes).toContain('storeService.addToCart(');
    expect(storeRoutes).toContain('storeService.getCart(');
    expect(storeRoutes).toContain('storeService.updateCartItem(');
    expect(storeRoutes).toContain('storeService.removeCartItem(');
    expect(storeRoutes).toContain('storeService.listOrders(');
    expect(storeRoutes).not.toContain('List store products — not yet implemented');
    expect(storeRoutes).not.toContain('Get product details — not yet implemented');
    expect(storeRoutes).not.toContain('Add to cart — not yet implemented');
    expect(storeRoutes).not.toContain('Get cart — not yet implemented');
    expect(storeRoutes).not.toContain('List orders — not yet implemented');
  });

  test('device routes are wired to live CRUD, status, and location handlers', () => {
    expect(deviceRoutes).toContain('deviceService.listDevices(');
    expect(deviceRoutes).toContain('deviceService.createDevice(');
    expect(deviceRoutes).toContain('deviceService.getDevice(');
    expect(deviceRoutes).toContain('deviceService.updateDevice(');
    expect(deviceRoutes).toContain('deviceService.updateStatus(');
    expect(deviceRoutes).toContain('deviceService.deleteDevice(');
    expect(deviceRoutes).toContain('deviceService.listLocations(');
    expect(deviceRoutes).not.toContain('List devices — not yet implemented');
    expect(deviceRoutes).not.toContain('Register device — not yet implemented');
    expect(deviceRoutes).not.toContain('Get device — not yet implemented');
    expect(deviceRoutes).not.toContain('Update device — not yet implemented');
    expect(deviceRoutes).not.toContain('Remove device — not yet implemented');
  });

  test('gym routes are wired to live CRUD/default handlers and keep deferred flows explicit', () => {
    expect(gymRoutes).toContain('gymService.listGyms(');
    expect(gymRoutes).toContain('gymService.createGym(');
    expect(gymRoutes).toContain('gymService.getGym(');
    expect(gymRoutes).toContain('gymService.updateGym(');
    expect(gymRoutes).toContain('gymService.setDefaultGym(');
    expect(gymRoutes).toContain('gymService.deleteGym(');
    expect(gymRoutes).not.toContain('List gyms — not yet implemented');
    expect(gymRoutes).not.toContain('Get gym details — not yet implemented');
    expect((gymRoutes.match(/StatusCodes\.NOT_IMPLEMENTED/g) || []).length).toBe(3);
    expect(gymRoutes).toContain("router.post('/evaluate', isAuthenticated");
    expect(gymRoutes).toContain("'/events',");
    expect(gymRoutes).toContain("router.get('/nearby', isAuthenticated");
    expect(gymRoutes).toContain("router.post('/:id/check-in', isAuthenticated");
  });

  test('users/me aggregation reads live device and order collections', () => {
    expect(userRoutes).toMatch(/StoreOrder\.countDocuments\(\s*\{\s*userId:\s*user\._id,/s);
    expect(userRoutes).toMatch(/Device\.find\(\{\s*userId:\s*user\._id\s*\}\)\.sort/s);
    expect(userRoutes).toMatch(/StoreOrder\.find\(\{\s*userId:\s*user\._id\s*\}\)\.sort/s);
  });

  test('workout routes are wired to live CRUD and metrics handlers', () => {
    expect(workoutRoutes).toContain("router.get('/metrics/overview'");
    expect(workoutRoutes).toContain('const createWorkoutSchema');
    expect(workoutRoutes).toContain('const updateWorkoutSchema');
    expect(workoutRoutes).toContain('const completeWorkoutSchema');
    expect(workoutRoutes).not.toContain('List workouts — not yet implemented');
    expect(workoutRoutes).not.toContain('Create workout — not yet implemented');
    expect(workoutRoutes).not.toContain('Get workout — not yet implemented');
    expect(workoutRoutes).not.toContain('Update workout — not yet implemented');
    expect(workoutRoutes).not.toContain('Delete workout — not yet implemented');
    expect(workoutRoutes).not.toContain('Complete workout — not yet implemented');
  });

  test('run routes are mounted live with bounded list and completion handlers', () => {
    expect(apiRoutes).toContain("router.use('/runs', runsRoutes);");
    expect(runRoutes).toContain("router.get('/active'");
    expect(runRoutes).toContain("'/:id/complete'");
    expect(runRoutes).toContain('const startRunSchema');
    expect(runRoutes).toContain('const completeRunSchema');
    expect(runRoutes).toContain('Math.min(50');
    expect(runRoutes).not.toContain('List runs — not yet implemented');
    expect(runRoutes).not.toContain('Start run — not yet implemented');
    expect(runRoutes).not.toContain('Complete run — not yet implemented');
  });
});
