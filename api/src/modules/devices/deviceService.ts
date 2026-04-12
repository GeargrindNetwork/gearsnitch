import { Types } from 'mongoose';
import { StatusCodes } from 'http-status-codes';
import { Device } from '../../models/Device.js';
import { DeviceShare } from '../../models/DeviceShare.js';

const SUPPORTED_STATUSES = [
  'registered',
  'active',
  'inactive',
  'connected',
  'monitoring',
  'disconnected',
  'lost',
  'reconnected',
] as const;

type DeviceStatus = (typeof SUPPORTED_STATUSES)[number];

export class DeviceServiceError extends Error {
  constructor(
    readonly statusCode: number,
    message: string,
  ) {
    super(message);
    this.name = 'DeviceServiceError';
  }
}

interface CreateDeviceInput {
  name: string;
  bluetoothIdentifier: string;
  type: 'earbuds' | 'tracker' | 'belt' | 'bag' | 'other';
}

interface UpdateDeviceInput {
  name?: string;
  nickname?: string | null;
  type?: 'earbuds' | 'tracker' | 'belt' | 'bag' | 'other';
  isFavorite?: boolean;
}

interface DeviceResponse {
  _id: string;
  name: string;
  nickname: string | null;
  type: string;
  bluetoothIdentifier: string;
  status: string;
  isFavorite: boolean;
  firmwareVersion: string | null;
  signalStrength: number | null;
  lastSeenAt: Date | null;
  isMonitoring: boolean;
  createdAt: Date;
}

interface DeviceDetailResponse extends DeviceResponse {
  sharedWith: string[];
}

interface DeviceLocationResponse {
  _id: string;
  name: string;
  latitude: number;
  longitude: number;
  lastSeenAt: string;
  rssi: number | null;
  battery: number | null;
  isConnected: boolean;
}

function assertObjectId(value: string, fieldName: string): Types.ObjectId {
  if (!Types.ObjectId.isValid(value)) {
    throw new DeviceServiceError(
      StatusCodes.BAD_REQUEST,
      `${fieldName} must be a valid ObjectId`,
    );
  }

  return new Types.ObjectId(value);
}

function normalizeStatus(value: string): DeviceStatus {
  if (!SUPPORTED_STATUSES.includes(value as DeviceStatus)) {
    throw new DeviceServiceError(StatusCodes.BAD_REQUEST, 'Unsupported device status');
  }

  return value as DeviceStatus;
}

function serializeDevice(
  device: InstanceType<typeof Device>,
): DeviceResponse {
  return {
    _id: String(device._id),
    name: device.name,
    nickname: device.nickname ?? null,
    type: device.type,
    bluetoothIdentifier: device.identifier,
    status: device.status,
    isFavorite: device.isFavorite === true,
    firmwareVersion: device.firmwareVersion ?? null,
    signalStrength: device.lastSignalStrength ?? null,
    lastSeenAt: device.lastSeenAt ?? null,
    isMonitoring: device.monitoringEnabled,
    createdAt: device.createdAt,
  };
}

export class DeviceService {
  async listDevices(userId: string): Promise<DeviceResponse[]> {
    const devices = await Device.find({
      userId: assertObjectId(userId, 'userId'),
    }).sort({ isFavorite: -1, updatedAt: -1, createdAt: -1 });

    return devices.map((device) => serializeDevice(device));
  }

  async createDevice(
    userId: string,
    input: CreateDeviceInput,
  ): Promise<DeviceResponse> {
    const normalizedUserId = assertObjectId(userId, 'userId');

    let device = await Device.findOne({
      userId: normalizedUserId,
      identifier: input.bluetoothIdentifier,
    });

    if (!device) {
      device = await Device.create({
        userId: normalizedUserId,
        name: input.name,
        type: input.type,
        identifier: input.bluetoothIdentifier,
        status: 'monitoring',
        monitoringEnabled: true,
        lastSeenAt: new Date(),
      });
    } else {
      device.name = input.name;
      device.type = input.type;
      device.status = 'monitoring';
      device.monitoringEnabled = true;
      device.lastSeenAt = new Date();
      await device.save();
    }

    return serializeDevice(device);
  }

