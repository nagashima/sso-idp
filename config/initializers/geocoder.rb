# Geocoder設定
#
# 住所から緯度経度を取得するためのGeocoderの設定
# Google Geocoding APIを使用
#
# API KEY設定方法:
# 1. 環境変数: GOOGLE_GEOCODING_API_KEY（推奨、docker-compose.ymlで設定）
# 2. Rails credentials: rails credentials:edit で google.server_api_key に設定
#
# Google Geocoding API:
# - 無料枠: 1日2,500リクエストまで
# - 超過: $0.005/リクエスト
# - API KEYの取得: https://console.cloud.google.com/
Geocoder.configure(
  # Geocoding service設定
  timeout: 5,                      # タイムアウト（秒）
  lookup: :google,                 # Google Geocoding APIを使用
  api_key: ENV['GOOGLE_GEOCODING_API_KEY'] ||
           Rails.application.credentials.dig(:google, :server_api_key),

  # 単位設定
  units: :km,                      # 距離の単位（キロメートル）

  # キャッシュ設定（Redisを使用）
  cache: Rails.cache,
  cache_options: {
    expiration: 7.days,            # キャッシュ有効期限
    prefix: 'geocoder:'            # キャッシュキープレフィックス
  }
)
