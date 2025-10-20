-- ORY Hydra OAuth2 Server Database Initialization

-- Hydra用データベース
CREATE DATABASE IF NOT EXISTS `hydra_development` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- 権限設定
GRANT ALL PRIVILEGES ON `hydra_development`.* TO 'rails'@'%';
FLUSH PRIVILEGES;