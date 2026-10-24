module AdminSession
  private

  def current_admin
    return nil unless session[:admin_id]

    expires_at = session[:admin_expires_at]&.to_time
    if expires_at.nil? || expires_at <= Time.current
      session.delete(:admin_id)
      session.delete(:admin_expires_at)
      return nil
    end

    @current_admin ||= AdminUser.find_by(id: session[:admin_id])
  end
end
