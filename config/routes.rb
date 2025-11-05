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

  # Profile
  get 'profile', to: 'profile#show'

  # Email Verification (共通エンドポイント)
  get 'verify_email/:token', to: 'verify_email#verify', as: 'verify_email'
  
  # Authentication Routes
  get '/login', to: 'sessions/login#login'
  post '/login', to: 'sessions/login#authenticate'
  get '/login/verify', to: 'sessions/login#verification_form', as: :login_verify
  post '/login/verify', to: 'sessions/login#verify'
  delete '/logout', to: 'sessions/login#destroy', as: :logout
  
  # User Registration
  get 'users/new', to: 'users/new#new'
  post 'users/new/confirm', to: 'users/new#confirm'
  get 'users/new/confirm', to: 'users/new#confirm'
  post 'users/new/register', to: 'users/new#register'
  get 'users/new/complete', to: 'users/new#complete'
  
  # Email Activation
  get 'users/activate/:token', to: 'users/activation#activate', as: :users_activate
  get 'users/activated', to: 'users/activation#activated', as: :users_activated
  
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
    namespace :v1 do
      get 'user_info', to: 'user_info#show'
    end
  end
end
