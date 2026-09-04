# Steps for features/fund/portfolio_investment_tasks.feature — tasks owned by a
# PortfolioInvestment (Task#owner is polymorphic, same as Investor and
# CapitalCommitment).
#
# Relies on shared steps for login, the portfolio company / instrument / fund
# fixtures (portfolio.rb) and the board column assertions (task_board_steps.rb).

# "there are {string} portfolio investments {string}" creates them without
# holding on to one, so pin the one this feature works with.
Given('I have a portfolio investment') do
  @portfolio_investment = PortfolioInvestment.order(:id).last
  expect(@portfolio_investment).not_to be_nil, 'no portfolio investment was created'
end

Given('the portfolio investment has the following tasks:') do |table|
  table.hashes.each do |row|
    task = Task.new(entity: @user.entity, user: @user, details: row['details'],
                    owner: @portfolio_investment)
    task.status = row['status'] if row['status'].present?
    # Creation notifications are noise here (Cucumber runs ActiveJob inline)
    task.send_notification_flag = false
    task.save!
  end
end

# A task on the same entity but no owner — proves the tab is scoped to the
# investment rather than showing everything the user can see.
Given('there is an unrelated task {string}') do |details|
  task = Task.new(entity: @user.entity, user: @user, details: details, owner: @user.entity)
  task.send_notification_flag = false
  task.save!
end

When('I go to the portfolio investment page') do
  visit portfolio_investment_path(@portfolio_investment)
end

Then('the portfolio investment page should offer a Tasks tab') do
  expect(page).to have_link('Tasks', href: '#tasks-tab')
  # The pane loads lazily, so assert the frame it will fetch is scoped to this
  # investment rather than waiting for the tab to be opened
  frame = find('#tasks-tab turbo-frame#task_list', visible: :all)
  expect(frame[:src]).to include("owner_type=PortfolioInvestment")
  expect(frame[:src]).to include("owner_id=#{@portfolio_investment.id}")
end

When('I open the portfolio investment tasks tab') do
  visit tasks_path(owner_id: @portfolio_investment.id, owner_type: 'PortfolioInvestment')
end

When('I open the new task form from the portfolio investment tasks tab') do
  click_on('New Task', match: :first)
end

Then('the task owner fields should be hidden but carry the portfolio investment') do
  # The owner-type select only offers User/Investor, so showing it here would let
  # the browser fall back to User and detach the task on save
  expect(page).not_to have_select('task_owner_type')
  expect(page).not_to have_select('task_owner_id')
  expect(page).to have_field('task_owner_type', type: 'hidden', with: 'PortfolioInvestment', visible: :all)
  expect(page).to have_field('task_owner_id', type: 'hidden',
                             with: @portfolio_investment.id.to_s, visible: :all)
end

When('I save the task with details {string}') do |details|
  find("trix-editor[input='task_details_trix_input_task']").set(details)
  click_on('Save')
  sleep(2)
end

Then('the task {string} should be owned by the portfolio investment') do |details|
  task = Task.all.find { |t| t.details.to_plain_text.include?(details) }
  expect(task).not_to be_nil, "no task with details #{details.inspect}"
  expect(task.reload.owner).to eq(@portfolio_investment)
end

Then('the tasks tab should offer a board link for the portfolio investment') do
  board_link = find_link('Board')
  expect(board_link[:href]).to include('owner_type=PortfolioInvestment')
  expect(board_link[:href]).to include("owner_id=#{@portfolio_investment.id}")
end

When('I go to the tasks board page for the portfolio investment') do
  visit tasks_path(board: true, owner_id: @portfolio_investment.id,
                   owner_type: 'PortfolioInvestment')
end

Then('the board title should name the portfolio investment') do
  # A scoped board replaces the generic "Tasks Board" heading with the scope
  # link itself (the owner's bare #to_s, no type prefix), which is the way
  # back to the record it was opened from
  expect(page).to have_link(@portfolio_investment.to_s,
                            href: portfolio_investment_path(@portfolio_investment))
end

# The "For" column collapses a PI owner to its stakeholder (company) name —
# the full to_s (with instrument, buy/sell and date) must not leak into the cell
Then("the task's For column should link the company name to the portfolio investment") do
  expect(page).to have_link(@portfolio_investment.portfolio_company_name,
                            href: portfolio_investment_path(@portfolio_investment))
  expect(page).not_to have_content(@portfolio_investment.to_s)
end

When('the portfolio investment is destroyed') do
  @destroyed_portfolio_investment_id = @portfolio_investment.id
  @portfolio_investment.destroy!
end

Then('no tasks should remain for the portfolio investment') do
  expect(Task.where(owner_type: 'PortfolioInvestment',
                    owner_id: @destroyed_portfolio_investment_id)).to be_empty
end
