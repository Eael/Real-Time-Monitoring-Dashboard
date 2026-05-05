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

  // JWT authentication middleware for Socket.IO
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

    // Send last 20 events on connect
    const history = await Event.find().sort({ timestamp: -1 }).limit(20);
    socket.emit('history', history.reverse());

    socket.on('disconnect', () => console.log(`Client disconnected: ${socket.id}`));
  });

  // Subscribe to Redis channel and broadcast to all socket clients
  redisSub.subscribe(CHANNEL, (message) => {
    io.emit('event', JSON.parse(message));
  });

  return io;
};