# frozen_string_literal: true

class Master::Prefecture < ApplicationRecord
  self.table_name = 'master_prefectures'

  has_many :cities, class_name: 'Master::City', foreign_key: :master_prefecture_id, dependent: :restrict_with_error

  validates :name, presence: true
  validates :kana_name, presence: true
end
