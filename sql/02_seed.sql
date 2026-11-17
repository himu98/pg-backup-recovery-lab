-- Fills the shop with sample data. Safe to run more than once (adds more orders each time).
-- Change the 50000 below to make the database bigger and see how restore time grows.

INSERT INTO customers (full_name, email, city)
SELECT 'Customer ' || g,
       'customer' || g || '@example.com',
       (ARRAY['Dhaka','Chattogram','Sylhet','Khulna','Rajshahi'])[1 + g % 5]
FROM generate_series(1, 2000) AS g
ON CONFLICT (email) DO NOTHING;

INSERT INTO products (name, price)
SELECT 'Product ' || g, round((50 + random() * 4950)::numeric, 2)
FROM generate_series(1, 200) AS g
WHERE NOT EXISTS (SELECT 1 FROM products);

INSERT INTO orders (customer_id, product_id, quantity, amount, created_at)
SELECT c, p, q, q * pr.price, now() - (random() * interval '90 days')
FROM (
    SELECT 1 + floor(random() * 2000)::int AS c,
           1 + floor(random() * 200)::int  AS p,
           1 + floor(random() * 5)::int    AS q
    FROM generate_series(1, 50000)
) s
JOIN products pr ON pr.product_id = s.p;

ANALYZE;
