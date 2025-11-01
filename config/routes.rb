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
  end
  
  # OAuth2 / OpenID Connect関連ルート（SSO機能）
  namespace :sso do
    get 'sign_in', to: 'sign_in#login'
    post 'sign_in', to: 'sign_in#authenticate'           # 第1段階認証
    get 'sign_in/verify', to: 'sign_in#verification_form' # 第2段階認証フォーム
    post 'sign_in/verify', to: 'sign_in#verify'           # 第2段階認証処理
    get 'consent', to: 'consent#consent'
    post 'consent', to: 'consent#accept'
    get 'sign_out', to: 'sign_out#logout'                # Hydraからのログアウト要求
    post 'sign_out', to: 'sign_out#logout'               # 互換性のため
  end
  
  # API
  namespace :api do
    namespace :v1 do
      get 'user_info', to: 'user_info#show'
    end
  end
end
