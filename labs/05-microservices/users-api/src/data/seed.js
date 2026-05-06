require('dotenv').config();
const pool = require('../db/client');

const users = [
  { name: 'Alice Martin',   email: 'alice@example.com',   role: 'admin',    active: true },
  { name: 'Bob Chen',       email: 'bob@example.com',     role: 'customer', active: true },
  { name: 'Carol Johnson',  email: 'carol@example.com',   role: 'customer', active: true },
  { name: 'David Kim',      email: 'david@example.com',   role: 'customer', active: false },
  { name: 'Eva Rossi',      email: 'eva@example.com',     role: 'manager',  active: true },
  { name: 'Frank Müller',   email: 'frank@example.com',   role: 'customer', active: true },
  { name: 'Grace Okafor',   email: 'grace@example.com',   role: 'customer', active: true },
  { name: 'Henry Dupont',   email: 'henry@example.com',   role: 'manager',  active: false },
];

async function seed() {
  const clear = process.argv.includes('--clear');
  const client = await pool.connect();
  try {
    if (clear) {
      await client.query('TRUNCATE TABLE users RESTART IDENTITY CASCADE');
      console.log('✅ users table cleared');
    }

    const fs = require('fs');
    const path = require('path');
    const schema = fs.readFileSync(path.join(__dirname, '../db/schema.sql'), 'utf8');
    await client.query(schema);

    for (const u of users) {
      await client.query(
        `INSERT INTO users (name, email, role, active)
         VALUES ($1, $2, $3, $4)
         ON CONFLICT (email) DO NOTHING`,
        [u.name, u.email, u.role, u.active]
      );
    }
    console.log(`✅ Seeded ${users.length} users`);
  } finally {
    client.release();
    await pool.end();
  }
}

seed().catch((err) => {
  console.error('Seed failed:', err);
  process.exit(1);
});
