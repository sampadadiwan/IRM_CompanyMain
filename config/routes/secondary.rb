resources :offers do
  patch 'approve', on: :member
  patch 'accept_spa', on: :member
  patch 'allocate', on: :member
  get   'allocation_form', on: :member
  get 'search', on: :collection
  patch 'generate_esign_link', on: :member
end

resources :interests do
  patch 'accept_spa', on: :member
  patch 'short_list', on: :member
  patch 'finalize', on: :member
  patch 'allocate', on: :member
  get   'allocation_form', on: :member
  get 'matched_offers', on: :member
end

resources :secondary_sales do
  # patch 'make_visible', on: :member
  get 'search', on: :collection
  get 'download', on: :member
  patch 'allocate', on: :member
  patch 'generate_spa', on: :member
  patch 'send_notification', on: :member
  get 'spa_upload', on: :member
  patch 'lock_allocations', on: :member
  get 'offers', on: :member
  patch 'approve_offers', on: :member
  get 'interests', on: :member
  get 'finalize_offer_allocation', on: :member
  get 'finalize_interest_allocation', on: :member
  get 'payments', on: :member
  get 'report', on: :member
end
