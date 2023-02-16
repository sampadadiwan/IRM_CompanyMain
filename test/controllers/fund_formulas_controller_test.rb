require "test_helper"

class FundFormulasControllerTest < ActionDispatch::IntegrationTest
  setup do
    @fund_formula = fund_formulas(:one)
  end

  test "should get index" do
    get fund_formulas_url
    assert_response :success
  end

  test "should get new" do
    get new_fund_formula_url
    assert_response :success
  end

  test "should create fund_formula" do
    assert_difference("FundFormula.count") do
      post fund_formulas_url, params: { fund_formula: { description: @fund_formula.description, formula: @fund_formula.formula, fund_id: @fund_formula.fund_id, name: @fund_formula.name } }
    end

    assert_redirected_to fund_formula_url(FundFormula.last)
  end

  test "should show fund_formula" do
    get fund_formula_url(@fund_formula)
    assert_response :success
  end

  test "should get edit" do
    get edit_fund_formula_url(@fund_formula)
    assert_response :success
  end

  test "should update fund_formula" do
    patch fund_formula_url(@fund_formula), params: { fund_formula: { description: @fund_formula.description, formula: @fund_formula.formula, fund_id: @fund_formula.fund_id, name: @fund_formula.name } }
    assert_redirected_to fund_formula_url(@fund_formula)
  end

  test "should destroy fund_formula" do
    assert_difference("FundFormula.count", -1) do
      delete fund_formula_url(@fund_formula)
    end

    assert_redirected_to fund_formulas_url
  end
end
