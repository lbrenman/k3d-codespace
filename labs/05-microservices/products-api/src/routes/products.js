const router = require('express').Router();
const paginate = require('../middleware/pagination');
const c = require('../controllers/products');

router.get('/',     paginate, c.list);
router.get('/:id',           c.getById);
router.post('/',             c.create);
router.put('/:id',           c.update);
router.delete('/:id',        c.remove);

module.exports = router;
