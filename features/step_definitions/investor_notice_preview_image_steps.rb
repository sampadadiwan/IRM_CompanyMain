# Step definitions for features/misc/investor_notice_preview_image.feature
#
# Regression for _preview.html.erb rendering <img src=""> (a broken-image
# icon) when a notice has no link and its GP entity has no logo.

Then('the notices carousel should not show a broken image') do
  within("#carouselExampleControls") do
    expect(page).to have_no_css("img.notice_image")
  end
end
