Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Root
  root "home#index"

  # Email Verification (共通エンドポイント)
  get 'verify_email/:token', to: 'verify_email#verify', as: 'verify_email'
  
  # Development tools
  if Rails.env.development?
    mount LetterOpenerWeb::Engine, at: "/letter_opener"
    get 'test-react', to: 'test_react#index'
  end
  
  # OAuth2 / OpenID Connect関連ルート（SSO機能）
  namespace :sso do
    # ページ（エントリポイント）
    get 'sign_in', to: 'sign_in#index'
    get 'sign_up', to: 'sign_up#index'

    # 旧実装（削除予定）
    # post 'sign_in', to: 'sign_in#authenticate'           # 第1段階認証（旧）
    # get 'sign_in/verify', to: 'sign_in#verification_form' # 第2段階認証フォーム（旧）
    # post 'sign_in/verify', to: 'sign_in#verify'           # 第2段階認証処理（旧）

    get 'consent', to: 'consent#consent'
    post 'consent', to: 'consent#accept'
    get 'sign_out', to: 'sign_out#logout'                # Hydraからのログアウト要求
    post 'sign_out', to: 'sign_out#logout'               # 互換性のため

    # API
    namespace :api do
      namespace :sign_in do
        post 'authenticate', to: 'authenticate#create'
        post 'verify', to: 'verify#create'
      end
      namespace :sign_up do
        post 'email', to: 'email#create'
        post 'password', to: 'password#create'
        post 'profile', to: 'profile#create'
        post 'complete', to: 'complete#create'
      end
    end
  end
  
  # Users機能（通常WEB）
  namespace :users do
    # ページ（エントリポイント）
    get 'sign_in', to: 'sign_in#index'
    get 'sign_up', to: 'sign_up#index'
    delete 'sign_out', to: 'sign_out#destroy'
    get 'profile', to: 'profile#show'

    # API
    namespace :api do
      namespace :sign_in do
        post 'authenticate', to: 'authenticate#create'
        post 'verify', to: 'verify#create'
      end
      namespace :sign_up do
        post 'email', to: 'email#create'
        post 'password', to: 'password#create'
        post 'profile', to: 'profile#create'
        post 'complete', to: 'complete#create'
      end
    end
  end

  # API（外部提供）
  namespace :api do
    # 共通API（内部用）
    namespace :common do
      # 住所検索
      post 'address_search', to: 'address_search#index'
      get 'address_search/prefectures', to: 'address_search#prefectures'
      get 'address_search/cities', to: 'address_search#cities'
    end

    # RP用API（バージョン付き）
    namespace :v1 do
      get 'user_info', to: 'user_info#show'

      # ユーザー情報管理API
      resources :users, only: [:index, :show, :create, :update]
    end
  end
end
