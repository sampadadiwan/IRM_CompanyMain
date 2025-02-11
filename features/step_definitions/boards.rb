When("I have Boards Permissions") do
  @user.permissions.set(:enable_kanban)
	@user.save!
	@entity.permissions.set(:enable_kanban)
	@entity.save!
end

When("I am at the Boards Page") do
	visit("/boards")
	entity_setting = @entity.entity_setting
  entity_setting.kanban_steps = {
                                	"KanbanBoard"=>["Todo", "In Progres", "Done", "Validated"]
                              	}
  entity_setting.save!
end

When('I create a new board {string}') do |arg1|
  click_on("New Board")
	#sleep(1)
	fill_in("kanban_board_name", with: "Board")
	click_on("Save")
	sleep(1)
	expect(page).to have_content("Board")
	kanban_board = KanbanBoard.first
	kanban_columns = kanban_board.kanban_columns.pluck(:name)
  #sleep(1)
  kanban_columns.each {|column| expect(page.text).to(include(column)) }
end

When('I add an item to the board') do
	first('button', text: "Add Item").click()
  # sleep(0.25)
	fill_in "kanban_card[title]", with: "Test Card"
	fill_in "kanban_card[notes]", with: "Test Note"
	fill_in "kanban_card[info_field]", with: "Test Card"
	click_button('Save')
	sleep(0.5)
	all('.connect-sorting').first.find('#dropdownMenuLink-1').click()
	sleep(0.1)
	click_on('Archive All')
	sleep(1)
	expect(KanbanBoard.last.kanban_cards.only_deleted.count).to(eq(1))
	expect(KanbanBoard.last.kanban_columns.only_deleted.count).to(eq(1))
	all('#dropdownMenuLink-1').first.click()
	click_on('Archived Columns')
	sleep(0.25)
	click_button('Restore')
	sleep(0.5)
	expect(KanbanBoard.last.kanban_cards.only_deleted.count).to(eq(0))
	expect(KanbanBoard.last.kanban_columns.only_deleted.count).to(eq(0))
end

When('I move card to the top position') do
	kanban_card = KanbanCard.last
	expect(kanban_card.sequence).to(eq(2))
	all(".kanban-card").last.find(".move-to-up-column").click
	sleep(2)
	expect(kanban_card.reload.sequence).to(eq(1))
end
