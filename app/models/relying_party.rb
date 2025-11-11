class RelyingParty < ApplicationRecord
  has_and_belongs_to_many :users, join_table: 'user_relying_parties'

  validates :name, presence: true
  validates :domain, presence: true, uniqueness: true
  validates :api_key, presence: true, uniqueness: true
  validates :api_secret, presence: true

  # 論理削除
  def soft_delete
    update(deleted_at: Time.current)
  end

  def deleted?
    deleted_at.present?
  end

  # 有効なRPのみ取得
  scope :active, -> { where(deleted_at: nil) }
end
