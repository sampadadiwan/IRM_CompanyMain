require "test_helper"

class PortfolioReportsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @portfolio_report = portfolio_reports(:one)
  end

  test "should get index" do
    get portfolio_reports_url
    assert_response :success
  end

  test "should get new" do
    get new_portfolio_report_url
    assert_response :success
  end

  test "should create portfolio_report" do
    assert_difference("PortfolioReport.count") do
      post portfolio_reports_url, params: { portfolio_report: { entity_id: @portfolio_report.entity_id, extraction_questions: @portfolio_report.extraction_questions, include_kpi: @portfolio_report.include_kpi, include_portfolio_investments: @portfolio_report.include_portfolio_investments, name: @portfolio_report.name, tags: @portfolio_report.tags } }
    end

    assert_redirected_to portfolio_report_url(PortfolioReport.last)
  end

  test "should show portfolio_report" do
    get portfolio_report_url(@portfolio_report)
    assert_response :success
  end

  test "should get edit" do
    get edit_portfolio_report_url(@portfolio_report)
    assert_response :success
  end

  test "should update portfolio_report" do
    patch portfolio_report_url(@portfolio_report), params: { portfolio_report: { entity_id: @portfolio_report.entity_id, extraction_questions: @portfolio_report.extraction_questions, include_kpi: @portfolio_report.include_kpi, include_portfolio_investments: @portfolio_report.include_portfolio_investments, name: @portfolio_report.name, tags: @portfolio_report.tags } }
    assert_redirected_to portfolio_report_url(@portfolio_report)
  end

  test "should destroy portfolio_report" do
    assert_difference("PortfolioReport.count", -1) do
      delete portfolio_report_url(@portfolio_report)
    end

    assert_redirected_to portfolio_reports_url
  end
end
