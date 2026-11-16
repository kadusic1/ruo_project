CREATE TABLE invoices (
  id INT AUTO_INCREMENT PRIMARY KEY,
  number VARCHAR(50) NOT NULL,
  client VARCHAR(100) NOT NULL,
  amount DECIMAL(10, 2) NOT NULL,
  status ENUM('draft', 'sent', 'paid') NOT NULL DEFAULT 'draft',
  due_date DATE NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);
