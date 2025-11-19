# frozen_string_literal: true

# Userモデルの作成・更新を担当するService
# 会員登録およびプロフィール更新の業務ロジックを管理
class UserService
  # 会員登録からUser作成
  # SignupServiceから呼び出される
  #
  # @param email [String] メールアドレス
  # @param password [String] 平文パスワード
  # @param profile [Hash] プロフィール情報（last_name, first_name等）
  # @return [User, nil] 作成されたUserオブジェクト、失敗時はnil
  def self.create_from_signup(email:, password:, profile: {})
    profile_data = profile.symbolize_keys

    # 自宅住所から緯度経度を自動算出
    if profile_data[:home_master_city_id].present?
      coordinates = AddressService.coordinates(
        profile_data[:home_master_city_id],
        profile_data[:home_address_town] || ''
      )
      profile_data[:home_latitude] = coordinates[:latitude]
      profile_data[:home_longitude] = coordinates[:longitude]

      Rails.logger.info "Geocoded home address: city_id=#{profile_data[:home_master_city_id]}, " \
                        "lat=#{coordinates[:latitude]}, lng=#{coordinates[:longitude]}"
    end

    User.create!(
      email: email,
      password: password,
      password_confirmation: password,
      **profile_data
    )
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error "UserService.create_from_signup failed: #{e.message}"
    Rails.logger.error e.record.errors.full_messages.join(', ') if e.record
    nil
  end

  # プロフィール更新
  #
  # @param user [User] 更新対象のUserオブジェクト
  # @param profile [Hash] 更新するプロフィール情報
  # @return [Boolean] 更新成功時true、失敗時false
  def self.update_profile(user, profile)
    user.update!(profile.symbolize_keys)
    true
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error "UserService.update_profile failed: #{e.message}"
    false
  end
end
