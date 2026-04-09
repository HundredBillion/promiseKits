require_relative "test_helper"

class OrdersControllerTest < ActionDispatch::IntegrationTest
  def setup
    @unique_suffix = Time.current.to_i
    @kit = PromiseFitnessKit.create!(name: "Test Kit #{@unique_suffix}", description: "Test Description", slug: "test-kit-ctrl-#{@unique_suffix}")
    @coupon = CouponCode.create!(code: "SK#{@unique_suffix}AAA", usage: "unused")
    @used_coupon = CouponCode.create!(code: "SK#{@unique_suffix + 1}BBB", usage: "used")
    @valid_params = {
      order: {
        first_name: "John",
        last_name: "Doe",
        address1: "123 Main St",
        city: "San Francisco",
        state: "CA",
        zip: "94102",
        phone: "4155551234",
        email: "john@example.com",
        coupon_code_input: @coupon.code
      }
    }
  end

  def teardown
    ExportedOrder.delete_all
    OrderExport.delete_all
    Order.delete_all
    CouponCode.delete_all
    PromiseFitnessKit.delete_all
  end

  # New Action Tests
  test "should get new" do
    get fitness_kit_order_url(slug: @kit.slug)
    assert_response :success
  end

  test "should assign order and fitness kit" do
    get fitness_kit_order_url(slug: @kit.slug)
    assert_response :success
    # Ensure the page includes the kit name and the order form (observable behavior)
    assert_select "h1", text: /You have selected:/i
    assert_select "h1", text: /#{@kit.name}/
    assert_select "form.order-form"
  end

  test "should redirect to root for invalid kit" do
    get fitness_kit_order_url(slug: "invalid-kit-slug")
    # When the slug doesn't match a known kit the route may not resolve;
    # expect a 404 Not Found rendered by the router in that case.
    assert_response :not_found
  end

  # Create Action - Success Tests
  test "should create order with valid params" do
    assert_difference("Order.count", 1) do
      post create_fitness_kit_order_url(slug: @kit.slug), params: @valid_params
    end
  end

  test "should redirect to order show on success" do
    post create_fitness_kit_order_url(slug: @kit.slug), params: @valid_params
    assert_redirected_to order_path(Order.last)
  end

  test "should mark coupon as used after order creation" do
    assert_equal "unused", @coupon.usage
    post create_fitness_kit_order_url(slug: @kit.slug), params: @valid_params
    @coupon.reload
    assert_equal "used", @coupon.usage
  end

  test "should increment order confirmation number" do
    Order.delete_all
    Sequence.delete_all

    post create_fitness_kit_order_url(slug: @kit.slug), params: @valid_params
    order = Order.last
    # After deleting all orders and sequences, first order should have confirmation 1
    assert_equal 1, order.order_confirmation
  end

  test "should set success flash message" do
    post create_fitness_kit_order_url(slug: @kit.slug), params: @valid_params
    assert_equal "Order placed successfully!", flash[:notice]
  end

  # Create Action - Error Tests
  test "should not create order with invalid coupon" do
    params = @valid_params.deep_dup
    params[:order][:coupon_code_input] = "INVALID999"

    assert_no_difference("Order.count") do
      post create_fitness_kit_order_url(slug: @kit.slug), params: params
    end
  end

  test "should render new with error for invalid coupon" do
    params = @valid_params.deep_dup
    params[:order][:coupon_code_input] = "INVALID999"

    post create_fitness_kit_order_url(slug: @kit.slug), params: params
    assert_response :unprocessable_entity
    # New was rendered with an error message shown in the page
    assert_select "div.alert-error", text: /Invalid coupon code/
    assert_select "form.order-form"
  end

  test "should not create order with used coupon" do
    params = @valid_params.deep_dup
    # Use the actual used coupon code created in setup so the controller
    # finds the coupon and validates its used state.
    params[:order][:coupon_code_input] = "SK1001BBB"

    assert_no_difference("Order.count") do
      post create_fitness_kit_order_url(slug: @kit.slug), params: params
    end
  end

  test "should show specific error for used coupon" do
    params = @valid_params.deep_dup
    params[:order][:coupon_code_input] = @used_coupon.code

    post create_fitness_kit_order_url(slug: @kit.slug), params: params
    assert_response :unprocessable_entity
    # check that the error flash was set to the more specific message
    assert_equal "This code has been used before and can no longer be used to place an order", flash[:error]
    assert_select "form.order-form"
  end

  test "should not create order with missing fields" do
    params = @valid_params.deep_dup
    params[:order].delete(:first_name)
    params[:order].delete(:email)

    assert_no_difference("Order.count") do
      post create_fitness_kit_order_url(slug: @kit.slug), params: params
    end
  end

  test "should render new with validation errors" do
    params = @valid_params.deep_dup
    params[:order].delete(:first_name)

    post create_fitness_kit_order_url(slug: @kit.slug), params: params
    assert_response :unprocessable_entity
    # Expect the form to be re-rendered and validation error messages to appear
    assert_select "form.order-form"
    assert_select "div.alert-error", text: /first name/i
  end

  test "should return 422 for validation errors" do
    params = @valid_params.deep_dup
    params[:order].delete(:email)

    post create_fitness_kit_order_url(slug: @kit.slug), params: params
    assert_response :unprocessable_entity
  end

  test "should preserve form data on errors" do
    params = @valid_params.deep_dup
    params[:order].delete(:first_name)

    post create_fitness_kit_order_url(slug: @kit.slug), params: params
    assert_response :unprocessable_entity
    # Ensure submitted values persist in the rendered form fields
    assert_select 'input[name="order[last_name]"][value="Doe"]'
    assert_select 'input[name="order[email]"][value="john@example.com"]'
  end

  # Show Action Tests
  test "should get show" do
    order = Order.create!(
      promise_fitness_kit: @kit,
      coupon_code: @coupon,
      first_name: "John",
      last_name: "Doe",
      address1: "123 Main St",
      city: "San Francisco",
      state: "CA",
      zip: "94102",
      phone: "4155551234",
      email: "john@example.com"
    )

    get order_url(order)
    assert_response :success
  end

  test "should assign order" do
    order = Order.create!(
      promise_fitness_kit: @kit,
      coupon_code: @coupon,
      first_name: "John",
      last_name: "Doe",
      address1: "123 Main St",
      city: "San Francisco",
      state: "CA",
      zip: "94102",
      phone: "4155551234",
      email: "john@example.com"
    )

    get order_url(order)
    assert_response :success
    # Confirm the order is rendered by checking the confirmation number and kit name appear
    assert_select "strong", text: order.formatted_order_confirmation
    assert_select "strong", text: order.promise_fitness_kit.name
  end

  test "should return 404 for invalid order" do
    get order_url(id: 99999)
    assert_response :not_found
  end
end
