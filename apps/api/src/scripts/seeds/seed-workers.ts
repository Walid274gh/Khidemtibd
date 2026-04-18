// ══════════════════════════════════════════════════════════════════════════════
// KHIDMETI — Script de seed : travailleurs de test à Oran (Wahran)
//
// USAGE via Makefile (recommandé — aucune installation requise) :
//   make scripts-seed-workers              ← seed initial
//   make scripts-seed-workers ARGS=--clear ← efface + re-seed
//
// USAGE direct (si ts-node installé sur l'hôte) :
//   npx ts-node --project tsconfig.json src/scripts/seeds/seed-workers.ts
//   npx ts-node --project tsconfig.json src/scripts/seeds/seed-workers.ts --clear
//
// IMPORTANT :
//   Ces workers ont des UIDs fictifs (seed-worker-XXX).
//   Ils sont visibles dans MongoDB et dans l'API REST,
//   mais ne peuvent PAS se connecter via Firebase Auth.
//   → Parfait pour tester : browsing worker, cartes, recherche IA.
// ══════════════════════════════════════════════════════════════════════════════

import mongoose from 'mongoose';

// ── Config ────────────────────────────────────────────────────────────────────
const MONGODB_URI =
  process.env['MONGODB_URI'] ??
  'mongodb://khidmeti:khidmeti123@localhost:27017/khidmeti?authSource=admin';

// Oran (Wahran) — wilayaCode = 31
const WILAYA_CODE = 31;

// ── Coordonnées de quartiers d'Oran pour avoir des workers répartis ───────────
const ORAN_LOCATIONS = [
  { name: 'Es Senia',      lat: 35.6481,  lng: -0.6030 },
  { name: 'Bir El Djir',   lat: 35.7128,  lng: -0.5538 },
  { name: 'Oran Centre',   lat: 35.6969,  lng: -0.6331 },
  { name: 'Hay Yasmine',   lat: 35.6750,  lng: -0.6200 },
  { name: 'Plateaux',      lat: 35.7050,  lng: -0.6500 },
  { name: 'Gambetta',      lat: 35.7110,  lng: -0.6420 },
  { name: 'Belgaid',       lat: 35.6600,  lng: -0.6700 },
  { name: 'Sidi El Bachir', lat: 35.6850, lng: -0.6100 },
];

// ── Données des travailleurs de test ──────────────────────────────────────────
const TEST_WORKERS = [
  {
    uid:        'seed-worker-001',
    name:       'Karim Benali',
    phone:      '+213550111001',
    profession: 'plumber',
    rating:     4.7,
    jobs:       34,
    location:   ORAN_LOCATIONS[0],
  },
  {
    uid:        'seed-worker-002',
    name:       'Farid Boumediene',
    phone:      '+213550111002',
    profession: 'electrician',
    rating:     4.5,
    jobs:       28,
    location:   ORAN_LOCATIONS[1],
  },
  {
    uid:        'seed-worker-003',
    name:       'Mohamed Tlemcani',
    phone:      '+213550111003',
    profession: 'plumber',
    rating:     4.2,
    jobs:       19,
    location:   ORAN_LOCATIONS[2],
  },
  {
    uid:        'seed-worker-004',
    name:       'Youcef Hadjadj',
    phone:      '+213550111004',
    profession: 'ac_repair',
    rating:     4.8,
    jobs:       52,
    location:   ORAN_LOCATIONS[3],
  },
  {
    uid:        'seed-worker-005',
    name:       'Amine Zerrouk',
    phone:      '+213550111005',
    profession: 'mason',
    rating:     4.0,
    jobs:       11,
    location:   ORAN_LOCATIONS[4],
  },
  {
    uid:        'seed-worker-006',
    name:       'Rachid Kaci',
    phone:      '+213550111006',
    profession: 'painter',
    rating:     4.3,
    jobs:       22,
    location:   ORAN_LOCATIONS[5],
  },
  {
    uid:        'seed-worker-007',
    name:       'Bilal Messaoudi',
    phone:      '+213550111007',
    profession: 'electrician',
    rating:     4.6,
    jobs:       41,
    location:   ORAN_LOCATIONS[6],
  },
  {
    uid:        'seed-worker-008',
    name:       'Nabil Brahimi',
    phone:      '+213550111008',
    profession: 'cleaner',
    rating:     4.1,
    jobs:       16,
    location:   ORAN_LOCATIONS[7],
  },
  {
    uid:        'seed-worker-009',
    name:       'Samir Bouali',
    phone:      '+213550111009',
    profession: 'carpenter',
    rating:     4.4,
    jobs:       30,
    location:   ORAN_LOCATIONS[0],
  },
  {
    uid:        'seed-worker-010',
    name:       'Hichem Djebari',
    phone:      '+213550111010',
    profession: 'appliance_repair',
    rating:     4.9,
    jobs:       67,
    location:   ORAN_LOCATIONS[1],
  },
  // Quelques workers HORS LIGNE pour tester les filtres
  {
    uid:        'seed-worker-011',
    name:       'Omar Laid',
    phone:      '+213550111011',
    profession: 'plumber',
    rating:     3.8,
    jobs:       8,
    location:   ORAN_LOCATIONS[2],
    isOnline:   false,
  },
  {
    uid:        'seed-worker-012',
    name:       'Khaled Mansouri',
    phone:      '+213550111012',
    profession: 'mechanic',
    rating:     4.2,
    jobs:       25,
    location:   ORAN_LOCATIONS[3],
    isOnline:   false,
  },
];

