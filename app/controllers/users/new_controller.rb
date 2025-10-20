class Users::NewController < Users::BaseController
  # 新規会員登録フォーム
  def new
    # 確認画面から戻った場合は入力値を復元
    user_data = Rails.cache.read("user_data:#{session.id}")
    if user_data
      @user = User.new(user_data)
    else
      @user = User.new
    end
  end

  # 登録確認画面（POST/GETの両方に対応）
  def confirm
    if request.post?
      # POST: フォームから送信された場合
      @user = User.new(user_params)
      if @user.valid?
        Rails.cache.write("user_data:#{session.id}", user_params.to_h, expires_in: 30.minutes)
        render :confirm
      else
        render :new, status: :unprocessable_entity
      end
    else
      # GET: 確認画面の直接アクセス
      user_data = Rails.cache.read("user_data:#{session.id}")
      unless user_data
        redirect_to users_new_path, alert: 'セッションが無効です。最初からやり直してください。'
        return
      end
      @user = User.new(user_data)
    end
  end

  # 仮登録処理
  def register
    user_data = Rails.cache.read("user_data:#{session.id}")
    unless user_data
      redirect_to users_new_path, alert: 'セッションが無効です。最初からやり直してください。'
      return
    end

    @user = User.new(user_data)
    if @user.save
      # 認証トークンを生成してメール送信
      @user.generate_activation_token!
      UserMailer.activation_email(@user).deliver_now
      
      Rails.cache.delete("user_data:#{session.id}")
      Rails.cache.write("registered_user:#{session.id}", @user.id, expires_in: 24.hours)
      redirect_to users_new_complete_path
    else
      # 保存に失敗した場合は新規登録画面に戻る
      render :new, status: :unprocessable_entity
    end
  end

  # 登録完了画面
  def complete
    user_id = Rails.cache.read("registered_user:#{session.id}")
    unless user_id
      redirect_to users_new_path, alert: '不正なアクセスです。'
      return
    end
    
    @user = User.find(user_id)
    Rails.cache.delete("registered_user:#{session.id}")
  end
end