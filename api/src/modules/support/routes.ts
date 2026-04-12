import { Router, type Request } from 'express';
import { z } from 'zod';
import { Types } from 'mongoose';
import { StatusCodes } from 'http-status-codes';
import {
  attachUserIfPresent,
  isAuthenticated,
  type JwtPayload,
} from '../../middleware/auth.js';
import { SupportTicket } from '../../models/SupportTicket.js';
import { User } from '../../models/User.js';
import { errorResponse, successResponse } from '../../utils/response.js';

const router = Router();

const faqEntries = [
  {
    question: 'How do I connect my BLE fitness gear?',
    answer:
      'Open GearSnitch, go to the Gear tab, and tap "Scan for Devices." Make sure Bluetooth is enabled on your phone. The app will automatically discover nearby BLE-enabled fitness equipment. Tap a device to pair it.',
  },
  {
    question: 'How does gym detection work?',
    answer:
      'GearSnitch uses geo-fencing to detect when you arrive at a partnered gym. When you enter the geo-fenced zone, the app automatically activates session tracking and BLE monitoring. You must grant location permissions for this feature to work.',
  },
  {
    question: 'What happens when my gear disconnects?',
    answer:
      'When a tracked BLE device disconnects unexpectedly, GearSnitch triggers a panic alert with sound and haptic feedback. If you have emergency contacts configured, they will receive a push notification with your last known location.',
  },
  {
    question: 'How do I manage my subscription?',
    answer:
      'GearSnitch subscriptions are currently managed through the App Store. Open Settings > Apple ID > Subscriptions on your iPhone, or use the Manage in App Store button from gearsnitch.com/account.',
  },
  {
    question: 'How do I cancel my subscription?',
    answer:
      'Cancel through your iPhone Settings > Apple ID > Subscriptions. You will retain access until the end of your current billing period.',
  },
  {
    question: 'How does the referral program work?',
    answer:
      'Share your unique referral code or QR code with friends. When they subscribe, you earn 90 days of free premium access per qualifying referral.',
  },
  {
    question: 'Are peptide store products safe for consumption?',
    answer:
      'Products in the peptide store are sold for research purposes only and are not evaluated by the FDA. They are not intended to diagnose, treat, cure, or prevent any disease. You must be 21 or older to purchase. Consult a healthcare professional before use.',
  },
  {
    question: 'How do I delete my account?',
    answer:
      'Visit gearsnitch.com/delete-account or go to Account Settings in the app. A 30-day grace period starts immediately after you request deletion.',
  },
  {
    question: 'Is my health data shared with anyone?',
    answer:
      'No. HealthKit data stays on your device and in Apple Health. It is never sold, shared with advertisers, or sent to third parties. We only read and write workout data with your explicit permission.',
  },
  {
    question: 'What devices are compatible with GearSnitch?',
    answer:
      'GearSnitch requires iOS 16.0 or later. BLE monitoring works with any Bluetooth Low Energy device. HealthKit integration is available on iPhones with Apple Health.',
  },
];

const createTicketSchema = z.object({
  name: z.string().trim().min(1).max(120),
  email: z.string().trim().email().max(320),
  subject: z.string().trim().min(1).max(200),
  message: z.string().trim().min(1).max(5000),
  source: z.enum(['web', 'ios', 'email']).optional(),
});

function getUserId(req: Request): string {
  return (req.user as JwtPayload).sub;
}

function getRouteParam(req: Request, key: string): string {
  const value = req.params[key];
  return Array.isArray(value) ? value[0] : value;
}

function serializeTicket(ticket: {
  _id: { toString(): string };
  name: string;
  email: string;
  subject: string;
  message: string;
  status: string;
  source: string;
  createdAt: Date;
  updatedAt: Date;
}) {
  return {
    _id: ticket._id.toString(),
    name: ticket.name,
    email: ticket.email,
    subject: ticket.subject,
    message: ticket.message,
    status: ticket.status,
    source: ticket.source,
    createdAt: ticket.createdAt,
    updatedAt: ticket.updatedAt,
  };
}

// POST /support/tickets
router.post('/tickets', attachUserIfPresent, async (req, res) => {
  try {
    const parsed = createTicketSchema.safeParse(req.body);
    if (!parsed.success) {
      errorResponse(
        res,
        StatusCodes.BAD_REQUEST,
        'Validation failed',
        parsed.error.flatten().fieldErrors,
      );
      return;
    }

    const userId =
      req.user && Types.ObjectId.isValid(req.user.sub)
        ? new Types.ObjectId(req.user.sub)
        : null;

    const created = await SupportTicket.create({
      ...parsed.data,
      source: parsed.data.source ?? 'web',
      userId,
    });

    successResponse(
      res,
      {
        ticketId: created._id.toString(),
        status: created.status,
        ticket: serializeTicket(created),
      },
      StatusCodes.CREATED,
    );
  } catch (err) {
    errorResponse(
      res,
      StatusCodes.INTERNAL_SERVER_ERROR,
      'Failed to create support ticket',
      err instanceof Error ? err.message : String(err),
    );
  }
});

// GET /support/tickets
router.get('/tickets', isAuthenticated, async (req, res) => {
  try {
    const currentUser = await User.findById(getUserId(req)).lean();
    if (!currentUser) {
      errorResponse(res, StatusCodes.NOT_FOUND, 'User not found');
      return;
    }

    const filter =
      req.user?.role === 'admin'
        ? {}
        : {
            $or: [
              { userId: currentUser._id },
              { email: currentUser.email },
            ],
          };

    const tickets = await SupportTicket.find(filter)
      .sort({ createdAt: -1 })
      .limit(100)
      .lean();

    successResponse(res, tickets.map((ticket) => serializeTicket(ticket)));
  } catch (err) {
    errorResponse(
      res,
      StatusCodes.INTERNAL_SERVER_ERROR,
      'Failed to list support tickets',
      err instanceof Error ? err.message : String(err),
    );
  }
});

// GET /support/tickets/:id
router.get('/tickets/:id', isAuthenticated, async (req, res) => {
  try {
    const ticketId = getRouteParam(req, 'id');
    if (!Types.ObjectId.isValid(ticketId)) {
      errorResponse(res, StatusCodes.BAD_REQUEST, 'Invalid support ticket id');
      return;
    }

    const currentUser = await User.findById(getUserId(req)).lean();
    if (!currentUser) {
      errorResponse(res, StatusCodes.NOT_FOUND, 'User not found');
      return;
    }

    const ticket = await SupportTicket.findById(ticketId).lean();
    if (!ticket) {
      errorResponse(res, StatusCodes.NOT_FOUND, 'Support ticket not found');
      return;
    }

    const canViewTicket =
      req.user?.role === 'admin'
      || String(ticket.userId ?? '') === String(currentUser._id)
      || ticket.email.toLowerCase() === currentUser.email.toLowerCase();

    if (!canViewTicket) {
      errorResponse(res, StatusCodes.FORBIDDEN, 'You do not have access to this support ticket');
      return;
    }

    successResponse(res, serializeTicket(ticket));
  } catch (err) {
    errorResponse(
      res,
      StatusCodes.INTERNAL_SERVER_ERROR,
      'Failed to get support ticket',
      err instanceof Error ? err.message : String(err),
    );
  }
});

// GET /support/faq
router.get('/faq', (_req, res) => {
  successResponse(res, faqEntries);
});

export default router;
