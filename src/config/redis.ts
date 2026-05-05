import { createClient } from 'redis';

export const redisClient = createClient({ url: process.env.REDIS_URL || 'redis://localhost' });
export const redisSub = createClient({ url: process.env.REDIS_URL || 'redis://localhost' });

export const connectRedis = async () => {
  await redisClient.connect();
  await redisSub.connect();
  console.log('Redis connected');
};