class ApplicationMailbox < ActionMailbox::Base
  routing(/task-\d+/i          => :tasks)
  # to: fund-1@caphive.com
  # to: capital_commitment-11@caphive.com
  routing(/[a-zA-Z]*-\d+/i     => :tasks)
end
