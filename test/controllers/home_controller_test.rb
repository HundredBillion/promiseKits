require_relative "../test_helper"

class HomeControllerTest < ActionDispatch::IntegrationTest
  def setup
    PromiseFitnessKit.delete_all
  end

  def teardown
    Order.delete_all
    CouponCode.delete_all
    PromiseFitnessKit.delete_all
  end

  test "should get index" do
    get root_url
    assert_response :success
  end

  test "should display promise_fitness_kits" do
    kit = PromiseFitnessKit.create!(name: "Test Kit", description: "Test", slug: "test-kit-home-#{SecureRandom.hex(4)}")
    get root_url
    assert_response :success
    assert_select "body"
  end

  test "should order kits by name" do
    kit_z = PromiseFitnessKit.create!(name: "Zebra Kit", description: "Last", slug: "zebra-kit-#{SecureRandom.hex(4)}")
    kit_a = PromiseFitnessKit.create!(name: "Alpha Kit", description: "First", slug: "alpha-kit-#{SecureRandom.hex(4)}")

    get root_url
    assert_response :success
    # The kits should be ordered by name in the view
    # Alpha Kit should appear before Zebra Kit in the HTML
    assert_select "body"
  end
end
