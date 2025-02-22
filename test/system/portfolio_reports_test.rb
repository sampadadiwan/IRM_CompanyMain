require "application_system_test_case"

class PortfolioReportsTest < ApplicationSystemTestCase
  setup do
    @portfolio_report = portfolio_reports(:one)
  end

  test "visiting the index" do
    visit portfolio_reports_url
    assert_selector "h1", text: "Portfolio reports"
  end

  test "should create portfolio report" do
    visit portfolio_reports_url
    click_on "New portfolio report"

    fill_in "Entity", with: @portfolio_report.entity_id
    fill_in "Extraction questions", with: @portfolio_report.extraction_questions
    check "Include kpi" if @portfolio_report.include_kpi
    check "Include portfolio investments" if @portfolio_report.include_portfolio_investments
    fill_in "Name", with: @portfolio_report.name
    fill_in "Tags", with: @portfolio_report.tags
    click_on "Create Portfolio report"

    assert_text "Portfolio report was successfully created"
    click_on "Back"
  end

  test "should update Portfolio report" do
    visit portfolio_report_url(@portfolio_report)
    click_on "Edit this portfolio report", match: :first

    fill_in "Entity", with: @portfolio_report.entity_id
    fill_in "Extraction questions", with: @portfolio_report.extraction_questions
    check "Include kpi" if @portfolio_report.include_kpi
    check "Include portfolio investments" if @portfolio_report.include_portfolio_investments
    fill_in "Name", with: @portfolio_report.name
    fill_in "Tags", with: @portfolio_report.tags
    click_on "Update Portfolio report"

    assert_text "Portfolio report was successfully updated"
    click_on "Back"
  end

  test "should destroy Portfolio report" do
    visit portfolio_report_url(@portfolio_report)
    click_on "Destroy this portfolio report", match: :first

    assert_text "Portfolio report was successfully destroyed"
  end
end
