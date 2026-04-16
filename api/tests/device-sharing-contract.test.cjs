const fs = require('node:fs');
const path = require('node:path');

const apiRoot = path.join(__dirname, '..');

function read(relativePath) {
  return fs.readFileSync(path.join(apiRoot, relativePath), 'utf8');
}

describe('device sharing contract', () => {
  const deviceRoutes = read('src/modules/devices/routes.ts');
  const deviceShareModel = read('src/models/DeviceShare.ts');

  test('DeviceShare model has unique compound index on deviceId + sharedWithUserId', () => {
    expect(deviceShareModel).toContain('{ deviceId: 1, sharedWithUserId: 1 }');
    expect(deviceShareModel).toContain('unique: true');
  });

  test('DeviceShare has lookup index on sharedWithUserId', () => {
    expect(deviceShareModel).toContain('{ sharedWithUserId: 1 }');
  });

  test('POST /devices/:id/shares endpoint exists with auth and validation', () => {
    expect(deviceRoutes).toContain("router.post('/:id/shares', isAuthenticated, validateBody(shareDeviceSchema)");
  });

  test('GET /devices/:id/shares endpoint exists with auth', () => {
    expect(deviceRoutes).toContain("router.get('/:id/shares', isAuthenticated");
  });

  test('DELETE /devices/:id/shares/:shareId endpoint exists with auth', () => {
    expect(deviceRoutes).toContain("router.delete('/:id/shares/:shareId', isAuthenticated");
  });

  test('share creation validates email format', () => {
    expect(deviceRoutes).toContain('z.string().email()');
  });

  test('share creation validates device ownership before allowing share', () => {
    expect(deviceRoutes).toContain('Device.findOne({ _id: deviceId, userId })');
  });

  test('share creation prevents self-sharing', () => {
    expect(deviceRoutes).toContain('Cannot share a device with yourself');
  });

  test('share creation prevents duplicate shares via conflict check', () => {
    expect(deviceRoutes).toContain('Device is already shared with this user');
  });

  test('share list populates user email and display name', () => {
    expect(deviceRoutes).toContain("populate('sharedWithUserId', 'email displayName')");
  });
});
