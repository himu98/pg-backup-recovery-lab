-- A small online-shop database to back up, break and restore.
-- Run as: sudo -u postgres psql -d shopdb -f sql/01_schema.sql

CREATE TABLE IF NOT EXISTS customers (
    customer_id  serial PRIMARY KEY,
    full_name    text        NOT NULL,
    email        text        NOT NULL UNIQUE,
    city         text        NOT NULL,
    created_at   timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS products (
    product_id   serial PRIMARY KEY,
    name         text          NOT NULL,
    price        numeric(10,2) NOT NULL CHECK (price > 0)
);

CREATE TABLE IF NOT EXISTS orders (
    order_id     bigserial PRIMARY KEY,
    customer_id  int           NOT NULL REFERENCES customers(customer_id),
    product_id   int           NOT NULL REFERENCES products(product_id),
    quantity     int           NOT NULL CHECK (quantity > 0),
    amount       numeric(12,2) NOT NULL,
    created_at   timestamptz   NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_orders_created_at ON orders (created_at);
CREATE INDEX IF NOT EXISTS idx_orders_customer   ON orders (customer_id);
