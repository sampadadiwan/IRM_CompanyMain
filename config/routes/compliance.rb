# Fund compliance monitoring — openspec/changes/fund-compliance-monitoring/lld.md › Controllers
scope :compliance do
  get "/", to: "compliance_home#index", as: :compliance_home
  resources :compliance_packs, path: "packs", only: %i[index show new create] do
    member { patch :retire }
  end
  resources :compliance_pack_versions, path: "versions", only: %i[show update] do
    member do
      post :test_run
      patch :publish
    end
  end
  resources :compliance_check_drafts, path: "drafts", only: %i[create show update] do
    member do
      post :test_run
      post :save_check
    end
  end
  resources :fund_compliance_packs, path: "fund_packs", only: %i[index create show] do
    member do
      post :run_now
      get :preview
      post :rerun
    end
  end
  resource :compliance_entity_setup, path: "setup", only: %i[show update]
  resources :compliance_requests, path: "requests", only: %i[create] do
    member do
      patch :approve
      patch :reject
    end
  end
  resources :compliance_register_items, path: "register", only: %i[index show] do
    member { patch :assign }
  end
  resources :compliance_results, path: "results", only: %i[show destroy]
  resources :compliance_duties, path: "duties", only: %i[index] do
    member { patch :complete }
  end
  resources :document_signoffs, only: %i[create]
  resources :compliance_exports, path: "exports", only: %i[create]
end
