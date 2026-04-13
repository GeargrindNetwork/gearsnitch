const { execFileSync } = require('node:child_process');
const path = require('node:path');

describe('device event history runtime regression sweep', () => {
  test('records connect and disconnect events with GPS snapshots', () => {
    const apiRoot = path.join(__dirname, '..');
    const script = `
      const mongoose = require('mongoose');
      const { MongoMemoryServer } = require('mongodb-memory-server');
      const { DeviceService } = require('./src/modules/devices/deviceService.ts');
      const { Device } = require('./src/models/Device.ts');
      const { DeviceEvent } = require('./src/models/DeviceEvent.ts');

      (async () => {
        const mongoServer = await MongoMemoryServer.create();
        await mongoose.connect(mongoServer.getUri(), {
          serverSelectionTimeoutMS: 15000,
        });

        try {
          const service = new DeviceService();
          const userId = new mongoose.Types.ObjectId().toString();
          const created = await service.createDevice(userId, {
            name: 'Gym Earbuds',
            nickname: null,
            bluetoothIdentifier: 'gym-earbuds-01',
            type: 'earbuds',
            isFavorite: true,
          });

          await service.recordEvent(userId, created._id, {
            action: 'connect',
            occurredAt: new Date('2026-04-12T17:00:00.000Z'),
            location: {
              type: 'Point',
              coordinates: [-122.4064, 37.7858],
            },
            signalStrength: -52,
            source: 'ios',
          });

          await service.recordEvent(userId, created._id, {
            action: 'disconnect',
            occurredAt: new Date('2026-04-12T18:12:00.000Z'),
            location: {
              type: 'Point',
              coordinates: [-122.4051, 37.7862],
            },
            signalStrength: -81,
            source: 'ios',
          });

          const device = await Device.findById(created._id).lean();
          const events = await DeviceEvent.find({ deviceId: created._id }).sort({ occurredAt: 1 }).lean();

          if (!device) {
            throw new Error('Device was not persisted');
          }

          if (device.status !== 'disconnected') {
            throw new Error(\`Expected device status to be disconnected, received \${device.status}\`);
          }

          if (!device.lastSeenLocation || device.lastSeenLocation.coordinates[0] !== -122.4051) {
            throw new Error('Device last seen location was not updated from disconnect event');
          }

          if (events.length !== 2) {
            throw new Error(\`Expected 2 device events, received \${events.length}\`);
          }

          if (events[0].action !== 'connect' || events[1].action !== 'disconnect') {
            throw new Error('Device events were not stored in the expected order');
          }

          console.log('device-event-history-runtime-ok');
        } finally {
          await DeviceEvent.deleteMany({});
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

    expect(output).toContain('device-event-history-runtime-ok');
  }, 30000);
});
