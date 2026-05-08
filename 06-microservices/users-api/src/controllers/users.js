const pool = require('../db/client');
const buildPagination = (total, page, limit) => ({
  total, page, limit,
  totalPages: Math.ceil(total / limit),
  hasNext: page * limit < total,
  hasPrev: page > 1,
});
exports.list = async (req, res) => {
  const { limit, offset, page } = req.pagination;
  try {
    const [countResult, dataResult] = await Promise.all([
      pool.query('SELECT COUNT(*) FROM users'),
      pool.query('SELECT * FROM users ORDER BY id LIMIT $1 OFFSET $2', [limit, offset]),
    ]);
    res.json({ data: dataResult.rows, pagination: buildPagination(parseInt(countResult.rows[0].count), page, limit) });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Internal server error' }); }
};
exports.getById = async (req, res) => {
  try {
    const result = await pool.query('SELECT * FROM users WHERE id = $1', [req.params.id]);
    if (!result.rows.length) return res.status(404).json({ error: 'User not found' });
    res.json({ data: result.rows[0] });
  } catch (err) { console.error(err); res.status(500).json({ error: 'Internal server error' }); }
};
exports.create = async (req, res) => {
  const { name, email, role, active } = req.body;
  if (!name || !email) return res.status(400).json({ error: 'name and email are required' });
  try {
    const result = await pool.query(
      'INSERT INTO users (name, email, role, active) VALUES ($1, $2, $3, $4) RETURNING *',
      [name, email, role || 'customer', active !== undefined ? active : true]
    );
    res.status(201).json({ data: result.rows[0] });
  } catch (err) {
    if (err.code === '23505') return res.status(409).json({ error: 'Email already exists' });
    console.error(err); res.status(500).json({ error: 'Internal server error' });
  }
};
exports.update = async (req, res) => {
  const { name, email, role, active } = req.body;
  try {
    const result = await pool.query(
      'UPDATE users SET name=COALESCE($1,name), email=COALESCE($2,email), role=COALESCE($3,role), active=COALESCE($4,active) WHERE id=$5 RETURNING *',
      [name, email, role, active, req.params.id]
    );
    if (!result.rows.length) return res.status(404).json({ error: 'User not found' });
    res.json({ data: result.rows[0] });
  } catch (err) {
    if (err.code === '23505') return res.status(409).json({ error: 'Email already exists' });
    console.error(err); res.status(500).json({ error: 'Internal server error' });
  }
};
exports.remove = async (req, res) => {
  try {
    const result = await pool.query('DELETE FROM users WHERE id = $1 RETURNING id', [req.params.id]);
    if (!result.rows.length) return res.status(404).json({ error: 'User not found' });
    res.status(204).send();
  } catch (err) { console.error(err); res.status(500).json({ error: 'Internal server error' }); }
};
