require "test_helper"

class AdminOrderExportsRequestsTest < ActionDispatch::IntegrationTest
  setup do
    @admin = admin_users(:one)
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
    assert_select "form[action=?]", admin_order_exports_path, 1
    assert_select "input[name=?]", "order_export[recipient]"
    assert_select "input[name=?]", "order_export[ends_at]"
  end

  test "POST /admin/order_exports enqueues Admin::SendOrderExportJob for authenticated admin" do
    login_as_admin(@admin)

    assert_enqueued_with(job: Admin::SendOrderExportJob) do
      post "/admin/order_exports", params: {
        order_export: {
          recipient: "ops@example.com",
          ends_at: Time.current.in_time_zone(OrderExportSettings::Config.timezone).strftime("%Y-%m-%d %H:%M")
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

  test "admin can retry a failed export but not uncertain delivery" do
    login_as_admin(@admin)
    failed = OrderExport.create!(status: "failed", scheduled_for: Time.current.utc, recipient: "ops@example.com")
    uncertain = OrderExport.create!(status: "review_required", scheduled_for: Time.current.utc, recipient: "ops@example.com", delivery_started_at: Time.current.utc)

    assert_enqueued_with(job: Admin::SendOrderExportJob, args: [ failed.scheduled_for, { recipient: failed.recipient, manual: true, export_id: failed.id } ]) do
      post admin_retry_order_export_path(failed)
    end
    assert_redirected_to new_admin_order_exports_path

    assert_no_enqueued_jobs do
      post admin_retry_order_export_path(uncertain)
    end
    assert_redirected_to new_admin_order_exports_path

    assert_enqueued_with(job: Admin::SendOrderExportJob, args: [ uncertain.scheduled_for, { recipient: uncertain.recipient, manual: true, export_id: uncertain.id } ]) do
      post admin_retry_order_export_path(uncertain), params: { confirmed_undelivered: "1" }
    end
    assert_redirected_to new_admin_order_exports_path
    assert_nil uncertain.reload.delivery_started_at
    assert_equal "failed", uncertain.status
  end
end
