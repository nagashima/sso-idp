class UserRelyingParty < ApplicationRecord
  belongs_to :user
  belongs_to :relying_party

  # バリデーション
  validates :user_id, presence: true
  validates :relying_party_id, presence: true
  validates :user_id, uniqueness: { scope: :relying_party_id }

  # metadataのデフォルト値設定
  after_initialize :set_default_metadata, if: :new_record?

  private

  def set_default_metadata
    self.metadata ||= {}
  end
end