  async getDevice(userId: string, deviceId: string): Promise<DeviceDetailResponse> {
    const device = await Device.findOne({
      _id: assertObjectId(deviceId, 'deviceId'),
      userId: assertObjectId(userId, 'userId'),
    });

    if (!device) {
      throw new DeviceServiceError(StatusCodes.NOT_FOUND, 'Device not found');
    }

    const shares = await DeviceShare.find({ deviceId: device._id }).select(
      'sharedWithUserId',
    );

    return {
      ...serializeDevice(device),
      sharedWith: shares.map((share) => String(share.sharedWithUserId)),
    };
  }

  async updateDevice(
    userId: string,
    deviceId: string,
    input: UpdateDeviceInput,
  ): Promise<DeviceDetailResponse> {
    const device = await Device.findOne({
      _id: assertObjectId(deviceId, 'deviceId'),
      userId: assertObjectId(userId, 'userId'),
    });

    if (!device) {
      throw new DeviceServiceError(StatusCodes.NOT_FOUND, 'Device not found');
    }

    if (input.name !== undefined) {
      device.name = input.name;
    }

    if (input.nickname !== undefined) {
      const normalizedNickname = input.nickname?.trim() ?? '';
      device.nickname = normalizedNickname.length > 0 ? normalizedNickname : null;
    }

    if (input.type !== undefined) {
      device.type = input.type;
    }

    if (input.isFavorite !== undefined) {
      device.isFavorite = input.isFavorite;
    }

    await device.save();

    const shares = await DeviceShare.find({ deviceId: device._id }).select(
      'sharedWithUserId',
    );

    return {
      ...serializeDevice(device),
      sharedWith: shares.map((share) => String(share.sharedWithUserId)),
    };
  }

  async updateStatus(
    userId: string,
    deviceId: string,
    nextStatusValue: string,
  ): Promise<void> {
    const nextStatus = normalizeStatus(nextStatusValue);
    const device = await Device.findOne({
      _id: assertObjectId(deviceId, 'deviceId'),
      userId: assertObjectId(userId, 'userId'),
    });

    if (!device) {
      throw new DeviceServiceError(StatusCodes.NOT_FOUND, 'Device not found');
    }

    device.status = nextStatus;
    device.monitoringEnabled = nextStatus === 'monitoring';
    device.lastSeenAt = new Date();
    await device.save();
  }

  async deleteDevice(userId: string, deviceId: string): Promise<void> {
    const device = await Device.findOneAndDelete({
      _id: assertObjectId(deviceId, 'deviceId'),
      userId: assertObjectId(userId, 'userId'),
    });

    if (!device) {
      throw new DeviceServiceError(StatusCodes.NOT_FOUND, 'Device not found');
    }

    await DeviceShare.deleteMany({ deviceId: device._id });
  }

  async listLocations(userId: string): Promise<DeviceLocationResponse[]> {
    const devices = await Device.find({
      userId: assertObjectId(userId, 'userId'),
      'lastSeenLocation.coordinates.1': { $exists: true },
      lastSeenAt: { $ne: null },
    }).sort({ updatedAt: -1 });

    return devices
      .filter((device) => device.lastSeenLocation?.coordinates.length === 2)
      .map((device) => ({
        _id: String(device._id),
        name: device.name,
        latitude: device.lastSeenLocation!.coordinates[1],
        longitude: device.lastSeenLocation!.coordinates[0],
        lastSeenAt: device.lastSeenAt?.toISOString() ?? new Date(0).toISOString(),
        rssi: device.lastSignalStrength ?? null,
        battery: null,
        isConnected: ['connected', 'monitoring', 'reconnected'].includes(
          device.status,
        ),
      }));
  }
}
