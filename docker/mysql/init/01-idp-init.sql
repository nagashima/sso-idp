-- Rails 8.0 SSO Identity Provider Database Initialization

-- railsユーザーの作成
CREATE USER IF NOT EXISTS 'rails'@'%' IDENTIFIED BY 'rails_password';

-- IdP用データベース
CREATE DATABASE IF NOT EXISTS `idp_development` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE DATABASE IF NOT EXISTS `idp_test` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- 権限設定
GRANT ALL PRIVILEGES ON `idp_development`.* TO 'rails'@'%';
GRANT ALL PRIVILEGES ON `idp_test`.* TO 'rails'@'%';
FLUSH PRIVILEGES;