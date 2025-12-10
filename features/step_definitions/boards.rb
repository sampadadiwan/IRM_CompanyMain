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
  first('#add_new_card').click
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
  page.execute_script <<~JS
    document.addEventListener(
      'click',
      function(e) {
        if (e.target.closest('.move-to-up-column, .move-to-next-column')) {
          e.stopPropagation(); // prevent it reaching .kanban-card listener
        }
      },
      true // capture phase so this runs before your existing handler
    );
  JS
  kanban_card = KanbanCard.last
  expect(kanban_card.sequence).to(eq(2))
  all(".move-to-up-column").last.click
  sleep(2)
	# TODO: improve spec
	expect(kanban_card.reload.sequence).to(eq(2))
end

When('I create two new cards and save') do
  create_new_card("Card 1", "Note 1", "Info 1")
	create_new_card("Card 2", "Note 2", "Info 2")
end

def create_new_card(title, notes, info_field)
  first('#add_new_card').click
  expect(page).to have_content("Card : New", wait: 5)
	fill_in("kanban_card_title", with: title)
	fill_in("kanban_card_notes", with: notes)
	fill_in("kanban_card_info_field", with: info_field)
	click_on("Save")
end
