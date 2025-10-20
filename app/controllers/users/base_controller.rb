class Users::BaseController < ApplicationController
  private
  
  def user_params
    params.require(:user).permit(:email, :password, :password_confirmation, :name, :birth_date, :address, :phone_number)
  end
end