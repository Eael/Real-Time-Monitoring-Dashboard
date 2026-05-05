import mongoose from 'mongoose';
import process = require('process');

export const connectDB = async () => {
  await mongoose.connect(process.env.MONGO_URI!);
  console.log('MongoDB connected');
};