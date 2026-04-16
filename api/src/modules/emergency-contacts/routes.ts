import { Router, type Request, type Response } from 'express';
import { Types } from 'mongoose';
import { z } from 'zod';
import { StatusCodes } from 'http-status-codes';
import { isAuthenticated, type JwtPayload } from '../../middleware/auth.js';
import { validateBody } from '../../middleware/validate.js';
import { EmergencyContact } from '../../models/EmergencyContact.js';
import { successResponse, errorResponse } from '../../utils/response.js';

const router = Router();

const createContactSchema = z.object({
  name: z.string().trim().min(1).max(100),
  phone: z.string().trim().min(7).max(20),
  email: z.string().email().max(120).optional().default(''),
  notifyOnPanic: z.boolean().optional().default(true),
  notifyOnDisconnect: z.boolean().optional().default(false),
});

const updateContactSchema = z.object({
  name: z.string().trim().min(1).max(100).optional(),
  phone: z.string().trim().min(7).max(20).optional(),
  email: z.string().email().max(120).optional(),
  notifyOnPanic: z.boolean().optional(),
  notifyOnDisconnect: z.boolean().optional(),
});

function serialize(contact: Record<string, any>) {
  return {
    _id: String(contact._id),
    name: contact.name,
    phone: contact.phone,
    email: contact.email || null,
    notifyOnPanic: contact.notifyOnPanic,
    notifyOnDisconnect: contact.notifyOnDisconnect,
    createdAt: contact.createdAt?.toISOString?.() ?? contact.createdAt,
    updatedAt: contact.updatedAt?.toISOString?.() ?? contact.updatedAt,
  };
}

// GET /emergency-contacts
router.get('/', isAuthenticated, async (req: Request, res: Response) => {
  try {
    const user = req.user as JwtPayload;
    const contacts = await EmergencyContact.find({
      userId: new Types.ObjectId(user.sub),
    })
      .sort({ createdAt: -1 })
      .lean();

    successResponse(res, contacts.map(serialize));
  } catch (err) {
    errorResponse(res, StatusCodes.INTERNAL_SERVER_ERROR, 'Failed to load emergency contacts', (err as Error).message);
  }
});

// POST /emergency-contacts
router.post('/', isAuthenticated, validateBody(createContactSchema), async (req: Request, res: Response) => {
  try {
    const user = req.user as JwtPayload;
    const body = req.body as z.infer<typeof createContactSchema>;

    // Limit to 5 contacts per user
    const count = await EmergencyContact.countDocuments({ userId: new Types.ObjectId(user.sub) });
    if (count >= 5) {
      errorResponse(res, StatusCodes.BAD_REQUEST, 'Maximum 5 emergency contacts allowed');
      return;
    }

    const contact = await EmergencyContact.create({
      userId: new Types.ObjectId(user.sub),
      ...body,
    });

    successResponse(res, serialize(contact.toObject()), StatusCodes.CREATED);
  } catch (err) {
    errorResponse(res, StatusCodes.INTERNAL_SERVER_ERROR, 'Failed to create emergency contact', (err as Error).message);
  }
});

// PATCH /emergency-contacts/:id
router.patch('/:id', isAuthenticated, validateBody(updateContactSchema), async (req: Request, res: Response) => {
  try {
    const user = req.user as JwtPayload;
    const contactId = req.params.id;
    const body = req.body as z.infer<typeof updateContactSchema>;

    const contact = await EmergencyContact.findOneAndUpdate(
      { _id: contactId, userId: new Types.ObjectId(user.sub) },
      { $set: body },
      { new: true }
    ).lean();

    if (!contact) {
      errorResponse(res, StatusCodes.NOT_FOUND, 'Emergency contact not found');
      return;
    }

    successResponse(res, serialize(contact));
  } catch (err) {
    errorResponse(res, StatusCodes.INTERNAL_SERVER_ERROR, 'Failed to update emergency contact', (err as Error).message);
  }
});

// DELETE /emergency-contacts/:id
router.delete('/:id', isAuthenticated, async (req: Request, res: Response) => {
  try {
    const user = req.user as JwtPayload;
    const contactId = req.params.id;

    const result = await EmergencyContact.findOneAndDelete({
      _id: contactId,
      userId: new Types.ObjectId(user.sub),
    });

    if (!result) {
      errorResponse(res, StatusCodes.NOT_FOUND, 'Emergency contact not found');
      return;
    }

    successResponse(res, { deleted: true });
  } catch (err) {
    errorResponse(res, StatusCodes.INTERNAL_SERVER_ERROR, 'Failed to delete emergency contact', (err as Error).message);
  }
});

export default router;
