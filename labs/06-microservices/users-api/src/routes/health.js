const router = require('express').Router();
router.get('/', (req, res) => {
  res.json({ status: 'ok', service: 'users-api', version: process.env.API_VERSION || '1.0.0', timestamp: new Date().toISOString() });
});
module.exports = router;
