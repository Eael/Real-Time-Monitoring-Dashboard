import { Schema, model } from 'mongoose';

const EventSchema = new Schema({
  type: String,       // e.g. 'cpu', 'transaction', 'login'
  payload: Schema.Types.Mixed,
  timestamp: { type: Date, default: Date.now },
});

export const Event = model('Event', EventSchema);