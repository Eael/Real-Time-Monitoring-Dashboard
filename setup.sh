#!/bin/bash

set -e

echo "==> Installing MongoDB..."
echo "Purge conflicting packages..."
sudo apt-get purge -y mongodb mongodb-server mongodb-clients mongodb-org*
sudo apt-get autoremove -y

# Import GPG
curl -fsSL https://www.mongodb.org/static/pgp/server-7.0.asc | sudo gpg -o /usr/share/keyrings/mongodb-server-7.0.gpg --dearmor --yes

# Add Repo
echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-7.0.gpg ] https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/7.0 multiverse" | sudo tee /etc/apt/sources.list.d/mongodb-org-7.0.list

# Update and install
sudo apt-get update
sudo apt-get install -y mongodb-org

sudo systemctl daemon-reload
sudo systemctl enable mongod
sudo systemctl start mongod
echo "MongoDB running."

echo "==> Installing Redis..."
sudo apt install -y redis-server
sudo systemctl start redis
sudo systemctl enable redis
echo "Redis running."

echo "==> Setting up project..."
mkdir -p realtime-dashboard && cd realtime-dashboard

npm init -y

npm install express socket.io mongoose redis jsonwebtoken bcrypt dotenv cors
npm install -D typescript ts-node nodemon \
  @types/node @types/express @types/socket.io \
  @types/mongoose @types/jsonwebtoken @types/bcrypt @types/cors

npx tsc --init --target ES2020 --module commonjs \
  --rootDir ./src --outDir ./dist \
  --strict --esModuleInterop

# Update package.json scripts
node -e "
const fs = require('fs');
const pkg = JSON.parse(fs.readFileSync('package.json'));
pkg.scripts = {
  dev: 'nodemon --exec ts-node src/index.ts',
  build: 'tsc',
  start: 'node dist/index.js'
};
fs.writeFileSync('package.json', JSON.stringify(pkg, null, 2));
"

echo "==> Creating .env..."
cat > .env <<EOF
PORT=4000
MONGO_URI=mongodb://localhost:27017/dashboard
REDIS_URL=redis://localhost:6379
JWT_SECRET=change_this_secret
EOF

echo "==> Creating folder structure..."
mkdir -p src/config src/models src/middleware src/routes src/socket src/services public

echo "==> Writing source files..."

cat > src/config/db.ts <<'EOF'
import mongoose from 'mongoose';

export const connectDB = async () => {
  await mongoose.connect(process.env.MONGO_URI!);
  console.log('MongoDB connected');
};
EOF

cat > src/config/redis.ts <<'EOF'
import { createClient } from 'redis';

export const redisClient = createClient({ url: process.env.REDIS_URL });
export const redisSub = createClient({ url: process.env.REDIS_URL });

export const connectRedis = async () => {
  await redisClient.connect();
  await redisSub.connect();
  console.log('Redis connected');
};
EOF

cat > src/models/User.ts <<'EOF'
import { Schema, model } from 'mongoose';

const UserSchema = new Schema({
  username: { type: String, required: true, unique: true },
  password: { type: String, required: true },
}, { timestamps: true });

export const User = model('User', UserSchema);
EOF

cat > src/models/Event.ts <<'EOF'
import { Schema, model } from 'mongoose';

const EventSchema = new Schema({
  type: String,
  payload: Schema.Types.Mixed,
  timestamp: { type: Date, default: Date.now },
});

export const Event = model('Event', EventSchema);
EOF

cat > src/middleware/auth.ts <<'EOF'
import { Request, Response, NextFunction } from 'express';
import jwt from 'jsonwebtoken';

export const authenticate = (req: Request, res: Response, next: NextFunction) => {
  const token = req.headers.authorization?.split(' ')[1];
  if (!token) return res.status(401).json({ error: 'No token' });
  try {
    (req as any).user = jwt.verify(token, process.env.JWT_SECRET!);
    next();
  } catch {
    res.status(403).json({ error: 'Invalid token' });
  }
};
EOF

cat > src/routes/auth.ts <<'EOF'
import { Router, Request, Response } from 'express';
import bcrypt from 'bcrypt';
import jwt from 'jsonwebtoken';
import { User } from '../models/User';

const router = Router();

router.post('/register', async (req: Request, res: Response) => {
  const { username, password } = req.body;
  const hashed = await bcrypt.hash(password, 10);
  const user = await User.create({ username, password: hashed });
  res.json({ id: user._id, username: user.username });
});

