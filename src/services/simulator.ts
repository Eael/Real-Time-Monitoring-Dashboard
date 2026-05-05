import { redisClient } from '../config/redis';
import { Event } from '../models/Event';

const CHANNEL = 'dashboard:events';

const randomEvent = () => {
  const types = ['cpu', 'memory', 'transaction', 'login'];
  const type = types[Math.floor(Math.random() * types.length)]!;
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
    const saved = await Event.create(event);  // get the saved doc with timestamp
    await redisClient.publish(CHANNEL, JSON.stringify(saved)); // publish with timestamp
  }, intervalMs);
  console.log('Simulator started');
};