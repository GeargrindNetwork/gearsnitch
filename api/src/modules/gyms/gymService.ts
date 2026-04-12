import { Types } from 'mongoose';
import { StatusCodes } from 'http-status-codes';
import { Gym } from '../../models/Gym.js';
import { User } from '../../models/User.js';

export class GymServiceError extends Error {
  constructor(
    readonly statusCode: number,
    message: string,
  ) {
    super(message);
    this.name = 'GymServiceError';
  }
}

interface GeoPointInput {
  type: 'Point';
  coordinates: [number, number];
}

interface CreateGymInput {
  name: string;
  location: GeoPointInput;
  radiusMeters: number;
  isDefault?: boolean;
}

interface UpdateGymInput {
  name?: string;
  location?: GeoPointInput;
  radiusMeters?: number;
  isDefault?: boolean;
}

interface GymResponse {
  _id: string;
  name: string;
  radiusMeters: number;
  isDefault: boolean;
  location: GeoPointInput;
  createdAt: Date;
  updatedAt: Date;
}

function assertObjectId(value: string, fieldName: string): Types.ObjectId {
  if (!Types.ObjectId.isValid(value)) {
    throw new GymServiceError(
      StatusCodes.BAD_REQUEST,
      `${fieldName} must be a valid ObjectId`,
    );
  }

  return new Types.ObjectId(value);
}

function serializeGym(gym: InstanceType<typeof Gym>): GymResponse {
  return {
    _id: String(gym._id),
    name: gym.name,
    radiusMeters: gym.radiusMeters,
    isDefault: gym.isDefault,
    location: {
      type: 'Point',
      coordinates: gym.location.coordinates,
    },
    createdAt: gym.createdAt,
    updatedAt: gym.updatedAt,
  };
}

export class GymService {
  async listGyms(userId: string): Promise<GymResponse[]> {
    const gyms = await Gym.find({
      userId: assertObjectId(userId, 'userId'),
    }).sort({ isDefault: -1, createdAt: -1 });

    return gyms.map((gym) => serializeGym(gym));
  }

  async createGym(userId: string, input: CreateGymInput): Promise<GymResponse> {
    const normalizedUserId = assertObjectId(userId, 'userId');
    const existingCount = await Gym.countDocuments({ userId: normalizedUserId });
    const shouldBeDefault = input.isDefault || existingCount === 0;

    if (shouldBeDefault) {
      await Gym.updateMany({ userId: normalizedUserId }, { isDefault: false });
    }

    const gym = await Gym.create({
      userId: normalizedUserId,
      name: input.name,
      location: input.location,
      radiusMeters: input.radiusMeters,
      isDefault: shouldBeDefault,
    });

    if (shouldBeDefault) {
      await User.findByIdAndUpdate(normalizedUserId, { defaultGymId: gym._id });
    }

    return serializeGym(gym);
  }

  async getGym(userId: string, gymId: string): Promise<GymResponse> {
    const gym = await Gym.findOne({
      _id: assertObjectId(gymId, 'gymId'),
      userId: assertObjectId(userId, 'userId'),
    });

    if (!gym) {
      throw new GymServiceError(StatusCodes.NOT_FOUND, 'Gym not found');
    }

    return serializeGym(gym);
  }

  async updateGym(
    userId: string,
    gymId: string,
    input: UpdateGymInput,
  ): Promise<GymResponse> {
    const normalizedUserId = assertObjectId(userId, 'userId');
    const gym = await Gym.findOne({
      _id: assertObjectId(gymId, 'gymId'),
      userId: normalizedUserId,
    });

    if (!gym) {
      throw new GymServiceError(StatusCodes.NOT_FOUND, 'Gym not found');
    }

    if (input.name !== undefined) {
      gym.name = input.name;
    }

    if (input.location !== undefined) {
      gym.location = input.location;
    }

    if (input.radiusMeters !== undefined) {
      gym.radiusMeters = input.radiusMeters;
    }

    await gym.save();

    if (input.isDefault) {
      await this.setDefaultGym(userId, gymId);
      const refreshedGym = await Gym.findById(gym._id);
      if (!refreshedGym) {
        throw new GymServiceError(StatusCodes.NOT_FOUND, 'Gym not found');
      }
      return serializeGym(refreshedGym);
    }

    return serializeGym(gym);
  }

  async deleteGym(userId: string, gymId: string): Promise<void> {
    const normalizedUserId = assertObjectId(userId, 'userId');
    const gym = await Gym.findOneAndDelete({
      _id: assertObjectId(gymId, 'gymId'),
      userId: normalizedUserId,
    });

    if (!gym) {
      throw new GymServiceError(StatusCodes.NOT_FOUND, 'Gym not found');
    }

    if (gym.isDefault) {
      await User.findByIdAndUpdate(normalizedUserId, { defaultGymId: null });
    }
  }

  async setDefaultGym(userId: string, gymId: string): Promise<GymResponse> {
    const normalizedUserId = assertObjectId(userId, 'userId');
    const normalizedGymId = assertObjectId(gymId, 'gymId');

    const gym = await Gym.findOne({
      _id: normalizedGymId,
      userId: normalizedUserId,
    });

    if (!gym) {
      throw new GymServiceError(StatusCodes.NOT_FOUND, 'Gym not found');
    }

    await Gym.updateMany({ userId: normalizedUserId }, { isDefault: false });
    gym.isDefault = true;
    await gym.save();
    await User.findByIdAndUpdate(normalizedUserId, { defaultGymId: gym._id });

    return serializeGym(gym);
  }
}
