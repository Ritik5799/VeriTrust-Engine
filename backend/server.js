/**
 * SENTINEL — Fraud Detection Backend
 * Node.js + Express API
 * 
 * Run:
 *   npm install
 *   node server.js
 *
 * API: POST /analyze
 */

const express = require('express');
const cors = require('cors');
const app = express();

app.use(cors());
app.use(express.json());

// ─── IN-MEMORY STORE (replace with MongoDB in production) ────────────────────
const lastLocations = {};   // userId → { lat, lng, timestamp }
const deviceUsers = {};     // deviceId → Set of userIds
const activityLog = [];     // all requests
const stats = { total: 0, allow: 0, restrict: 0, block: 0 };

// ─── HAVERSINE DISTANCE (km) ─────────────────────────────────────────────────
function haversine(lat1, lng1, lat2, lng2) {
  const R = 6371;
  const dLat = (lat2 - lat1) * Math.PI / 180;
  const dLng = (lng2 - lng1) * Math.PI / 180;
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(lat1 * Math.PI / 180) *
    Math.cos(lat2 * Math.PI / 180) *
    Math.sin(dLng / 2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

// ─── RISK SCORING ENGINE ─────────────────────────────────────────────────────
function calculateRisk(userId, deviceId, lat, lng, speed) {
  let risk = 0;
  const flags = { speedViolation: false, teleportation: false, deviceMismatch: false };
  const reasons = [];
  const now = Date.now();

  // Rule 1: Speed Check
  if (speed > 80) {
    risk += 30;
    flags.speedViolation = true;
    reasons.push(`Speed ${speed} km/h exceeds safe threshold (80 km/h)`);
  }

  // Rule 2: Teleportation Detection
  if (lastLocations[userId]) {
    const prev = lastLocations[userId];
    const distKm = haversine(prev.lat, prev.lng, lat, lng);
    const hours = (now - prev.timestamp) / 3600000;
    const impliedSpeed = distKm / Math.max(hours, 0.0001);

    if (impliedSpeed > 900) { // faster than commercial jet
      risk += 30;
      flags.teleportation = true;
      reasons.push(
        `Teleportation detected: ${Math.round(distKm)} km in ${Math.round(hours * 60)} min ` +
        `(implied speed: ${Math.round(impliedSpeed)} km/h)`
      );
    }
  }

  // Update last known location
  lastLocations[userId] = { lat, lng, timestamp: now };

  // Rule 3: Device Multi-User Check
  if (!deviceUsers[deviceId]) deviceUsers[deviceId] = new Set();
  deviceUsers[deviceId].add(userId);

  if (deviceUsers[deviceId].size > 1) {
    risk += 40;
    flags.deviceMismatch = true;
    const users = [...deviceUsers[deviceId]];
    reasons.push(`Device "${deviceId}" used by ${users.length} accounts: ${users.join(', ')}`);
  }

  return { risk: Math.min(risk, 100), flags, reasons };
}

// ─── DECISION ENGINE ─────────────────────────────────────────────────────────
function makeDecision(risk) {
  if (risk < 30) return { decision: 'ALLOW',    code: 200, color: 'green'  };
  if (risk < 70) return { decision: 'RESTRICT', code: 202, color: 'amber'  };
  return           { decision: 'BLOCK',    code: 403, color: 'red'    };
}

// ─── CLUSTER DETECTION ───────────────────────────────────────────────────────
function detectCluster(deviceId) {
  const users = deviceUsers[deviceId];
  if (!users || users.size < 2) return null;
  return {
    clusterId: 'C' + (Math.abs(
      deviceId.split('').reduce((a, c) => a + c.charCodeAt(0), 0)
    ) % 99 + 1),
    deviceId,
    users: [...users],
    riskLevel: users.size >= 3 ? 'HIGH' : 'MEDIUM'
  };
}

// ─── POST /analyze ────────────────────────────────────────────────────────────
app.post('/analyze', (req, res) => {
  const { userId, lat, lng, speed, deviceId } = req.body;

  // Validation
  if (!userId || lat === undefined || lng === undefined || speed === undefined || !deviceId) {
    return res.status(400).json({
      error: 'Missing required fields: userId, lat, lng, speed, deviceId'
    });
  }

  const { risk, flags, reasons } = calculateRisk(userId, deviceId, lat, lng, speed);
  const { decision, code, color } = makeDecision(risk);
  const cluster = detectCluster(deviceId);

  // Update stats
  stats.total++;
  stats[decision.toLowerCase()] = (stats[decision.toLowerCase()] || 0) + 1;

  const result = {
    userId,
    deviceId,
    location: { lat, lng },
    speed,
    riskScore: risk,
    decision,
    color,
    flags,
    reasons,
    cluster,
    timestamp: new Date().toISOString()
  };

  activityLog.unshift(result);
  if (activityLog.length > 100) activityLog.pop();

  console.log(`[${new Date().toISOString()}] ${userId} → ${decision} (score: ${risk})`);
  res.status(code).json(result);
});

// ─── GET /stats ───────────────────────────────────────────────────────────────
app.get('/stats', (req, res) => {
  res.json({
    ...stats,
    fraudRate: stats.total > 0
      ? Math.round((stats.block / stats.total) * 100) + '%'
      : '0%',
    recentLog: activityLog.slice(0, 10)
  });
});

// ─── GET /clusters ────────────────────────────────────────────────────────────
app.get('/clusters', (req, res) => {
  const clusters = Object.entries(deviceUsers)
    .filter(([, users]) => users.size > 1)
    .map(([deviceId]) => detectCluster(deviceId));
  res.json({ count: clusters.length, clusters });
});

// ─── GET /reset ───────────────────────────────────────────────────────────────
app.post('/reset', (req, res) => {
  Object.keys(lastLocations).forEach(k => delete lastLocations[k]);
  Object.keys(deviceUsers).forEach(k => delete deviceUsers[k]);
  activityLog.length = 0;
  stats.total = stats.allow = stats.restrict = stats.block = 0;
  res.json({ message: 'State reset successfully' });
});

// ─── HEALTH CHECK ─────────────────────────────────────────────────────────────
app.get('/health', (req, res) => {
  res.json({ status: 'ok', uptime: process.uptime(), timestamp: new Date().toISOString() });
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(`\n🛡️  SENTINEL Fraud Detection API`);
  console.log(`   Running on http://localhost:${PORT}`);
  console.log(`   POST /analyze   — analyze a transaction`);
  console.log(`   GET  /stats     — get fraud statistics`);
  console.log(`   GET  /clusters  — view fraud rings`);
  console.log(`   POST /reset     — reset all state\n`);
});

module.exports = app;
