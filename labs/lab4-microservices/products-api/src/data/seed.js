require('dotenv').config();
const pool = require('../db/client');

const products = [
  { name: 'Wireless Headphones', description: 'Over-ear noise-cancelling headphones', price: 149.99, category: 'Electronics', stock: 42, sku: 'ELEC-WH-001' },
  { name: 'Mechanical Keyboard', description: 'Tenkeyless mechanical keyboard, Cherry MX Brown switches', price: 89.99, category: 'Electronics', stock: 18, sku: 'ELEC-KB-002' },
  { name: 'Desk Lamp', description: 'LED desk lamp with adjustable brightness and color temperature', price: 34.99, category: 'Home Office', stock: 75, sku: 'HOME-DL-003' },
  { name: 'Standing Desk Mat', description: 'Anti-fatigue mat for standing desks, 36x24 inches', price: 49.99, category: 'Home Office', stock: 30, sku: 'HOME-DM-004' },
  { name: 'USB-C Hub', description: '7-in-1 USB-C hub with HDMI, USB-A, SD card reader', price: 39.99, category: 'Electronics', stock: 60, sku: 'ELEC-HB-005' },
  { name: 'Notebook Set', description: 'Set of 3 hardcover notebooks, A5 size', price: 19.99, category: 'Stationery', stock: 120, sku: 'STAT-NB-006' },
  { name: 'Webcam HD', description: '1080p webcam with built-in microphone', price: 59.99, category: 'Electronics', stock: 25, sku: 'ELEC-WC-007' },
  { name: 'Cable Management Kit', description: 'Velcro ties, clips, and sleeves for cable management', price: 14.99, category: 'Home Office', stock: 200, sku: 'HOME-CM-008' },
];

async function seed() {
  const clear = process.argv.includes('--clear');
  const client = await pool.connect();
  try {
    if (clear) {
      await client.query('TRUNCATE TABLE products RESTART IDENTITY CASCADE');
      console.log('✅ products table cleared');
    }

    // Apply schema
    const fs = require('fs');
    const path = require('path');
    const schema = fs.readFileSync(path.join(__dirname, '../db/schema.sql'), 'utf8');
    await client.query(schema);

    for (const p of products) {
      await client.query(
        `INSERT INTO products (name, description, price, category, stock, sku)
         VALUES ($1, $2, $3, $4, $5, $6)
         ON CONFLICT (sku) DO NOTHING`,
        [p.name, p.description, p.price, p.category, p.stock, p.sku]
      );
    }
    console.log(`✅ Seeded ${products.length} products`);
  } finally {
    client.release();
    await pool.end();
  }
}

seed().catch((err) => {
  console.error('Seed failed:', err);
  process.exit(1);
});