// ── Mongoose Schema (minimal — identique à user.schema.ts) ────────────────────
const UserSchema = new mongoose.Schema(
  {
    _id:            { type: String, required: true },
    name:           { type: String, required: true },
    email:          { type: String, default: '' },
    phoneNumber:    { type: String, default: '' },
    role:           { type: String, default: 'worker' },
    latitude:       { type: Number, default: null },
    longitude:      { type: Number, default: null },
    wilayaCode:     { type: Number, default: null },
    cellId:         { type: String, default: null },
    geoHash:        { type: String, default: null },
    lastUpdated:    { type: Date,   required: true },
    lastCellUpdate: { type: Date,   default: null },
    profileImageUrl:{ type: String, default: null },
    fcmToken:       { type: String, default: null },
    profession:     { type: String, default: null },
    isOnline:       { type: Boolean, default: false },
    averageRating:  { type: Number, default: 0 },
    ratingCount:    { type: Number, default: 0 },
    ratingSum:      { type: Number, default: 0 },
    jobsCompleted:  { type: Number, default: 0 },
    responseRate:   { type: Number, default: 0.7 },
    lastActiveAt:   { type: Date,   default: null },
  },
  { collection: 'users', versionKey: false },
);

// ── Helpers ───────────────────────────────────────────────────────────────────

/** Encode un geohash à précision 6 (identique à LocationService) */
function encodeGeoHash(lat: number, lng: number, precision = 6): string {
  const BASE32 = '0123456789bcdefghjkmnpqrstuvwxyz';
  let hash = '', isEven = true, bit = 0, ch = 0;
  let latMin = -90, latMax = 90, lngMin = -180, lngMax = 180;
  while (hash.length < precision) {
    let mid: number;
    if (isEven) {
      mid = (lngMin + lngMax) / 2;
      if (lng >= mid) { ch |= (1 << (4 - bit)); lngMin = mid; } else { lngMax = mid; }
    } else {
      mid = (latMin + latMax) / 2;
      if (lat >= mid) { ch |= (1 << (4 - bit)); latMin = mid; } else { latMax = mid; }
    }
    isEven = !isEven;
    if (bit < 4) { bit++; } else { hash += BASE32[ch]; bit = 0; ch = 0; }
  }
  return hash;
}

/** Construit le cellId (identique à LocationService) */
function buildCellId(lat: number, lng: number, wilayaCode: number): string {
  const p = 2;
  return `${wilayaCode}_${lat.toFixed(p)}_${lng.toFixed(p)}`;
}

// ── Main ──────────────────────────────────────────────────────────────────────

async function main() {
  const shouldClear = process.argv.includes('--clear');

  console.log('\n══════════════════════════════════════════════');
  console.log('  Khidmeti — Seed : workers de test (Oran)');
  console.log('══════════════════════════════════════════════\n');

  await mongoose.connect(MONGODB_URI);
  console.log('✅ Connecté à MongoDB');

  const UserModel = mongoose.model('User', UserSchema);

  if (shouldClear) {
    const del = await UserModel.deleteMany({ _id: /^seed-worker-/ });
    console.log(`🗑️  ${del.deletedCount} worker(s) seed supprimés\n`);
  }

  let created = 0;
  let skipped = 0;

  for (const w of TEST_WORKERS) {
    const { lat, lng } = w.location;
    const cellId  = buildCellId(lat, lng, WILAYA_CODE);
    const geoHash = encodeGeoHash(lat, lng, 6);

    // Bayesian average identique à UsersService.applyRating()
    const ratingSum = w.rating * w.jobs;
    const C = 3.5, m = 10;
    const bayesianAvg = (m * C + ratingSum) / (m + w.jobs);

    const doc = {
      _id:            w.uid,
      name:           w.name,
      email:          '',
      phoneNumber:    w.phone,
      role:           'worker',
      latitude:       lat,
      longitude:      lng,
      wilayaCode:     WILAYA_CODE,
      cellId,
      geoHash,
      lastUpdated:    new Date(),
      lastCellUpdate: new Date(),
      profileImageUrl: null,
      fcmToken:       null,
      profession:     w.profession,
      isOnline:       w.isOnline ?? true,
      averageRating:  bayesianAvg,
      ratingCount:    w.jobs,
      ratingSum,
      jobsCompleted:  w.jobs,
      responseRate:   0.85,
      lastActiveAt:   null,
    };

    try {
      await UserModel.create(doc);
      created++;
      console.log(
        `  ✅ ${w.name.padEnd(22)} | ${w.profession.padEnd(16)} ` +
        `| ${w.location.name.padEnd(15)} ` +
        `| ${w.isOnline ?? true ? '🟢 en ligne' : '⚫ hors ligne'}`,
      );
    } catch (err: any) {
      if (err.code === 11000) {
        skipped++;
        console.log(`  ⏭️  ${w.name} déjà existant — ignoré (utilise ARGS=--clear pour re-seed)`);
      } else {
        throw err;
      }
    }
  }

  console.log('\n══════════════════════════════════════════════');
  console.log(`  ✅ ${created} créé(s)  |  ⏭️  ${skipped} ignoré(s)`);
  console.log('══════════════════════════════════════════════');
  console.log('\n  Test rapide :');
  console.log(`  curl http://localhost:3000/workers?wilayaCode=31&isOnline=true`);
  console.log(`  curl http://localhost:3000/workers?wilayaCode=31&profession=plumber\n`);

  await mongoose.disconnect();
}

main().catch((err) => {
  console.error('\n❌ Erreur :', err.message);
  process.exit(1);
});
