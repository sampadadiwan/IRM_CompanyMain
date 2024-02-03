namespace :admin do
  namespace :paper_trail do
    resources :versions, except: :index
  end

  namespace :audited do
    resources :audits
  end

  resources :whatsapp_logs
  resources :notifications
  resources :investors
  resources :reports
  resources :quick_links
  resources :quick_link_steps
  resources :users
  resources :entities
  resources :documents
  resources :investments
  resources :access_rights
  resources :deals
  resources :deal_investors
  resources :deal_activities
  resources :holdings
  resources :offers
  resources :interests
  resources :folders
  resources :investor_accesses
  resources :secondary_sales
  resources :roles, except: :index
  resources :funding_rounds
  resources :option_pools
  resources :excercises
  resources :funds
  resources :fund_formulas
  resources :valuations
  resources :capital_calls
  resources :capital_commitments
  resources :capital_distributions
  resources :capital_remittances
  resources :capital_remittance_payments
  resources :capital_distribution_payments
  resources :approvals
  resources :approval_responses
  resources :e_signatures

  # namespace :audited do
  #   resources :audits
  # end

  root to: "investors#index"
end
