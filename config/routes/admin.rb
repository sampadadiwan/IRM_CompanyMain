namespace :admin do
  namespace :paper_trail do
    resources :versions, except: :index
  end
  resources :investors
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
  resources :valuations
  resources :capital_calls
  resources :capital_commitments
  resources :capital_distributions
  resources :capital_remittances
  resources :capital_distribution_payments

  # namespace :audited do
  #   resources :audits
  # end

  root to: "investors#index"
end
