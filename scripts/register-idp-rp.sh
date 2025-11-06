#!/usr/bin/env bash
set -e

# IdP RelyingPartyマスタ登録スクリプト（開発環境用）
# 使用方法: ./register-idp-rp.sh "RP名" "domain" "api_key" "api_secret" [--webhook-url "URL"] [--signin-url "URL"]
# 例: ./register-idp-rp.sh "検証用RP" "localhost:3443" "client_abc123" "secret_xyz789" --signin-url "https://localhost:3443/auth/sso"

RP_NAME="$1"
DOMAIN="$2"
API_KEY="$3"
API_SECRET="$4"
WEB_HOOK_URL=""
SIGN_IN_URL=""

# 引数チェック
if [ -z "$RP_NAME" ] || [ -z "$DOMAIN" ] || [ -z "$API_KEY" ] || [ -z "$API_SECRET" ]; then
    echo "❌ 使用方法: $0 RP名 domain api_key api_secret [--webhook-url URL] [--signin-url URL]"
    echo ""
    echo "例:"
    echo "  $0 \"検証用RP\" \"localhost:3443\" \"client_abc123\" \"secret_xyz789\""
    echo "  $0 \"本番RP\" \"example.com\" \"client_abc123\" \"secret_xyz789\" --webhook-url \"https://example.com/webhook\" --signin-url \"https://example.com/login\""
    exit 1
fi

# オプション引数パース
shift 4
while [[ $# -gt 0 ]]; do
    case $1 in
        --webhook-url)
            WEB_HOOK_URL="$2"
            shift 2
            ;;
        --signin-url)
            SIGN_IN_URL="$2"
            shift 2
            ;;
        *)
            echo "❌ 不明なオプション: $1"
            exit 1
            ;;
    esac
done

# Railsアプリ起動確認
echo "🔍 Rails確認中..."
until docker-compose exec app curl -f -s http://localhost:3000/up >/dev/null 2>&1; do
    echo "⏳ Rails起動待ち..."
    sleep 2
done

# RP登録
echo "📝 IdP RP登録中..."
echo "   名前: $RP_NAME"
echo "   ドメイン: $DOMAIN"
echo "   API Key: $API_KEY"
if [ -n "$WEB_HOOK_URL" ]; then
    echo "   WebHook URL: $WEB_HOOK_URL"
fi
if [ -n "$SIGN_IN_URL" ]; then
    echo "   Sign In URL: $SIGN_IN_URL"
fi
echo ""

# Rails runnerで登録
RAILS_CODE="
rp = RelyingParty.create!(
  name: '$RP_NAME',
  domain: '$DOMAIN',
  api_key: '$API_KEY',
  api_secret: '$API_SECRET',
  web_hook_url: $([ -n "$WEB_HOOK_URL" ] && echo "'$WEB_HOOK_URL'" || echo "nil"),
  sign_in_url: $([ -n "$SIGN_IN_URL" ] && echo "'$SIGN_IN_URL'" || echo "nil")
)
puts \"✅ RP登録完了: #{rp.name} (ID: #{rp.id})\"
"

docker-compose exec app bundle exec rails runner "$RAILS_CODE"

if [ $? -eq 0 ]; then
    cat << EOF

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ IdP RelyingParty 登録完了
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

RP名: $RP_NAME
ドメイン: $DOMAIN
API Key: $API_KEY

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

EOF
else
    echo "❌ 登録失敗"
    exit 1
fi
