const pool = require('../db/client');

const buildPagination = (total, page, limit) => ({
  total,
  page,
  limit,
  totalPages: Math.ceil(total / limit),
  hasNext: page * limit < total,
  hasPrev: page > 1,
});

exports.list = async (req, res) => {
  const { limit, offset, page } = req.pagination;
  try {
    const [countResult, dataResult] = await Promise.all([
      pool.query('SELECT COUNT(*) FROM products'),
      pool.query('SELECT * FROM products ORDER BY id LIMIT $1 OFFSET $2', [limit, offset]),
    ]);
    res.json({
      data: dataResult.rows,
      pagination: buildPagination(parseInt(countResult.rows[0].count), page, limit),
    });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Internal server error' });
  }
};

exports.getById = async (req, res) => {
  try {
    const result = await pool.query('SELECT * FROM products WHERE id = $1', [req.params.id]);
    if (!result.rows.length) return res.status(404).json({ error: 'Product not found' });
    res.json({ data: result.rows[0] });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Internal server error' });
  }
};

exports.create = async (req, res) => {
  const { name, description, price, category, stock, sku } = req.body;
  if (!name || price === undefined) {
    return res.status(400).json({ error: 'name and price are required' });
  }
  try {
    const result = await pool.query(
      `INSERT INTO products (name, description, price, category, stock, sku)
       VALUES ($1, $2, $3, $4, $5, $6) RETURNING *`,
      [name, description, price, category, stock ?? 0, sku]
    );
    res.status(201).json({ data: result.rows[0] });
  } catch (err) {
    if (err.code === '23505') return res.status(409).json({ error: 'SKU already exists' });
    console.error(err);
    res.status(500).json({ error: 'Internal server error' });
  }
};

exports.update = async (req, res) => {
  const { name, description, price, category, stock, sku } = req.body;
  try {
    const result = await pool.query(
      `UPDATE products SET
         name        = COALESCE($1, name),
         description = COALESCE($2, description),
         price       = COALESCE($3, price),
         category    = COALESCE($4, category),
         stock       = COALESCE($5, stock),
         sku         = COALESCE($6, sku)
       WHERE id = $7 RETURNING *`,
      [name, description, price, category, stock, sku, req.params.id]
    );
    if (!result.rows.length) return res.status(404).json({ error: 'Product not found' });
    res.json({ data: result.rows[0] });
  } catch (err) {
    if (err.code === '23505') return res.status(409).json({ error: 'SKU already exists' });
    console.error(err);
    res.status(500).json({ error: 'Internal server error' });
  }
};

exports.remove = async (req, res) => {
  try {
    const result = await pool.query('DELETE FROM products WHERE id = $1 RETURNING id', [req.params.id]);
    if (!result.rows.length) return res.status(404).json({ error: 'Product not found' });
    res.status(204).send();
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Internal server error' });
  }
};
