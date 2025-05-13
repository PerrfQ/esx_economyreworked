DROP TABLE IF EXISTS transactions;
DROP TABLE IF EXISTS deliveries;
DROP TABLE IF EXISTS invoices;
DROP TABLE IF EXISTS treasury;
DROP TABLE IF EXISTS businesses;

CREATE TABLE businesses (
    id INT PRIMARY KEY AUTO_INCREMENT,
    type VARCHAR(20) NOT NULL,
    owner VARCHAR(50),
    lease_expiry DATETIME,
    funds INT DEFAULT 0,
    stock INT DEFAULT 0,
    blocked_until DATETIME,
    pending_fees INT DEFAULT 0,
    auto_renew BOOLEAN DEFAULT FALSE,
    price INT NOT NULL,
    INDEX idx_type (type)
);

CREATE TABLE invoices (
    id INT PRIMARY KEY AUTO_INCREMENT,
    business_id INT,
    amount INT,
    is_fictitious BOOLEAN DEFAULT FALSE,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    paid_at DATETIME,
    FOREIGN KEY (business_id) REFERENCES businesses(id),
    INDEX idx_business_id (business_id),
    INDEX idx_created_at (created_at)
);

CREATE TABLE deliveries (
    id INT PRIMARY KEY AUTO_INCREMENT,
    business_id INT,
    units INT,
    cost INT,
    type VARCHAR(10),
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (business_id) REFERENCES businesses(id),
    INDEX idx_business_id (business_id)
);

CREATE TABLE transactions (
    id INT PRIMARY KEY AUTO_INCREMENT,
    business_id INT,
    type VARCHAR(20),
    amount INT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (business_id) REFERENCES businesses(id),
    INDEX idx_business_id (business_id)
);

CREATE TABLE treasury (
    id INT PRIMARY KEY AUTO_INCREMENT,
    job_name VARCHAR(50),
    funds INT DEFAULT 0,
    last_tax DATETIME
);