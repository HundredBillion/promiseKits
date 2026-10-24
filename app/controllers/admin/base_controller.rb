class Admin::BaseController < ApplicationController
  include AdminSession
  before_action :require_admin
  layout "admin"

  private

  def require_admin
    unless current_admin
      redirect_to admin_login_path, alert: "Please log in to access admin area"
    end
  end

  helper_method :current_admin
end
