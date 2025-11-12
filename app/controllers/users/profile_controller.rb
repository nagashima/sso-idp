# frozen_string_literal: true

module Users
  class ProfileController < ApplicationController
    before_action :require_login

    # GET /users/profile
    def show
      @user = current_user
    end
  end
end
