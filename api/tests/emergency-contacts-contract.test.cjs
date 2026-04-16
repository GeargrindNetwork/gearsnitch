const fs = require('node:fs');
const path = require('node:path');

const apiRoot = path.join(__dirname, '..');

function read(relativePath) {
  return fs.readFileSync(path.join(apiRoot, relativePath), 'utf8');
}

describe('emergency contacts contract', () => {
  const model = read('src/models/EmergencyContact.ts');
  const routes = read('src/modules/emergency-contacts/routes.ts');
  const routeIndex = read('src/routes/index.ts');

  test('EmergencyContact model has required userId, name, phone fields', () => {
    expect(model).toContain('userId: { type: Schema.Types.ObjectId');
    expect(model).toContain('name: { type: String, required: true');
    expect(model).toContain('phone: { type: String, required: true');
  });

  test('EmergencyContact has user-scoped index', () => {
    expect(model).toContain('EmergencyContactSchema.index({ userId: 1 })');
  });

  test('EmergencyContact has notifyOnPanic and notifyOnDisconnect flags', () => {
    expect(model).toContain('notifyOnPanic: { type: Boolean');
    expect(model).toContain('notifyOnDisconnect: { type: Boolean');
  });

  test('routes module is registered in route index', () => {
    expect(routeIndex).toContain("import emergencyContactsRoutes from '../modules/emergency-contacts/routes.js'");
    expect(routeIndex).toContain("router.use('/emergency-contacts', emergencyContactsRoutes)");
  });

  test('all CRUD endpoints require authentication', () => {
    expect(routes).toContain("router.get('/', isAuthenticated");
    expect(routes).toContain("router.post('/', isAuthenticated, validateBody(createContactSchema)");
    expect(routes).toContain("router.patch('/:id', isAuthenticated, validateBody(updateContactSchema)");
    expect(routes).toContain("router.delete('/:id', isAuthenticated");
  });

  test('contact creation limits to 5 per user', () => {
    expect(routes).toContain('Maximum 5 emergency contacts allowed');
    expect(routes).toContain('count >= 5');
  });

  test('contact schemas validate phone length (7-20 chars)', () => {
    expect(routes).toContain('.min(7).max(20)');
  });

  test('contact update/delete enforce user ownership', () => {
    expect(routes).toContain("userId: new Types.ObjectId(user.sub)");
  });
});
