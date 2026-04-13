import { Types } from 'mongoose';
import { StatusCodes } from 'http-status-codes';
import { Device } from '../../models/Device.js';
import { DeviceEvent } from '../../models/DeviceEvent.js';
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
  nickname?: string | null;
  bluetoothIdentifier: string;
  type: 'earbuds' | 'tracker' | 'belt' | 'bag' | 'other';
  isFavorite?: boolean;
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

interface DeviceLocationInput {
  type: 'Point';
  coordinates: [number, number];
}

interface UpdateStatusInput {
  status: string;
  lastSeenLocation?: DeviceLocationInput;
  lastSignalStrength?: number;
  recordedAt?: Date;
}

interface RecordDeviceEventInput {
  action: 'connect' | 'disconnect';
  occurredAt?: Date;
  location?: DeviceLocationInput;
  signalStrength?: number;
  source?: 'ios' | 'web' | 'system';
  metadata?: Record<string, unknown> | null;
}

interface DeviceEventResponse {
  _id: string;
  deviceId: string;
  deviceName: string;
  action: 'connect' | 'disconnect';
  occurredAt: Date;
  latitude: number | null;
  longitude: number | null;
  signalStrength: number | null;
  source: 'ios' | 'web' | 'system';
  metadata: Record<string, unknown> | null;
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

function serializeDeviceEvent(
  device: InstanceType<typeof Device>,
  event: InstanceType<typeof DeviceEvent>,
): DeviceEventResponse {
  const coordinates = event.location?.coordinates ?? null;

  return {
    _id: String(event._id),
    deviceId: String(device._id),
    deviceName: device.name,
    action: event.action,
    occurredAt: event.occurredAt,
    latitude: coordinates ? coordinates[1] : null,
    longitude: coordinates ? coordinates[0] : null,
    signalStrength: event.signalStrength ?? null,
    source: event.source,
    metadata:
      event.metadata && typeof event.metadata === 'object'
        ? (event.metadata as Record<string, unknown>)
        : null,
  };
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

function normalizeOptionalText(value: string | null | undefined): string | null {
  const trimmed = value?.trim() ?? '';
  return trimmed.length > 0 ? trimmed : null;
}

function applyDeviceSnapshot(
  device: InstanceType<typeof Device>,
  nextStatus: DeviceStatus,
  options?: {
    location?: DeviceLocationInput;
    signalStrength?: number;
    recordedAt?: Date;
    updateMonitoringFlag?: boolean;
  },
): void {
  device.status = nextStatus;

  if (options?.updateMonitoringFlag === true) {
    device.monitoringEnabled = nextStatus === 'monitoring';
  }

  device.lastSeenAt = options?.recordedAt ?? new Date();

  if (options?.location) {
    device.lastSeenLocation = options.location;
  }

  if (options?.signalStrength !== undefined) {
    device.lastSignalStrength = options.signalStrength;
  }
}

export class DeviceService {
  private async clearPinnedDevices(
    userId: Types.ObjectId,
    exceptDeviceId?: Types.ObjectId,
  ): Promise<void> {
    const query: {
      userId: Types.ObjectId;
      isFavorite: true;
      _id?: { $ne: Types.ObjectId };
    } = {
      userId,
      isFavorite: true,
    };

    if (exceptDeviceId) {
      query._id = { $ne: exceptDeviceId };
    }

    await Device.updateMany(query, {
      $set: { isFavorite: false },
    });
  }

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
    const hasPinnedDevice =
      (await Device.exists({ userId: normalizedUserId, isFavorite: true })) != null;
    const shouldPinDevice = input.isFavorite ?? !hasPinnedDevice;
    const normalizedNickname = normalizeOptionalText(input.nickname);

    let device = await Device.findOne({
      userId: normalizedUserId,
      identifier: input.bluetoothIdentifier,
    });

    if (!device) {
      device = await Device.create({
        userId: normalizedUserId,
        name: input.name,
        nickname: normalizedNickname,
        type: input.type,
        identifier: input.bluetoothIdentifier,
        status: 'monitoring',
        isFavorite: shouldPinDevice,
        monitoringEnabled: true,
        lastSeenAt: new Date(),
      });
    } else {
      device.name = input.name;
      device.nickname = normalizedNickname;
      device.type = input.type;
      device.status = 'monitoring';
      device.isFavorite = shouldPinDevice;
      device.monitoringEnabled = true;
      device.lastSeenAt = new Date();
      await device.save();
    }

    if (shouldPinDevice) {
      await this.clearPinnedDevices(normalizedUserId, device._id);
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

    if (input.isFavorite === true) {
      await this.clearPinnedDevices(assertObjectId(userId, 'userId'), device._id);
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
    input: UpdateStatusInput,
  ): Promise<void> {
    const nextStatus = normalizeStatus(input.status);
    const device = await Device.findOne({
      _id: assertObjectId(deviceId, 'deviceId'),
      userId: assertObjectId(userId, 'userId'),
    });

    if (!device) {
      throw new DeviceServiceError(StatusCodes.NOT_FOUND, 'Device not found');
    }

    applyDeviceSnapshot(device, nextStatus, {
      location: input.lastSeenLocation,
      signalStrength: input.lastSignalStrength,
      recordedAt: input.recordedAt,
      updateMonitoringFlag: true,
    });
    await device.save();
  }

  async recordEvent(
    userId: string,
    deviceId: string,
    input: RecordDeviceEventInput,
  ): Promise<DeviceEventResponse> {
    const normalizedUserId = assertObjectId(userId, 'userId');
    const normalizedDeviceId = assertObjectId(deviceId, 'deviceId');
    const device = await Device.findOne({
      _id: normalizedDeviceId,
      userId: normalizedUserId,
    });

    if (!device) {
      throw new DeviceServiceError(StatusCodes.NOT_FOUND, 'Device not found');
    }

    const occurredAt = input.occurredAt ?? new Date();
    const nextStatus: DeviceStatus = input.action === 'connect' ? 'connected' : 'disconnected';

    const event = await DeviceEvent.create({
      userId: normalizedUserId,
      deviceId: normalizedDeviceId,
      action: input.action,
      occurredAt,
      location: input.location,
      signalStrength: input.signalStrength ?? null,
      source: input.source ?? 'ios',
      metadata: input.metadata ?? undefined,
    });

    applyDeviceSnapshot(device, nextStatus, {
      location: input.location,
      signalStrength: input.signalStrength,
      recordedAt: occurredAt,
      updateMonitoringFlag: false,
    });
    await device.save();

    return serializeDeviceEvent(device, event);
  }

  async listEvents(userId: string, deviceId: string): Promise<DeviceEventResponse[]> {
    const normalizedUserId = assertObjectId(userId, 'userId');
    const normalizedDeviceId = assertObjectId(deviceId, 'deviceId');
    const device = await Device.findOne({
      _id: normalizedDeviceId,
      userId: normalizedUserId,
    });

    if (!device) {
      throw new DeviceServiceError(StatusCodes.NOT_FOUND, 'Device not found');
    }

    const events = await DeviceEvent.find({
      userId: normalizedUserId,
      deviceId: normalizedDeviceId,
    }).sort({ occurredAt: -1, createdAt: -1 });

    return events.map((event) => serializeDeviceEvent(device, event));
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
    await DeviceEvent.deleteMany({ deviceId: device._id });
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
