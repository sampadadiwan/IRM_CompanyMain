resources :offers do
  patch 'approve', on: :member
  patch 'accept_spa', on: :member
  # No `allocate` / `allocation_form` member routes: OffersController has neither action (removed with
  # their views in "Secondary allocations" #503) and nothing links to them (F5-1X —
  # features/security/security_review_2026_10_followups.feature). Allocations are made on AllocationsController.
  get 'search', on: :collection
  # No `generate_esign_link` member route: its action went with Aadhaar eSign ("Remove adhaar esign" #57)
  # and nothing links to it (F6-3 — features/security/security_review_2026_10_followups.feature).
  post 'bulk_actions', on: :collection
  patch 'generate_docs', on: :member
  put :restore_deleted, on: :member
  get :show_deleted, on: :collection
end

resources :interests do
  patch 'accept_spa', on: :member
  patch 'short_list', on: :member
  # No `finalize` member route (its action went in "New policy framework" #435) and no `allocation_form`
  # (its view and the _final_interest row it edited went in "Secondary allocations" #503, when the
  # per-interest allocation table became AllocationsController). `allocate` stays: its HTML / JSON
  # responses still set an interest's allocation quantity for the selling firm (F5-1H, F6-2, F6-3 —
  # features/security/security_review_2026_10_followups.feature).
  patch 'allocate', on: :member
  patch 'generate_docs', on: :member
  put :restore_deleted, on: :member
  get :show_deleted, on: :collection
end

resources :secondary_sales do
  # patch 'make_visible', on: :member
  get 'search', on: :collection
  get 'download', on: :member
  post 'allocate', on: :member
  get 'allocate', on: :member
  patch 'generate_spa', on: :member
  patch 'send_notification', on: :member
  get 'spa_upload', on: :member
  patch 'lock_allocations', on: :member
  get 'offers', on: :member
  patch 'approve_offers', on: :member
  patch 'short_list_interests', on: :member
  get 'interests', on: :member
  get 'payments', on: :member
  # No `report` member route: it rendered any secondary_sales template named in params[:report]
  # (e.g. the full-PII download / payments sheets) to anyone who could see the sale, and nothing has
  # linked to it since Oct 2025 (C4-1, C4-2 in features/security/secondaries_isolation.feature).
  put :restore_deleted, on: :member
  get :show_deleted, on: :collection
end

resources :allocations do
  patch 'generate_docs', on: :member
  patch 'verify', on: :member
  post 'bulk_actions', on: :collection
  put :restore_deleted, on: :member
  get :show_deleted, on: :collection
end
