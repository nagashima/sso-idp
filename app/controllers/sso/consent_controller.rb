class Sso::ConsentController < ApplicationController
  before_action :require_login

  def consent
    # 1. consent_challengeパラメータを取得
    consent_challenge = params[:consent_challenge]

    if consent_challenge.blank?
      redirect_to root_path, alert: '不正なアクセスです'
      return
    end

    begin
      # 2. HydraClientで同意要求詳細を取得
      consent_request = HydraClient.get_consent_request(consent_challenge)


      # 3. 自動同意の判定
      if should_auto_consent?(consent_request)
        accept_consent_automatically(consent_challenge, consent_request)
      else
        # 4. 同意画面を表示
        @consent_request = consent_request
        @requested_scopes = consent_request['requested_scope'] || []
        @client_name = consent_request.dig('client', 'client_name') || 'Unknown Application'
        @consent_challenge = consent_challenge
      end

    rescue HydraError => e
      redirect_to root_path, alert: '同意処理中にエラーが発生しました'
    end
  end

  def accept
    consent_challenge = params[:consent_challenge]

    if consent_challenge.blank?
      redirect_to root_path, alert: '不正なアクセスです'
      return
    end

    begin
      # 同意要求詳細を再取得
      consent_request = HydraClient.get_consent_request(consent_challenge)

      # ユーザーが選択したスコープ（今回は全て許可）
      granted_scopes = consent_request['requested_scope'] || []

      # ユーザー情報をクレームとして準備
      user_claims = build_user_claims(current_user, granted_scopes)

      # ユーザーとRPの関連を保存
      rp = record_user_rp_relationship(consent_request)

      # 認証ログ: SSOログイン成功
      AuthenticationLoggerService.log_sign_in_success(
        user: current_user,
        request: request,
        sign_in_type: :sso,
        relying_party: rp
      )

      # 同意チャレンジを受け入れ
      response = HydraClient.accept_consent_request(
        consent_challenge,
        granted_scopes,
        user_claims
      )

      # Hydraから返されたリダイレクトURLに転送
      redirect_to response['redirect_to']

    rescue HydraError => e
      redirect_to login_path, alert: '同意処理中にエラーが発生しました'
    end
  end

  private

  # 自動同意すべきかの判定
  def should_auto_consent?(consent_request)
    # 1. Hydraのskipフラグが立っている場合
    return true if consent_request['skip']

    # 2a. Hydra Metadataでfirst_partyが指定されている場合
    client_metadata = consent_request.dig('client', 'metadata') || {}
    if client_metadata['first_party'] == true
      Rails.logger.info "Auto-consent due to metadata.first_party=true"
      return true
    end

    # 2b. 信頼できるクライアント（環境変数, 下位互換）
    if defined?(JwtConfig::TRUSTED_CLIENT_IDS) && JwtConfig::TRUSTED_CLIENT_IDS.present?
      trusted_clients = JwtConfig::TRUSTED_CLIENT_IDS.split(',').map(&:strip).reject(&:empty?)
      client_id = consent_request.dig('client', 'client_id')
      if trusted_clients.include?(client_id)
        Rails.logger.info "Auto-consent due to TRUSTED_CLIENT_IDS: #{client_id}"
        return true
      end
    end

    # 3. 基本スコープのみの場合（テスト用: emailを除外）
    requested_scopes = consent_request['requested_scope'] || []
    basic_scopes = ['openid', 'profile']  # emailを除外
    return true if (requested_scopes - basic_scopes).empty?

    false
  end

  def accept_consent_automatically(consent_challenge, consent_request)
    granted_scopes = consent_request['requested_scope'] || []
    user_claims = build_user_claims(current_user, granted_scopes)

    # ユーザーとRPの関連を保存
    rp = record_user_rp_relationship(consent_request)

    # 認証ログ: SSOログイン成功
    AuthenticationLoggerService.log_sign_in_success(
      user: current_user,
      request: request,
      sign_in_type: :sso,
      relying_party: rp
    )

    response = HydraClient.accept_consent_request(
      consent_challenge,
      granted_scopes,
      user_claims
    )

    redirect_to response['redirect_to']
  end

  def build_user_claims(user, granted_scopes)
    claims = {}

    # 基本クレーム（sub は必須）
    claims[:sub] = user.id.to_s

    # profileスコープが含まれている場合
    if granted_scopes.include?('profile')
      claims[:name] = user.full_name
      claims[:birthdate] = user.birth_date&.strftime('%Y-%m-%d')
    end

    # emailスコープが含まれている場合
    if granted_scopes.include?('email')
      claims[:email] = user.email
      claims[:email_verified] = true
    end

    # addressスコープが含まれている場合（カスタムスコープ）
    if granted_scopes.include?('address') && user.home_master_city_id.present?
      # 住所を連結（自宅住所のみ）
      full_address = [
        user.home_master_city&.master_prefecture&.name,
        user.home_master_city&.county_name,
        user.home_master_city&.name,
        user.home_address_town,
        user.home_address_later
      ].compact.join('')

      claims[:address] = {
        formatted: full_address
      }
    end

    # phoneスコープが含まれている場合（カスタムスコープ）
    if granted_scopes.include?('phone') && user.phone_number.present?
      claims[:phone_number] = user.phone_number
    end

    claims
  end

  # ユーザーとRPの関連を記録
  #
  # @param consent_request [Hash] Hydraから取得した同意要求情報
  # @return [RelyingParty, nil] RPオブジェクト
  def record_user_rp_relationship(consent_request)
    client_id = consent_request.dig('client', 'client_id')
    return nil if client_id.blank?

    # client_idからRelyingPartyを検索（api_keyがclient_idとして使われている）
    rp = RelyingParty.find_by(api_key: client_id)
    return nil unless rp

    # UserRelyingPartyServiceでレコード作成（SSO経由はmetadata空で作成）
    UserRelyingPartyService.find_or_create(
      user: current_user,
      relying_party: rp,
      metadata: {}
    )

    rp
  rescue StandardError => e
    # エラーログを出力するが、SSOログイン自体は継続
    Rails.logger.error "Failed to record user-RP relationship: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    nil
  end
end