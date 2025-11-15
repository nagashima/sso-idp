class UserRelyingPartyService
  # ユーザーとRPの関連を作成または取得
  #
  # @param user [User] ユーザーオブジェクト
  # @param relying_party [RelyingParty] RPオブジェクト
  # @param metadata [Hash] RP固有情報（オプション、デフォルト: {}）
  # @return [UserRelyingParty] 作成または既存のuser_relying_partyレコード
  def self.find_or_create(user:, relying_party:, metadata: {})
    raise ArgumentError, 'user is required' if user.nil?
    raise ArgumentError, 'relying_party is required' if relying_party.nil?

    user_rp = UserRelyingParty.find_or_initialize_by(
      user_id: user.id,
      relying_party_id: relying_party.id
    )

    if user_rp.new_record?
      user_rp.metadata = metadata
      user_rp.save!
      Rails.logger.info "Created user-RP relationship: user_id=#{user.id}, rp_id=#{relying_party.id}"
    end

    user_rp
  end

  # ユーザーとRPの関連を作成または更新
  #
  # @param user [User] ユーザーオブジェクト
  # @param relying_party [RelyingParty] RPオブジェクト
  # @param metadata [Hash] RP固有情報
  # @return [UserRelyingParty] 更新されたuser_relying_partyレコード
  def self.create_or_update(user:, relying_party:, metadata:)
    raise ArgumentError, 'user is required' if user.nil?
    raise ArgumentError, 'relying_party is required' if relying_party.nil?
    raise ArgumentError, 'metadata is required' if metadata.nil?

    user_rp = UserRelyingParty.find_or_initialize_by(
      user_id: user.id,
      relying_party_id: relying_party.id
    )

    user_rp.metadata = metadata
    user_rp.save!

    action = user_rp.previously_new_record? ? 'Created' : 'Updated'
    Rails.logger.info "#{action} user-RP relationship: user_id=#{user.id}, rp_id=#{relying_party.id}"

    user_rp
  end
end
