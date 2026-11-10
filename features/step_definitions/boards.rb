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
	# Was sleep(1). "Board" alone is already on the page ("New Board"), so wait for the saved board
	# itself; a board that never saves failed on KanbanBoard.first being nil before, too
	eventually { expect(KanbanBoard.first).to be_present }
	expect(page).to have_content("Board")
	kanban_board = KanbanBoard.first
	kanban_columns = kanban_board.kanban_columns.pluck(:name)
  #sleep(1)
  # have_content waits for the board's columns to render (page.text was a one-off read after the sleep)
  kanban_columns.each { |column| expect(page).to have_content(column) }
end

When('I add an item to the board') do
  first('#add_new_card').click
  # sleep(0.25)
	fill_in "kanban_card[title]", with: "Test Card"
	fill_in "kanban_card[notes]", with: "Test Note"
	fill_in "kanban_card[info_field]", with: "Test Card"
	click_button('Save')
	# Was sleep(0.5): wait for the saved card to render on the board (input values are not page
	# text, so this cannot match the form itself). Capped at that same 0.5 s and not asserted.
	page.has_content?("Test Card", wait: 0.5)
	all('.connect-sorting').first.find('#dropdownMenuLink-1').click()
	# click_on waits for the menu item (was sleep 0.1)
	click_on('Archive All')
	# Was sleep(1): retry the DB checks until the archive request has committed
	eventually do
		expect(KanbanBoard.last.kanban_cards.only_deleted.count).to(eq(1))
		expect(KanbanBoard.last.kanban_columns.only_deleted.count).to(eq(1))
	end
	all('#dropdownMenuLink-1').first.click()
	click_on('Archived Columns')
	# click_button waits for the Restore button (was sleep 0.25)
	click_button('Restore')
	# Was sleep(0.5): retry the DB checks until the restore request has committed
	eventually do
		expect(KanbanBoard.last.kanban_cards.only_deleted.count).to(eq(0))
		expect(KanbanBoard.last.kanban_columns.only_deleted.count).to(eq(0))
	end
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
  # KEEP: the check below asserts the sequence did NOT change, so it needs the move request to have
  # run; there is no page signal for "the move was refused" to wait on instead
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
	expect(page).to have_content("Card is successfully created", wait: 5)
end
