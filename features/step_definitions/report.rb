Given('I ransack filter the {string}') do |filter_for|
  visit("/reports")
  expect(page).to have_content("All Reports")
  select "Commitments", from: "url"
end

Given('I save the filtered data as a report {string}') do |string|
  find('a[data-bs-original-title="Save Report"] i.ti.ti-database').click
  fill_in('report_name', with: string)
  fill_in('report_category', with: "#{string} category")
  fill_in('report_tag_list', with: "#{string} tags")
  fill_in('report_description', with: "#{string} description")
  click_on('Save')
end

Then('I should be able to view the report details') do
  @report ||= Report.last
  visit("/reports/#{@report.id}")
  expect(page).to have_content(@report.name)
  expect(page).to have_content(@report.category)
  expect(page).to have_content(@report.tag_list)
  expect(page).to have_content(@report.description)
end

Given('I delete the report') do
  @report ||= Report.last
  visit("/reports/#{@report.id}")
  click_on('Delete')
  click_on('Proceed')
end

Then('The report should be deleted') do
  expect(page).to have_content("Report was successfully destroyed")
end

Given('{string} support agent is enabled for the entity') do |string|
  @entity.support_agents.set(string)
  @entity.save!
end

Given('I save the filtered data as a report {string} with Ai prompt and notification recipient {string}') do |report_name, recipient|
   find('a[data-bs-original-title="Save Report"] i.ti.ti-database').click
  fill_in('report_name', with: report_name)
  fill_in('report_category', with: "#{report_name} category")
  fill_in('report_tag_list', with: "#{report_name} tags")
  fill_in('report_description', with: "#{report_name} description")
  fill_in('report_ai_prompt', with: "Generate insights for #{report_name}")
  check('send-notification-toggle')
  fill_in('report_notification_recipients', with: recipient)
  click_on('Save')
  expect(page).to have_content("successfully")
end

Then('the report should have the expected data') do
  @report ||= Report.last
  visit("/reports/#{@report.id}")
  expect(page).to have_content(@report.name)
  expect(page).to have_content(@report.category)
  expect(page).to have_content(@report.tag_list)
  expect(page).to have_content(@report.description)
end

Given('I generate the insight for the report') do
  mock_chat = double('chat')
  allow(RubyLLM).to receive(:chat).and_return(mock_chat)

  mock_response = {
    "md_body" => "## Executive Summary\nThis is a mock report.\n\n### Key Drivers\nEverything is going well.",
    "charts" => [
      {
        "id" => "chart_1",
        "library" => "chartjs",
        "config" => {
          "type" => "bar",
          "data" => {
              "labels" => ["A", "B"],
              "datasets" => [
                  {
                      "data" => [10, 20]
                  }
              ]
          }
        }
      }
    ],
    "summary_md" => "**Key Insight**\n- Metric: 10/100 (10%)\nWhy it matters: It defines testing.",
    "notes" => "Automated test."
  }.to_json

  allow(mock_chat).to receive(:ask).and_return(mock_response)

  @report ||= Report.last
  @report_insight_count = @report.report_insights.count
  visit("/reports/#{@report.id}")
  click_on('AI Analyses')
  click_on('Generate Analysis')
  click_on('Proceed')
  expect(page).to have_content("Report Analysis generation enqueued")
end

Then('the report insight should be generated') do
  mock_chat = double('chat')
  allow(RubyLLM).to receive(:chat).and_return(mock_chat)

  mock_response = {
    "md_body" => "## Executive Summary\nThis is a mock report.\n\n### Key Drivers\nEverything is going well.",
    "charts" => [
      {
        "id" => "chart_1",
        "library" => "chartjs",
        "config" => {
          "type" => "bar",
          "data" => {
              "labels" => ["A", "B"],
              "datasets" => [
                  {
                      "data" => [10, 20]
                  }
              ]
          }
        }
      }
    ],
    "summary_md" => "**Key Insight**\n- Metric: 10/100 (10%)\nWhy it matters: It defines testing.",
    "notes" => "Automated test."
  }.to_json

  allow(mock_chat).to receive(:ask).and_return(mock_response)
  @report.reload
  expect(@report.report_insights.count).to eq(@report_insight_count + 1)
  @report_insight = @report.report_insights.order(created_at: :desc).first
  expect(@report_insight.status).to eq("success")
end

Then('the recipient should receive an email notification with the insight summary') do
  @report.fetch_recipient_emails.split(",").map(&:strip).each do |email|
    current_email = nil
    emails_sent_to(email).each do |email|
      puts "#{email.subject} #{email.to} #{email.cc} #{email.bcc}"
      current_email = email if email.subject.downcase.include?("key insights")
    end
    puts "No email found for #{email} with subject 'Key Insights'" if current_email.nil?
    expect(current_email.body).to include "Why it matters: It defines testing." # Checking for part of the summary
  end
end

Given('the user has {string} assigned') do |attrs|
  @user = User.first
  key_values(@user, attrs)
  @user.save!
  @user.reload
  puts @user.inspect
  @user.entity.reload
  puts "entity employees - all: " + @user.entity.employees.pluck(:id, :tag_list).to_s
  puts @user.entity.employees.with_any_tags(@user.tag_list).pluck(:id).to_s
  expect(@user.entity.employees.with_any_tags(@user.tag_list).pluck(:id)).to include(@user.id)
end

Given('I go to edit the report') do
  @report ||= Report.last
  visit(edit_report_path(@report))
end

Given('I edit the report {string}') do |string|
  @report ||= Report.last
  @temp_report = Report.new()
  key_values(@temp_report, string)
  fill_in('report_notification_recipients', with: @temp_report.notification_recipients) if @temp_report.notification_recipients.present?
end

Then('the user with tag {string} should receive an email notification with the insight summary') do |string|
  @entity.employees.with_tag(string).pluck(:email).each do |email|
    current_email = nil
    emails_sent_to(email).each do |email|
      puts "#{email.subject} #{email.to} #{email.cc} #{email.bcc}"
      current_email = email if email.subject.downcase.include?("key insights")
    end
    puts "No email found for #{email} with subject 'Key Insights'" if current_email.nil?
    expect(current_email.body).to include "Why it matters: It defines testing." # Checking for part of the summary
  end
end
