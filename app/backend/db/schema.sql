CREATE TABLE IF NOT EXISTS invoices (
  id INT AUTO_INCREMENT PRIMARY KEY,
  number VARCHAR(50) NOT NULL,
  client VARCHAR(100) NOT NULL,
  amount DECIMAL(10, 2) NOT NULL,
  status ENUM('draft', 'sent', 'paid') NOT NULL DEFAULT 'draft',
  due_date DATE NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Inicijalni podaci za demonstraciju i testiranje aplikacije (seed data)
INSERT INTO invoices (number, client, amount, status, due_date)
SELECT 'INV-2026-001', 'Univerzitet u Zenici', 1250.00, 'paid', '2026-12-01'
WHERE NOT EXISTS (SELECT 1 FROM invoices WHERE number = 'INV-2026-001');

INSERT INTO invoices (number, client, amount, status, due_date)
SELECT 'INV-2026-002', 'Cloud Solutions d.o.o.', 3400.50, 'sent', '2026-12-15'
WHERE NOT EXISTS (SELECT 1 FROM invoices WHERE number = 'INV-2026-002');
