module Api
  module V1
    class UserInfoController < ApplicationController
      skip_before_action :verify_authenticity_token  # API用：CSRF保護をスキップ
      before_action :authenticate_with_bearer_token

      def show
        # アクセストークンから取得したユーザー情報を返す
        user = @current_oauth_user

        # 住所を連結（自宅住所のみ）
        full_address = nil
        if user.home_master_city_id.present?
          full_address = [
            user.home_master_city&.master_prefecture&.name,
            user.home_master_city&.county_name,
            user.home_master_city&.name,
            user.home_address_town,
            user.home_address_later
          ].compact.join('')
        end

        render json: {
          uid: user.id.to_s,
          email: user.email,
          name: user.full_name,
          birth_date: user.birth_date,
          phone_number: user.phone_number,
          address: full_address,
          email_verified: user.activated?
        }
      end

      private

      def authenticate_with_bearer_token
        # Authorization: Bearer <access_token> からトークンを取得
        token = request.headers['Authorization']&.gsub(/^Bearer\s+/, '')

        unless token
          render json: { error: 'Authorization header missing' }, status: :unauthorized
          return
        end

        # アクセストークンの検証とユーザー情報取得
        user_info = verify_access_token(token)

        unless user_info
          render json: { error: 'Invalid or expired access token' }, status: :unauthorized
          return
        end

        @current_oauth_user = user_info
      end

      def verify_access_token(token)
        # ORY HydraのIntrospectionエンドポイントでトークンを検証
        # 注: Hydra Admin API (4445)は内部ネットワークから認証不要
        #     tokenパラメータだけでユーザーを特定できるため、basic_authは不要
        uri = URI("#{ENV['HYDRA_ADMIN_URL']}/admin/oauth2/introspect")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == 'https'
        http.verify_mode = OpenSSL::SSL::VERIFY_NONE # 開発環境用

        request = Net::HTTP::Post.new(uri)
        request.set_form_data({ token: token })

        response = http.request(request)

        if response.code == '200'
          introspection = JSON.parse(response.body)

          # トークンがアクティブかチェック
          if introspection['active']
            user_id = introspection['sub']
            User.find_by(id: user_id)
          else
            nil
          end
        else
          nil
        end
      rescue => e
        Rails.logger.error "Token introspection failed: #{e.message}"
        nil
      end
    end
  end
end
