class HelpSlideOut < ViewComponent::Base
  def initialize(class_name:, current_user:, action: "show", id: nil, css_class: "")
    super
    @class_name = class_name
    @action = action
    @id = id
    @current_user = current_user
    # Any additional css classes to be attached to the card
    @css_class = css_class
  end

  HelpItem = Struct.new(:title, :description, :link)
  def help_text
    # Define a hash or use I18n to store static help texts keyed by page identifiers
    {
      # "Fund-show-employee" => [HelpItem.new('Fund Show Help', 'Fund show page help text...', 'https://example.com')],
      # "Fund-index-employee" => [HelpItem.new('Fund Index Help', 'Fund index page help text...', 'https://example.com')]
      # Add more pages as needed
    }["#{@class_name}-#{@action}-#{@current_user.curr_role}"] || [HelpItem.new('Contact Support', "Please contact support at support@caphive.com", '#')]
  end
end
