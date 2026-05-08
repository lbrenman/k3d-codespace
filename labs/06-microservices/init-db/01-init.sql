-- Run automatically by postgres container on first start
CREATE TABLE IF NOT EXISTS products (
  id          SERIAL PRIMARY KEY,
  name        VARCHAR(255) NOT NULL,
  description TEXT,
  price       NUMERIC(10, 2) NOT NULL,
  category    VARCHAR(100),
  stock       INTEGER NOT NULL DEFAULT 0,
  sku         VARCHAR(100) UNIQUE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE OR REPLACE FUNCTION update_products_updated_at()
RETURNS TRIGGER AS $$
BEGIN NEW.updated_at = NOW(); RETURN NEW; END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS set_products_updated_at ON products;
CREATE TRIGGER set_products_updated_at
  BEFORE UPDATE ON products FOR EACH ROW
  EXECUTE FUNCTION update_products_updated_at();

CREATE TABLE IF NOT EXISTS users (
  id         SERIAL PRIMARY KEY,
  name       VARCHAR(255) NOT NULL,
  email      VARCHAR(255) NOT NULL UNIQUE,
  role       VARCHAR(50)  NOT NULL DEFAULT 'customer',
  active     BOOLEAN      NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE OR REPLACE FUNCTION update_users_updated_at()
RETURNS TRIGGER AS $$
BEGIN NEW.updated_at = NOW(); RETURN NEW; END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS set_users_updated_at ON users;
CREATE TRIGGER set_users_updated_at
  BEFORE UPDATE ON users FOR EACH ROW
  EXECUTE FUNCTION update_users_updated_at();

INSERT INTO products (name, description, price, category, stock, sku) VALUES
  ('Wireless Headphones',  'Over-ear noise-cancelling headphones',         149.99, 'Electronics', 42,  'ELEC-WH-001'),
  ('Mechanical Keyboard',  'Tenkeyless, Cherry MX Brown switches',          89.99, 'Electronics', 18,  'ELEC-KB-002'),
  ('Desk Lamp',            'LED with adjustable brightness',                34.99, 'Home Office',  75,  'HOME-DL-003'),
  ('Standing Desk Mat',    'Anti-fatigue mat, 36x24 inches',               49.99, 'Home Office',  30,  'HOME-DM-004'),
  ('USB-C Hub',            '7-in-1 hub with HDMI, USB-A, SD card reader',  39.99, 'Electronics', 60,  'ELEC-HB-005')
ON CONFLICT (sku) DO NOTHING;

INSERT INTO users (name, email, role, active) VALUES
  ('Alice Martin',  'alice@example.com', 'admin',    true),
  ('Bob Chen',      'bob@example.com',   'customer', true),
  ('Carol Johnson', 'carol@example.com', 'customer', true),
  ('David Kim',     'david@example.com', 'customer', false),
  ('Eva Rossi',     'eva@example.com',   'manager',  true)
ON CONFLICT (email) DO NOTHING;
