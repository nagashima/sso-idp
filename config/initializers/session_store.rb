# ActionDispatch::Session::CacheStore（既存のValkey cache_storeを活用）
# HTTPS環境では secure フラグ必須
if ENV['HOST_PORT'] == '443'
  # HTTPS環境: secure フラグ付き
  Rails.application.config.session_store :cache_store,
    expire_after: 90.minutes,
    key: "_idp_session",
    secure: true,
    httponly: true
else
  # HTTP環境: secure フラグなし
  Rails.application.config.session_store :cache_store,
    expire_after: 90.minutes,
    key: "_idp_session"
end

# 参考: 他の試行履歴
# redis-session-store → Rails 8 API未対応でCSRF問題
# cookie_store → 正常動作（バックアップ）