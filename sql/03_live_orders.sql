-- Simulates live traffic: one new order. Used in the PITR lab with:
--   for i in $(seq 1 30); do sudo -u postgres psql -q -d shopdb -f sql/03_live_orders.sql; sleep 2; done
-- so there is a stream of changes with timestamps you can recover to.

INSERT INTO orders (customer_id, product_id, quantity, amount)
SELECT 1 + floor(random() * 2000)::int, p.product_id, 1, p.price
FROM products p
ORDER BY random()
LIMIT 1;
