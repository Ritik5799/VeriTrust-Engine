# 🛡️ SENTINEL — Fraud Detection System

> "We are not detecting fake users… we are detecting fraud systems."

A real-time fraud detection system with movement intelligence, device fingerprinting, and fraud ring detection.

---

## 📁 Project Structure

```
sentinel_fraud_detection/
├── frontend/
│   └── index.html          ← Standalone web dashboard (no install needed!)
├── backend/
│   ├── server.js           ← Node.js + Express API
│   └── package.json
└── flutter_app/
    ├── lib/main.dart       ← Flutter mobile/desktop app
    └── pubspec.yaml
```

---

## 🚀 Quick Start

### Option 1 — Frontend Only (Fastest)
Just open `frontend/index.html` in any browser. Fully self-contained.  
No server needed — the risk engine runs entirely in JavaScript.

---

### Option 2 — Full Stack (Node.js + Flutter)

#### Backend Setup
```bash
cd backend
npm install
node server.js
# API running at http://localhost:3000
```

#### Flutter App Setup
```bash
cd flutter_app
flutter pub get
flutter run
```
> For device testing: change `_baseUrl` in `main.dart` to your machine's IP (e.g. `http://192.168.1.100:3000`)

---

## 🧠 Risk Scoring Engine

| Rule | Trigger | Risk Points |
|------|---------|-------------|
| Speed Check | speed > 80 km/h | +30 |
| Teleportation | Impossible travel distance/time | +30 |
| Device Mismatch | Same device used by multiple users | +40 |

## 🚦 Decision Engine

| Score | Decision |
|-------|----------|
| 0–29  | ✅ ALLOW    |
| 30–69 | ⚠️ RESTRICT |
| 70+   | 🔴 BLOCK    |

---

## 📡 API Reference

### POST /analyze
```json
Request:
{
  "userId": "U123",
  "lat": 28.6,
  "lng": 77.2,
  "speed": 120,
  "deviceId": "ABC123"
}

Response:
{
  "userId": "U123",
  "riskScore": 72,
  "decision": "BLOCK",
  "flags": {
    "speedViolation": true,
    "teleportation": false,
    "deviceMismatch": true
  },
  "reasons": ["Speed 120 km/h exceeds threshold", "Device shared by 2 users"],
  "cluster": {
    "clusterId": "C42",
    "deviceId": "ABC123",
    "users": ["U123", "U456"]
  }
}
```

### GET /stats
Returns total requests, fraud rate, and recent activity log.

### GET /clusters
Returns all detected fraud rings.

### POST /reset
Clears all state (useful for demos).

---

## 🎯 Demo Scenario Flow

Run these in order for maximum impact:

1. **Normal User** → Score: 0 → ✅ ALLOW
2. **High Speed** → Score: 30 → ⚠️ RESTRICT  
3. **Teleportation** → Score: 60+ → 🔴 BLOCK
4. **Device Fraud Ring** → Score: 40–100 → 🔴 BLOCK + **Purple Cluster Panel appears** 💥

---

## 🛠️ Tech Stack

- **Frontend**: Pure HTML/CSS/JS + Chart.js
- **Backend**: Node.js + Express
- **Mobile**: Flutter (Dart)
- **Database**: In-memory (swap `lastLocations`/`deviceUsers` objects for MongoDB collections)

---

## 🔄 Adding MongoDB

Replace the in-memory objects in `server.js` with:

```javascript
const { MongoClient } = require('mongodb');
const client = new MongoClient('mongodb://localhost:27017');
const db = client.db('sentinel');
const locations = db.collection('locations');
const devices   = db.collection('devices');
const logs      = db.collection('logs');
```

---

Built with ❤️ for the SENTINEL fraud detection demo.
