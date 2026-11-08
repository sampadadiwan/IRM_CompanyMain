# Steps for features/core/folder_page.feature - folders/show: header (path + actions), the
# "New documents start with" defaults card and the Documents tab. IDs FP1-FP4 are the scenario comments.

When('I open the folder page of the child folder') do
  visit(folder_path(@child_folder))
  expect(page).to have_css("#folder_header", wait: 15)
end

# FP1
Then('the folder header should show {string} under the firm name and {string} as links') do |name, parent|
  within("#folder_header") do
    expect(page).to have_css("h5", text: name)
    within("#folder_path") do
      # The firm's "/" folder shows the firm's name
      expect(page).to have_link(@user.entity.name, href: folder_path(@child_folder.root))
      expect(page).to have_link(parent, href: folder_path(@folder))
    end
  end
  expect(page).to have_no_content("Viewing Folder")
end

Then('the folder actions should offer {string}') do |labels|
  within("#folder_actions") do
    labels.split(",").map(&:strip).each { |label| expect(page).to have_css("a, button", text: label) }
  end
end

# FP2
Given("the child folder's defaults are {string}") do |args|
  key_values(@child_folder, args)
  @child_folder.save!
end

Then('the {string} card should show {string} as {string} and {string} as {string}') do |title, first, first_value, second, second_value|
  within("#folder_defaults_card") do
    expect(page).to have_content(title)
    expect(find("li", text: first, match: :first)).to have_css(".badge", text: first_value)
    expect(find("li", text: second, match: :first)).to have_css(".badge", text: second_value)
  end
end

# FP3
Then("the folder's Documents tab should list {string}") do |name|
  within("#folders-tab") { expect(page).to have_css("tr[id^='document_'] a", text: name, wait: 15) }
end

Then("the folder's Documents tab should not repeat the folder path") do
  within("#folders-tab") do
    expect(page).to have_css("#docs_folder_explainer")
    expect(page).to have_no_css("#docs_folder_path")
  end
end

# FP4
Given('the child folder is private') do
  @child_folder.update!(private: true)
end

Then('the folder header should show the badge {string}') do |label|
  within("#folder_header") { expect(page).to have_css(".badge", text: label) }
end
