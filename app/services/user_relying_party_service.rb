class UserRelyingPartyService
  # ユーザーとRPの関連を作成または取得
  #
  # @param user [User] ユーザーオブジェクト
  # @param relying_party [RelyingParty] RPオブジェクト
  # @param metadata [Hash] RP固有情報（オプション、デフォルト: {}）
  # @param activate [Boolean] activated_atを設定するか（デフォルト: false）
  # @return [UserRelyingParty] 作成または既存のuser_relying_partyレコード
  def self.find_or_create(user:, relying_party:, metadata: {}, activate: false)
    raise ArgumentError, 'user is required' if user.nil?
    raise ArgumentError, 'relying_party is required' if relying_party.nil?

    user_rp = UserRelyingParty.find_or_initialize_by(
      user_id: user.id,
      relying_party_id: relying_party.id
    )

    if user_rp.new_record?
      user_rp.metadata = metadata
      user_rp.activated_at = Time.current if activate
      user_rp.save!
      Rails.logger.info "Created user-RP relationship: user_id=#{user.id}, rp_id=#{relying_party.id}, activated=#{activate}"
    elsif activate && user_rp.activated_at.nil?
      # 既存レコードでまだactivateされていない場合のみ
      user_rp.activated_at = Time.current
      user_rp.save!
      Rails.logger.info "Activated user-RP relationship: user_id=#{user.id}, rp_id=#{relying_party.id}"
    end

    user_rp
  end

  # ユーザーとRPの関連を作成または更新
  #
  # @param user [User] ユーザーオブジェクト
  # @param relying_party [RelyingParty] RPオブジェクト
  # @param metadata [Hash] RP固有情報
  # @param activate [Boolean] activated_atを設定するか（デフォルト: false）
  # @return [UserRelyingParty] 更新されたuser_relying_partyレコード
  def self.create_or_update(user:, relying_party:, metadata:, activate: false)
    raise ArgumentError, 'user is required' if user.nil?
    raise ArgumentError, 'relying_party is required' if relying_party.nil?
    raise ArgumentError, 'metadata is required' if metadata.nil?

    user_rp = UserRelyingParty.find_or_initialize_by(
      user_id: user.id,
      relying_party_id: relying_party.id
    )

    is_new = user_rp.new_record?
    user_rp.metadata = metadata
    user_rp.activated_at = Time.current if activate && user_rp.activated_at.nil?
    user_rp.save!

    action = is_new ? 'Created' : 'Updated'
    Rails.logger.info "#{action} user-RP relationship: user_id=#{user.id}, rp_id=#{relying_party.id}, activated=#{activate}"

    user_rp
  end
end
