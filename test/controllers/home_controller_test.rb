require "test_helper"

class HomeControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do
    get root_url
    assert_response :success
  end

  test "should assign promise_fitness_kits" do
    get root_url
    assert_not_nil assigns(:promise_fitness_kits)
  end

  test "should order kits by name" do
    kit_z = PromiseFitnessKit.create!(name: "Zebra Kit", description: "Last")
    kit_a = PromiseFitnessKit.create!(name: "Alpha Kit", description: "First")

    get root_url
    kits = assigns(:promise_fitness_kits)
    assert_equal kit_a.id, kits.first.id
    assert_equal kit_z.id, kits.last.id
  end
end
