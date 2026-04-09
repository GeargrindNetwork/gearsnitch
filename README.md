# GearSnitch

Bluetooth gear awareness, gym-location-aware activation, referral-driven growth, subscription validation, health tracking, and peptide store.

## Architecture

```
gearsnitch/
├── api/          # Express TypeScript API server
├── web/          # Vite + React + shadcn/ui web app
├── shared/       # Shared types, schemas, constants
├── worker/       # BullMQ background job processors
├── realtime/     # Socket.IO WebSocket service
├── client-ios/   # Native iOS app (SwiftUI)
├── infrastructure/
│   ├── terraform/    # GCP infrastructure as code
│   ├── docker/       # Dockerfiles for all services
│   └── cloudbuild/   # Cloud Build CI/CD configs
└── docs/         # Architecture docs, ADRs, plans
```

## Tech Stack

| Layer | Technology |
|-------|-----------|
| **Backend** | Node.js 20+, Express, TypeScript 5, Mongoose |
| **Frontend** | Vite, React 18, shadcn/ui, Tailwind CSS, React Router |
| **Database** | MongoDB Atlas, Redis |
| **Queue** | BullMQ (Redis-backed) |
| **Realtime** | Socket.IO with Redis adapter |
| **Auth** | Apple Sign-In, Google OAuth, JWT (RS256) |
| **Cloud** | Google Cloud Run, Secret Manager, Cloud Build, Cloud Armor |
| **iOS** | SwiftUI, Swift 5.9+, MVVM, CoreBluetooth, CoreLocation, HealthKit |

## Quick Start

```bash
# Install dependencies
npm install

# Start all services in dev mode
npm run dev

# Or start individually
npm run dev:api      # API on :3001
npm run dev:web      # Web on :5173
npm run dev:worker   # Background workers
npm run dev:realtime # WebSocket server on :3002
```

## Environment

Copy `.env.example` files and fill in your values:

```bash
cp api/.env.example api/.env
```

## MongoDB Atlas

- **Project**: GearSnitch (69d839cf8e17dcef631a0102)
- **Cluster**: gearsnitch-dev (M0 free tier, AWS us-east-1)
- **Connection**: `mongodb+srv://gearsnitch-dev.sqrsvda.mongodb.net/gearsnitch`

## GCP Project

- **Project ID**: gearsnitch
- **Domain**: gearsnitch.com

## License

Proprietary — Geargrind
