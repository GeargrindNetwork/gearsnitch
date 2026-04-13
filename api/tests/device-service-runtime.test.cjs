const { execFileSync } = require('node:child_process');
const path = require('node:path');

describe('device service runtime regression sweep', () => {
  test('creates bluetooth devices without schema runtime failures', () => {
    const apiRoot = path.join(__dirname, '..');
    const script = `
      const mongoose = require('mongoose');
      const { MongoMemoryServer } = require('mongodb-memory-server');
      const { DeviceService } = require('./src/modules/devices/deviceService.ts');
      const { Device } = require('./src/models/Device.ts');

      (async () => {
        const mongoServer = await MongoMemoryServer.create();
        await mongoose.connect(mongoServer.getUri(), {
          serverSelectionTimeoutMS: 15000,
        });

        try {
          const service = new DeviceService();
          const userId = new mongoose.Types.ObjectId().toString();
          const bluetoothIdentifier = 'debug-ble-device';

          const created = await service.createDevice(userId, {
            name: 'Shawns Apple Watch',
            nickname: null,
            bluetoothIdentifier,
            type: 'tracker',
            isFavorite: true,
          });

          const persisted = await Device.findOne({
            userId: new mongoose.Types.ObjectId(userId),
            identifier: bluetoothIdentifier,
          }).lean();

          if (!persisted) {
            throw new Error('Device was not persisted');
          }

          if (persisted.lastSeenLocation !== undefined) {
            throw new Error('lastSeenLocation should stay undefined for new devices');
          }

          if (created.bluetoothIdentifier !== bluetoothIdentifier) {
            throw new Error('Bluetooth identifier did not round-trip');
          }

          console.log('device-service-runtime-ok');
        } finally {
          await Device.deleteMany({});
          await mongoose.disconnect();
          await mongoServer.stop();
        }
      })().catch((err) => {
        console.error(err);
        process.exit(1);
      });
    `;

    const output = execFileSync(
      process.execPath,
      ['-r', 'tsx/cjs', '-e', script],
      {
        cwd: apiRoot,
        encoding: 'utf8',
        stdio: 'pipe',
      }
    );

    expect(output).toContain('device-service-runtime-ok');
  }, 30000);
});
