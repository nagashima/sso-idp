# JWT設定
module JwtConfig
  # JWTの有効期限（分）
  TOKEN_EXPIRATION_MINUTES = ENV.fetch('JWT_EXPIRATION_MINUTES', '30').to_i

  # Hydra設定
  HYDRA_PUBLIC_URL = ENV.fetch('HYDRA_PUBLIC_URL', 'http://localhost:4444').freeze
  HYDRA_ADMIN_URL = ENV.fetch('HYDRA_ADMIN_URL', 'http://localhost:4445').freeze
end