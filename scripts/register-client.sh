#!/bin/bash
set -e

# シンプルなOAuth2クライアント登録スクリプト
# 使用方法: ./register-client.sh "https://localhost:3443/callback" [--first-party] [--cors-origin "domain1,domain2"]
# ex) ./register-client.sh "https://localhost:3443/auth/sso/callback" --first-party --cors-origin "https://idp.localhost,https://localhost:3443"

REDIRECT_URI="$1"
FIRST_PARTY=false
CORS_ORIGINS=""

# 引数パース
shift
while [[ $# -gt 0 ]]; do
    case $1 in
        --first-party)
            FIRST_PARTY=true
            shift
            ;;
        --cors-origin)
            CORS_ORIGINS="$2"
            shift 2
            ;;
        *)
            echo "❌ 不明なオプション: $1"
            exit 1
            ;;
    esac
done

# バリデーション
if [ -z "$REDIRECT_URI" ]; then
    echo "❌ 使用方法: $0 REDIRECT_URI [--first-party] [--cors-origin \"domain1,domain2\"]"
    echo ""
    echo "例:"
    echo "  $0 \"http://localhost:3001/auth/callback\""
    echo "  $0 \"http://localhost:3001/auth/callback\" --first-party"
    echo "  $0 \"https://localhost:3443/auth/sso/callback\" --first-party --cors-origin \"https://idp.localhost,https://localhost:3443\""
    exit 1
fi

# Hydra起動確認
echo "🔍 Hydra確認中..."
until docker-compose exec hydra wget -q --spider http://localhost:4444/health/ready 2>/dev/null; do
    echo "⏳ Hydra起動待ち..."
    sleep 2
done

# コマンド構築
HYDRA_CMD="docker-compose exec hydra hydra create oauth2-client"
HYDRA_CMD="$HYDRA_CMD --endpoint http://localhost:4445"
HYDRA_CMD="$HYDRA_CMD --format json"
HYDRA_CMD="$HYDRA_CMD --name \"Simple RP Client\""
HYDRA_CMD="$HYDRA_CMD --scope openid --scope profile --scope email"
HYDRA_CMD="$HYDRA_CMD --grant-type authorization_code --grant-type refresh_token"
HYDRA_CMD="$HYDRA_CMD --response-type code"
HYDRA_CMD="$HYDRA_CMD --redirect-uri \"$REDIRECT_URI\""

# metadata追加
if [ "$FIRST_PARTY" = true ]; then
    HYDRA_CMD="$HYDRA_CMD --metadata '{\"first_party\": true}'"
fi

# CORS設定追加
if [ -n "$CORS_ORIGINS" ]; then
    IFS=',' read -ra DOMAINS <<< "$CORS_ORIGINS"
    for domain in "${DOMAINS[@]}"; do
        domain=$(echo "$domain" | xargs)  # trim whitespace
        HYDRA_CMD="$HYDRA_CMD --allowed-cors-origin \"$domain\""
    done
fi

# 実行
echo "📝 クライアント登録中..."
echo "   Redirect: $REDIRECT_URI"
echo "   First Party: $([ "$FIRST_PARTY" = true ] && echo "Yes" || echo "No")"
if [ -n "$CORS_ORIGINS" ]; then
    echo "   CORS Origins: $CORS_ORIGINS"
fi
echo ""

CLIENT_JSON=$(eval $HYDRA_CMD)

if [ $? -eq 0 ]; then
    CLIENT_ID=$(echo "$CLIENT_JSON" | jq -r '.client_id')
    CLIENT_SECRET=$(echo "$CLIENT_JSON" | jq -r '.client_secret')

    echo "✅ 登録完了!"
    echo ""
    echo "🔑 RP設定用:"
    echo "OAUTH2_CLIENT_ID=$CLIENT_ID"
    echo "OAUTH2_CLIENT_SECRET=$CLIENT_SECRET"
    echo "OAUTH2_ISSUER_URL=http://localhost:4444"
    echo "OAUTH2_REDIRECT_URI=$REDIRECT_URI"
else
    echo "❌ 登録失敗"
    exit 1
fi
