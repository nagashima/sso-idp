source "https://rubygems.org"

ruby "3.4.5"

# Rails 8.0系最新
gem "rails", "~> 8.0.2"

# Database & Server
gem "mysql2", "~> 0.5"
gem "puma", ">= 5.0"

# Core Rails features
gem "jbuilder"
gem "bootsnap", require: false

# Authentication & Security
gem "bcrypt", "~> 3.1.7"

# API & CORS
gem "rack-cors"

# HTTP client
gem "httparty"

# JWT for SSO authentication
gem "jwt"

# Redis/Valkey for cache & session
gem "redis", ">= 4.0.1"

# Frontend & Assets (Vite + React)
gem "vite_rails"

# Image processing
gem "image_processing", "~> 1.2"

# Windows support
gem "tzinfo-data", platforms: %i[ windows jruby ]

group :development, :test do
  gem "debug", platforms: %i[ mri windows ]
  gem "rspec-rails"
  gem "factory_bot_rails"
end

group :development do
  gem "letter_opener_web"
  gem "foreman"
  gem "web-console"
  
  # Debug & Profiler tools
  gem "rack-mini-profiler"  # Page performance profiler
  gem "bullet"              # N+1 query detector
end

group :test do
  gem "shoulda-matchers"
  gem "database_cleaner-active_record"
  gem "capybara"
  gem "selenium-webdriver"
end