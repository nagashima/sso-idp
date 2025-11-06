# frozen_string_literal: true

class ProfileController < ApplicationController
  before_action :require_login

  # GET /profile
  def show
    @user = current_user
  end
end
