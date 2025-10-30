#!/usr/bin/env bash
set -e

# appコンテナ内から実行するOAuth2クライアント登録スクリプト
# 開発環境・AWS環境共通で使用可能
#
# 使用方法:
#   開発環境: docker-compose exec app ./scripts/register-client-from-app.sh "https://localhost:3443/callback" [--first-party] [--cors-origin "domain1,domain2"]
#   AWS環境:  aws ecs execute-command --cluster my-cluster --task <task-id> --container app --interactive --command "/bin/bash"
#            bash-5.1$ ./scripts/register-client-from-app.sh "https://rp.example.com/callback" [--first-party]
#
# 例:
#   ./scripts/register-client-from-app.sh "https://localhost:3443/auth/sso/callback" --first-party --cors-origin "https://localhost:4443,https://localhost:3443"

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
    echo "  $0 \"https://localhost:3443/auth/sso/callback\" --first-party --cors-origin \"https://localhost:4443,https://localhost:3443\""
    exit 1
fi

# Hydra起動確認
echo "🔍 Hydra確認中..."
until curl -f -s http://hydra:4444/health/ready >/dev/null 2>&1; do
    echo "⏳ Hydra起動待ち..."
    sleep 2
done

# リダイレクトURIからホスト名を抽出（クライアント名として使用）
CLIENT_NAME=$(echo "$REDIRECT_URI" | sed -E 's|^https?://([^/]+).*|\1|')

# JSON構築
echo "📝 クライアント登録中..."
echo "   Redirect: $REDIRECT_URI"
echo "   First Party: $([ "$FIRST_PARTY" = true ] && echo "Yes" || echo "No")"
if [ -n "$CORS_ORIGINS" ]; then
    echo "   CORS Origins: $CORS_ORIGINS"
fi
echo ""

# JSON payload構築
JSON_PAYLOAD='{'
JSON_PAYLOAD="$JSON_PAYLOAD\"client_name\":\"$CLIENT_NAME\","
JSON_PAYLOAD="$JSON_PAYLOAD\"redirect_uris\":[\"$REDIRECT_URI\"],"
JSON_PAYLOAD="$JSON_PAYLOAD\"grant_types\":[\"authorization_code\",\"refresh_token\"],"
JSON_PAYLOAD="$JSON_PAYLOAD\"response_types\":[\"code\"],"
JSON_PAYLOAD="$JSON_PAYLOAD\"scope\":\"openid profile email\""

# metadata追加
if [ "$FIRST_PARTY" = true ]; then
    JSON_PAYLOAD="$JSON_PAYLOAD,\"metadata\":{\"first_party\":true}"
fi

# CORS設定追加
if [ -n "$CORS_ORIGINS" ]; then
    JSON_PAYLOAD="$JSON_PAYLOAD,\"allowed_cors_origins\":["
    IFS=',' read -ra DOMAINS <<< "$CORS_ORIGINS"
    FIRST_DOMAIN=true
    for domain in "${DOMAINS[@]}"; do
        domain=$(echo "$domain" | xargs)  # trim whitespace
        if [ "$FIRST_DOMAIN" = true ]; then
            JSON_PAYLOAD="$JSON_PAYLOAD\"$domain\""
            FIRST_DOMAIN=false
        else
            JSON_PAYLOAD="$JSON_PAYLOAD,\"$domain\""
        fi
    done
    JSON_PAYLOAD="$JSON_PAYLOAD]"
fi

JSON_PAYLOAD="$JSON_PAYLOAD}"

# Hydra Admin API呼び出し
CLIENT_JSON=$(curl -s -X POST http://hydra:4445/admin/clients \
    -H "Content-Type: application/json" \
    -d "$JSON_PAYLOAD")

if [ $? -eq 0 ]; then
    # JSONパース（sed使用、jq不要）
    CLIENT_ID=$(echo "$CLIENT_JSON" | sed -n 's/.*"client_id":"\([^"]*\)".*/\1/p')
    CLIENT_SECRET=$(echo "$CLIENT_JSON" | sed -n 's/.*"client_secret":"\([^"]*\)".*/\1/p')

    # エラーチェック
    if [ -z "$CLIENT_ID" ] || [ -z "$CLIENT_SECRET" ]; then
        echo "❌ 登録失敗: レスポンスのパースに失敗しました"
        echo ""
        echo "レスポンス:"
        echo "$CLIENT_JSON"
        exit 1
    fi

    # 見やすく整形して出力
    cat << EOF

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ OAuth2 Client 登録完了
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Client Name: $CLIENT_NAME
Callback URL: $REDIRECT_URI
First Party: $([ "$FIRST_PARTY" = true ] && echo "Yes" || echo "No")

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📋 RP側に送付する情報（コピーしてSlack/メール等で共有）
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

CLIENT_ID=$CLIENT_ID
CLIENT_SECRET=$CLIENT_SECRET

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📝 RP側の .env.local 設定内容
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

OAUTH_CLIENT_ID=$CLIENT_ID
OAUTH_CLIENT_SECRET=$CLIENT_SECRET

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

EOF

    # オプション: ファイルに保存
    mkdir -p tmp
    OUTPUT_FILE="tmp/client-${CLIENT_NAME}.env"
    cat > "$OUTPUT_FILE" << EOF
# OAuth2 Client Credentials for $CLIENT_NAME
# Generated: $(date)
# Callback URL: $REDIRECT_URI

OAUTH_CLIENT_ID=$CLIENT_ID
OAUTH_CLIENT_SECRET=$CLIENT_SECRET
EOF

    echo "💾 設定ファイルを保存しました: $OUTPUT_FILE"
    echo ""
else
    echo "❌ 登録失敗"
    exit 1
fi