router.post('/login', async (req: Request, res: Response) => {
  const { username, password } = req.body;
  const user = await User.findOne({ username });
  if (!user || !(await bcrypt.compare(password, user.password)))
    return res.status(401).json({ error: 'Invalid credentials' });
  const token = jwt.sign({ id: user._id, username }, process.env.JWT_SECRET!, { expiresIn: '1d' });
  res.json({ token });
});

export default router;
EOF

cat > src/services/simulator.ts <<'EOF'
import { redisClient } from '../config/redis';
import { Event } from '../models/Event';

const CHANNEL = 'dashboard:events';

const randomEvent = () => {
  const types = ['cpu', 'memory', 'transaction', 'login'];
  const type = types[Math.floor(Math.random() * types.length)];
  return {
    type,
    payload: {
      value: +(Math.random() * 100).toFixed(2),
      label: `${type.toUpperCase()} usage`,
    },
  };
};

export const startSimulator = (intervalMs = 2000) => {
  setInterval(async () => {
    const event = randomEvent();
    const saved = await Event.create(event);
    await redisClient.publish(CHANNEL, JSON.stringify(saved));
  }, intervalMs);
  console.log('Simulator started');
};
EOF

cat > src/socket/index.ts <<'EOF'
import { Server } from 'socket.io';
import { Server as HttpServer } from 'http';
import jwt from 'jsonwebtoken';
import { redisSub } from '../config/redis';
import { Event } from '../models/Event';

const CHANNEL = 'dashboard:events';

export const initSocket = (httpServer: HttpServer) => {
  const io = new Server(httpServer, {
    cors: { origin: '*' },
  });

  io.use((socket, next) => {
    const token = socket.handshake.auth?.token;
    if (!token) return next(new Error('Authentication error'));
    try {
      (socket as any).user = jwt.verify(token, process.env.JWT_SECRET!);
      next();
    } catch {
      next(new Error('Invalid token'));
    }
  });

  io.on('connection', async (socket) => {
    console.log(`Client connected: ${socket.id}`);
    const history = await Event.find().sort({ timestamp: -1 }).limit(20);
    socket.emit('history', history.reverse());
    socket.on('disconnect', () => console.log(`Client disconnected: ${socket.id}`));
  });

  redisSub.subscribe(CHANNEL, (message) => {
    io.emit('event', JSON.parse(message));
  });

  return io;
};
EOF

cat > src/index.ts <<'EOF'
import 'dotenv/config';
import express from 'express';
import http from 'http';
import cors from 'cors';
import path from 'path';
import { connectDB } from './config/db';
import { connectRedis } from './config/redis';
import authRoutes from './routes/auth';
import { initSocket } from './socket';
import { startSimulator } from './services/simulator';

const app = express();
app.use(cors());
app.use(express.json());
app.use(express.static(path.join(__dirname, '../public')));

app.use('/api/auth', authRoutes);

const httpServer = http.createServer(app);
initSocket(httpServer);

const PORT = process.env.PORT || 4000;

(async () => {
  await connectDB();
  await connectRedis();
  startSimulator(2000);
  httpServer.listen(PORT, () => console.log(`Server running on port ${PORT}`));
})();
EOF

cat > public/index.html <<'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <title>Dashboard</title>
  <script src="https://cdn.socket.io/4.7.5/socket.io.min.js"></script>
</head>
<body>
  <h2>Real-Time Events</h2>
  <div>
    <input id="tokenInput" placeholder="Paste JWT token here" style="width:400px"/>
    <button onclick="connect()">Connect</button>
  </div>
  <ul id="feed"></ul>
  <script>
    function connect() {
      const token = document.getElementById('tokenInput').value;
      const socket = io('http://localhost:4000', { auth: { token } });
      socket.on('history', (events) => events.forEach(addEvent));
      socket.on('event', addEvent);
      socket.on('connect_error', (err) => alert('Auth error: ' + err.message));
    }
    function addEvent(e) {
      const li = document.createElement('li');
      li.textContent = `[${e.type}] ${JSON.stringify(e.payload)} @ ${new Date(e.timestamp).toLocaleTimeString()}`;
      document.getElementById('feed').prepend(li);
    }
  </script>
</body>
</html>
EOF

echo ""
echo "==> Setup complete. To start the app:"
echo "    cd realtime-dashboard && npm run dev"