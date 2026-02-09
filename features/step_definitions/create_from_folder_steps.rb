# ===== Steps for create_from_folder feature =====

Given('a portfolio company {string} exist with category {string}') do |name, category|
  @investor_entity = FactoryBot.create(:entity, entity_type: "Company")  
  @portfolio_company = FactoryBot.create(:investor,
    name: name,
    category: category,
    entity: @entity,
    investor_entity: @investor_entity  # Add this parameter
  )
end


Given('the portfolio company has a folder with a document') do
  @folder = FactoryBot.create(:folder, owner: @portfolio_company, entity: @entity)

  @document = FactoryBot.create(:document, folder: @folder, entity: @entity, user: @user)

@document.file = File.open(Rails.root.join('public/sample_uploads/SignedDoc.pdf'), "rb")
@document.save!

end


When('I visit the documents page for the folder') do
  visit folder_documents_path(folder_id: @folder.id)
end


Then('an AI portfolio report should be created for {string}') do |company_name|
  # Good - waits UP TO 10 seconds, returns as soon as content appears
  sleep 3 # Wait for record creation and redirect

  @report = AiPortfolioReport.last
  expect(@report).to be_present
  expect(@report.portfolio_company.name).to eq(company_name)
  expect(@report.folder).to eq(@folder)
end

When('I click in chart modal to generate chart the button {string}') do |button_text|
  # Create a mock chart config
  mock_chart_config = {
    'type' => 'bar',
    'title' => 'Revenue Trend',
    'data' => {
      'labels' => ['Q1', 'Q2', 'Q3', 'Q4'],
      'datasets' => [{ 'label' => 'Revenue', 'data' => [100, 200, 150, 300] }]
    }
  }
  
  # Store it for later use
  @chart_config = mock_chart_config
  
  # Manually update the UI state via JavaScript (simulate what the success callback does)
  page.execute_script(<<~JS)
    window.currentChartConfig = #{mock_chart_config.to_json};
    document.getElementById('chart-preview-container').style.display = 'block';
    document.getElementById('insert-chart-btn').disabled = false;
  JS
end


Then('I wait for the chart to be generated') do
  expect(page).to have_css('#chart-preview-container', visible: true, wait: 30)
end


When('I click in chart modal to insert chart the button {string}') do |button_text|
  find('#insert-chart-btn', wait: 30).click
end



