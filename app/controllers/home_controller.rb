class HomeController < ApplicationController
  def index
    # ログイン状態に応じた表示
    if logged_in?
      @relying_parties = RelyingParty.active.order(:name)
      # activated_at が設定されているRP（実際に利用開始済み）のみ
      @user_rp_ids = current_user.user_relying_parties.where.not(activated_at: nil).pluck(:relying_party_id)
    end
  end
end