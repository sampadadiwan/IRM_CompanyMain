# Fund compliance monitoring — openspec/changes/fund-compliance-monitoring/lld.md › Controllers
scope :compliance do
  get "/", to: "compliance_home#index", as: :compliance_home
  # ⑩ Phase 5 newcomer guidance: the Getting started frame and the super-admin customer setup list
  get "getting_started", to: "compliance_home#getting_started", as: :compliance_getting_started
  get "onboarding", to: "compliance_onboarding#index", as: :compliance_onboarding
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
    # The fund page's lazy Compliance tab
    collection { get :fund_tab }
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
    member do
      get :mark_done
      patch :complete
    end
  end
  resources :document_signoffs, only: %i[new create]
  # Phase 3: facts read from documents — confirm, correct, enter by hand, read now (H40–H45, X48)
  resources :document_readings, path: "facts", controller: "document_facts", only: %i[index show new] do
    member { patch :confirm }
    collection do
      post :manual
      post :read_now
    end
  end
  resources :compliance_exports, path: "exports", only: %i[create]
end
