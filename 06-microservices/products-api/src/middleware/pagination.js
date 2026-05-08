module.exports = (req, res, next) => {
  const page  = Math.max(1, parseInt(req.query.page)  || 1);
  const limit = Math.min(100, Math.max(1, parseInt(req.query.limit) || 10));
  req.pagination = { page, limit, offset: (page - 1) * limit };
  next();
};
