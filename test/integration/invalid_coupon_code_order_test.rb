require "test_helper"

class InvalidCouponCodeOrderTest < ActionDispatch::IntegrationTest
  self.use_transactional_tests = false

  setup do
    ActionMailer::Base.deliveries.clear
    ExportedOrder.delete_all
    OrderExport.delete_all
    Order.delete_all
    PromiseFitnessKit.delete_all
    CouponCode.delete_all

    @kit = PromiseFitnessKit.create!(name: "Test Kit", description: "Test", slug: "test-kit-invalid-coupon-3")
    @valid_coupon = CouponCode.create!(code: "SK8000CCC", usage: "unused")
    @recipient = "admin@example.com"
  end

  test "order with invalid coupon code fails and shows error" do
    slug = @kit.slug

    assert_difference "Order.count", 0 do
      post "/#{slug}", params: {
        order: {
          first_name: "John",
          last_name: "Doe",
          address1: "123 Main St",
          city: "Miami",
          state: "FL",
          zip: "33101",
          phone: "3055551234",
          email: "john@example.com",
          coupon_code_input: "INVALID123"
        }
      }
    end

    assert_response :unprocessable_entity
    assert_equal "Invalid coupon code", flash[:error]
  end

  test "order with non-existent coupon code fails and shows error" do
    slug = @kit.slug

    assert_difference "Order.count", 0 do
      post "/#{slug}", params: {
        order: {
          first_name: "John",
          last_name: "Doe",
          address1: "123 Main St",
          city: "Miami",
          state: "FL",
          zip: "33101",
          phone: "3055551234",
          email: "john@example.com",
          coupon_code_input: "SK9999ZZZ"
        }
      }
    end

    assert_response :unprocessable_entity
    assert_equal "Invalid coupon code", flash[:error]
  end

  test "order with already used coupon code fails and shows error" do
    @valid_coupon.mark_as_used!
    slug = @kit.slug

    assert_difference "Order.count", 0 do
      post "/#{slug}", params: {
        order: {
          first_name: "John",
          last_name: "Doe",
          address1: "123 Main St",
          city: "Miami",
          state: "FL",
          zip: "33101",
          phone: "3055551234",
          email: "john@example.com",
          coupon_code_input: @valid_coupon.code
        }
      }
    end

    assert_response :unprocessable_entity
    assert_match /used before/, flash[:error]
  end

  test "no email sent when coupon code is invalid" do
    slug = @kit.slug

    post "/#{slug}", params: {
      order: {
        first_name: "John",
        last_name: "Doe",
        address1: "123 Main St",
        city: "Miami",
        state: "FL",
        zip: "33101",
        phone: "3055551234",
        email: "john@example.com",
        coupon_code_input: "INVALID123"
      }
    }

    assert_equal 0, ActionMailer::Base.deliveries.size, "No emails should be sent for failed order"
  end

  test "no email sent when coupon code is already used" do
    @valid_coupon.mark_as_used!
    slug = @kit.slug

    post "/#{slug}", params: {
      order: {
        first_name: "John",
        last_name: "Doe",
        address1: "123 Main St",
        city: "Miami",
        state: "FL",
        zip: "33101",
        phone: "3055551234",
        email: "john@example.com",
        coupon_code_input: @valid_coupon.code
      }
    }

    assert_equal 0, ActionMailer::Base.deliveries.size, "No emails should be sent for failed order"
  end

  test "valid coupon code creates order successfully" do
    slug = @kit.slug

    assert_difference "Order.count", 1 do
      post "/#{slug}", params: {
        order: {
          first_name: "John",
          last_name: "Doe",
          address1: "123 Main St",
          city: "Miami",
          state: "FL",
          zip: "33101",
          phone: "3055551234",
          email: "john@example.com",
          coupon_code_input: @valid_coupon.code
        }
      }
    end

    assert_redirected_to order_path(Order.last)
    assert_equal "Order placed successfully!", flash[:notice]
  end
end
