# frozen_string_literal: true

# Form Objectsの基底クラス
# ActiveModel::Modelを利用してバリデーションとモデルライクな振る舞いを提供
class Form
  include ActiveModel::Model

  # 共通の正規表現パターン
  VALID_HIRAGANA_REGEX = /\A[ぁ-んー]+\z/
  VALID_POSTAL_CODE_REGEX = /\A\d{3}-?\d{4}\z/
  VALID_EMAIL_REGEX = /\A[\w+\-.]+@[a-z\d\-.]+\.[a-z]+\z/i
  # 電話番号は形式チェックなし（産後ケアRPと同じ）

  # ActiveModel::Model.initialize()をオーバーライド
  # 文字列の数字を自動的にIntegerに変換
  #
  # @param params [Hash] 初期化パラメータ
  def initialize(params = {})
    if params
      params.each do |attr, value|
        # 文字列が数字のみで構成されている場合、整数に変換
        # 改行を含む文字列は除外
        if value.is_a?(String) && /^([1-9]\d*|0)$/.match(value) && !value.match(/(\n)/)
          params[attr] = value.to_i
        end
      end
    end

    super(params)
  end

  # モデルからFormオブジェクトを初期化
  #
  # @param model [ActiveRecord::Base] モデルオブジェクト
  # @return [Form] 初期化されたFormオブジェクト
  def self.initialize_with_model(model)
    instance = new

    columns = ActiveRecord::Base.connection.columns(model.class.table_name).map(&:name)
    columns -= %w[created_at updated_at deleted_at]

    columns.each do |column|
      method = "#{column}="
      instance.send(method, model.send(column)) if instance.respond_to?(method)
    end

    instance
  end
end
