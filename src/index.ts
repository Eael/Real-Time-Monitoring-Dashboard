import 'dotenv/config';
import express from 'express';
import http from 'http';
import cors from 'cors';
import { connectDB } from './config/db';
import { connectRedis } from './config/redis';
import authRoutes from './routes/auth';
import { initSocket } from './socket';
import { startSimulator } from './services/simulator';
import path from 'path';

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
