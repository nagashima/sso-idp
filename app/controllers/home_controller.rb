class HomeController < ApplicationController
  def index
    # ログイン状態に応じた表示
    if logged_in?
      @relying_parties = RelyingParty.active.order(:name)
      @user_rp_ids = current_user.relying_party_ids
    end
  end
end