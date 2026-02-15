require "test_helper"

class AdminOrderExportsRequestsTest < ActionDispatch::IntegrationTest
  setup do
    @admin = admins(:one)
    # Ensure clean job queue and mail deliveries
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
    ActionMailer::Base.deliveries.clear
  end

  def login_as_admin(admin)
    post admin_login_url, params: { username: admin.username, password: "password123" }
    assert_response :redirect
    follow_redirect! rescue nil
  end

  test "GET /admin/order_exports/new requires authentication" do
    get "/admin/order_exports/new"
    # Expect redirect to admin login when unauthenticated
    assert_response :redirect
    assert_redirected_to admin_login_url
  end

  test "GET /admin/order_exports/new for authenticated admin returns success and shows form" do
    login_as_admin(@admin)

    get "/admin/order_exports/new"
    assert_response :success

    # The new view should include a form to submit an export request
    assert_select "form", 1
    assert_select "input[name=?]", "order_export[recipient]"
    assert_select "input[name=?]", "order_export[ends_at]"
  end

  test "POST /admin/order_exports enqueues Admin::SendOrderExportJob for authenticated admin" do
    login_as_admin(@admin)

    assert_enqueued_with(job: Admin::SendOrderExportJob) do
      post "/admin/order_exports", params: {
        order_export: {
          recipient: "ops@example.com",
          ends_at: Time.current.in_time_zone(OrderExport::Config.timezone).strftime("%Y-%m-%d %H:%M")
        }
      }
    end

    # After enqueue, user is redirected (controller redirects to admin dashboard)
    assert_response :redirect
  end

  test "POST /admin/order_exports redirects to login when unauthenticated" do
    post "/admin/order_exports", params: { order_export: { recipient: "ops@example.com" } }
    assert_response :redirect
    assert_redirected_to admin_login_url
  end
end
