# Real-Time Monitoring Dashboard

A real-time data monitoring system that streams live events to connected clients via WebSockets. Built with Node.js, Socket.IO, Redis, and MongoDB.

---

## Tech Stack

| Layer | Technology |
|---|---|
| Backend | Node.js + Express + TypeScript |
| Real-time | Socket.IO (WebSockets) |
| Message Broker | Redis (Pub/Sub) |
| Database | MongoDB (event persistence) |
| Auth | JWT (socket auth) + bcrypt (passwords) |

---

## Architecture

```
Frontend (Socket.IO client)
        │  WebSocket (JWT auth)
        ▼
  Express + Socket.IO Server
        │             ▲
   Publishes      Subscribes
        ▼             │
      Redis Pub/Sub Channel
        │
  Data Simulator ──► MongoDB (event history)
```

---

## Project Structure

```
realtime-dashboard/
├── src/
│   ├── config/
│   │   ├── db.ts           # MongoDB connection
│   │   └── redis.ts        # Redis client + subscriber
│   ├── models/
│   │   ├── User.ts         # User schema
│   │   └── Event.ts        # Event schema
│   ├── middleware/
│   │   └── auth.ts         # JWT REST middleware
│   ├── routes/
│   │   └── auth.ts         # Register & login endpoints
│   ├── socket/
│   │   └── index.ts        # Socket.IO setup + Redis sub
│   ├── services/
│   │   └── simulator.ts    # Data stream simulator
│   └── index.ts            # Entry point
├── public/
│   └── index.html          # Browser client
├── .env
├── package.json
└── tsconfig.json
```

---

## Prerequisites

- Node.js v18+
- MongoDB
- Redis

---

## Quick Start

### 1. Automated Setup (recommended)

```bash
chmod +x setup.sh && sudo ./setup.sh
```

This installs MongoDB and Redis, scaffolds the project, and writes all source files.

### 2. Manual Setup

```bash
# Install dependencies
npm install

# Start MongoDB and Redis
sudo systemctl start mongod
sudo systemctl start redis

# Start the server
npm run dev
```

---

## Environment Variables

Create a `.env` file in the project root:

```env
PORT=4000
MONGO_URI=mongodb://localhost:27017/dashboard
REDIS_URL=redis://localhost:6379
JWT_SECRET=your_jwt_secret_here
```

---

## API Reference

### Auth

| Method | Endpoint | Body | Description |
|---|---|---|---|
| POST | `/api/auth/register` | `{ username, password }` | Create a new user |
| POST | `/api/auth/login` | `{ username, password }` | Returns a JWT token |

### Register

```bash
curl -X POST http://localhost:4000/api/auth/register \
  -H "Content-Type: application/json" \
  -d '{"username": "alice", "password": "secret123"}'
```

### Login

```bash
curl -X POST http://localhost:4000/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username": "alice", "password": "secret123"}'
```

Response:
```json
{ "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6..." }
```

---

## WebSocket Events

| Event | Direction | Description |
|---|---|---|
| `history` | Server → Client | Last 20 events on connect |
| `event` | Server → Client | Live event every 2 seconds |

### Connecting

```js
const socket = io('http://localhost:4000', {
  auth: { token: 'your_jwt_token' }
});

socket.on('history', (events) => console.log(events));
socket.on('event', (event) => console.log(event));
```

### Event Payload

```json
{
  "type": "cpu",
  "payload": {
    "value": 72.45,
    "label": "CPU usage"
  },
  "timestamp": "2024-01-15T10:30:00.000Z"
}
```

Event types: `cpu`, `memory`, `transaction`, `login`

---

## Browser Client

Open `http://localhost:4000`, paste your JWT token, and click **Connect** to start receiving live events.

---

## Scripts

```bash
npm run dev      # Start development server with hot reload
npm run build    # Compile TypeScript to dist/
npm start        # Run compiled output
```

---

## Security

- All WebSocket connections require a valid JWT token
- Unauthenticated clients are rejected before any data is streamed
- Passwords are hashed with bcrypt (salt rounds: 10)
- JWT tokens expire after 24 hours
