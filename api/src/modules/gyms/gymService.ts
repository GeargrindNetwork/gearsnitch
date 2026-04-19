import { Types } from 'mongoose';
import { StatusCodes } from 'http-status-codes';
import { Gym } from '../../models/Gym.js';
import { GymSession } from '../../models/GymSession.js';
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

const EARTH_RADIUS_METERS = 6_371_008.8;

/**
 * Great-circle (haversine) distance between two WGS84 lat/lng points, in meters.
 * Accurate to well within a meter for typical gym-geofence distances.
 */
export function haversineDistanceMeters(
  a: { lat: number; lng: number },
  b: { lat: number; lng: number },
): number {
  const toRad = (deg: number): number => (deg * Math.PI) / 180;
  const lat1 = toRad(a.lat);
  const lat2 = toRad(b.lat);
  const dLat = toRad(b.lat - a.lat);
  const dLng = toRad(b.lng - a.lng);

  const sinDLat = Math.sin(dLat / 2);
  const sinDLng = Math.sin(dLng / 2);
  const h =
    sinDLat * sinDLat
    + Math.cos(lat1) * Math.cos(lat2) * sinDLng * sinDLng;
  const c = 2 * Math.atan2(Math.sqrt(h), Math.sqrt(1 - h));

  return EARTH_RADIUS_METERS * c;
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

  /**
   * Evaluate whether a lat/lng falls inside the geofence of the caller's gym.
   * Returns distance in meters and the inside flag. The gym must belong to the
   * caller (we scope by userId to prevent cross-tenant geofence probing).
   */
  async evaluateLocation(
    userId: string,
    gymId: string,
    lat: number,
    lng: number,
  ): Promise<{
    inside: boolean;
    distanceMeters: number;
    gymId: string;
    evaluatedAt: Date;
  }> {
    const gym = await Gym.findOne({
      _id: assertObjectId(gymId, 'gymId'),
      userId: assertObjectId(userId, 'userId'),
    });

    if (!gym) {
      throw new GymServiceError(StatusCodes.NOT_FOUND, 'Gym not found');
    }

    const [gymLng, gymLat] = gym.location.coordinates;
    const distanceMeters = haversineDistanceMeters(
      { lat, lng },
      { lat: gymLat, lng: gymLng },
    );
    const radius = gym.radiusMeters ?? 100;

    return {
      inside: distanceMeters <= radius,
      distanceMeters: Math.round(distanceMeters * 100) / 100,
      gymId: String(gym._id),
      evaluatedAt: new Date(),
    };
  }

  /**
   * Find gyms within `radiusMeters` of a given point, sorted nearest-first.
   * Uses haversine distance in application code (rather than relying on a
   * Mongo `$geoNear` aggregation) so the behavior is deterministic on
   * in-memory Mongo without requiring the 2dsphere index to be rebuilt.
   * A bounding box pre-filter keeps the scanned set small at scale.
   */
  async findNearby(
    userId: string,
    lat: number,
    lng: number,
    radiusMeters: number,
    limit = 20,
  ): Promise<{
    gyms: Array<{
      _id: string;
      name: string;
      distanceMeters: number;
      address: string | null;
      location: GeoPointInput;
      isDefault: boolean;
    }>;
    scanned: number;
  }> {
    const normalizedUserId = assertObjectId(userId, 'userId');

    // Approx degrees per meter at this latitude for a cheap bounding box.
    const latDegPerMeter = 1 / 111_320;
    const lngDegPerMeter =
      1 / (111_320 * Math.max(Math.cos((lat * Math.PI) / 180), 0.0001));
    const latDelta = radiusMeters * latDegPerMeter;
    const lngDelta = radiusMeters * lngDegPerMeter;

    const candidates = await Gym.find({
      userId: normalizedUserId,
      'location.coordinates.0': { $gte: lng - lngDelta, $lte: lng + lngDelta },
      'location.coordinates.1': { $gte: lat - latDelta, $lte: lat + latDelta },
    });

    const within = candidates
      .map((gym) => {
        const [gymLng, gymLat] = gym.location.coordinates;
        const distanceMeters = haversineDistanceMeters(
          { lat, lng },
          { lat: gymLat, lng: gymLng },
        );
        return { gym, distanceMeters };
      })
      .filter((entry) => entry.distanceMeters <= radiusMeters)
      .sort((a, b) => a.distanceMeters - b.distanceMeters)
      .slice(0, limit);

    return {
      gyms: within.map(({ gym, distanceMeters }) => ({
        _id: String(gym._id),
        name: gym.name,
        distanceMeters: Math.round(distanceMeters * 100) / 100,
        address: null,
        location: {
          type: 'Point',
          coordinates: gym.location.coordinates,
        },
        isDefault: gym.isDefault,
      })),
      scanned: candidates.length,
    };
  }

  /**
   * Check the caller into a gym. Requires that the caller is physically inside
   * the gym geofence. Idempotent: if the caller already has an open session
   * for this gym (no endedAt), that same session is returned.
   */
  async checkIn(
    userId: string,
    gymId: string,
    lat: number,
    lng: number,
  ): Promise<
    | {
        ok: true;
        session: {
          _id: string;
          gymId: string;
          startedAt: Date;
          resumed: boolean;
        };
      }
    | { ok: false; distanceMeters: number }
  > {
    const evaluation = await this.evaluateLocation(userId, gymId, lat, lng);
    if (!evaluation.inside) {
      return { ok: false, distanceMeters: evaluation.distanceMeters };
    }

    const normalizedUserId = assertObjectId(userId, 'userId');
    const normalizedGymId = assertObjectId(gymId, 'gymId');

    const existing = await GymSession.findOne({
      userId: normalizedUserId,
      gymId: normalizedGymId,
      endedAt: null,
    }).sort({ startedAt: -1 });

    if (existing) {
      return {
        ok: true,
        session: {
          _id: String(existing._id),
          gymId: String(existing.gymId),
          startedAt: existing.startedAt,
          resumed: true,
        },
      };
    }

    const gym = await Gym.findById(normalizedGymId);
    const session = await GymSession.create({
      userId: normalizedUserId,
      gymId: normalizedGymId,
      gymName: gym?.name,
      startedAt: new Date(),
      source: 'manual',
      events: [
        {
          type: 'gym_checkin',
          timestamp: new Date(),
          metadata: {
            latitude: lat,
            longitude: lng,
            distanceMeters: evaluation.distanceMeters,
          },
        },
      ],
    });

    return {
      ok: true,
      session: {
        _id: String(session._id),
        gymId: String(session.gymId),
        startedAt: session.startedAt,
        resumed: false,
      },
    };
  }
}
