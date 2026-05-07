module.exports = (req, res, next) => {
  const mode = process.env.AUTH_MODE || 'apikey';
  if (mode === 'none') return next();
  const key = req.headers['x-api-key'];
  if (!key || key !== process.env.API_KEY) {
    return res.status(401).json({ error: 'Unauthorized — invalid or missing x-api-key header' });
  }
  next();
};
