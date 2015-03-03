Epm::Application.routes.draw do

  root 'events#index'

  devise_for :users
  resources :users, only: [:index, :show, :edit, :update] do
    resources :roles, only: [:create, :destroy], shallow: true
    collection do
      get 'map'
      get 'import', to: 'users#ask_to_import'
      patch 'import'
    end
    patch 'deactivate', on: :member
  end
  get 'me', to: 'users#me'

  resources :events do
    get 'calendar', on: :collection
    member do
      get 'who'
      get 'cancel', to: 'events#ask_to_cancel'
      patch 'cancel'
      patch 'approve'
      patch 'attend'
      patch 'unattend'
      patch 'invite'
      patch 'take_attendance'
    end
  end

  # for configurable_engine gem; it generates its own routes as well which are unused
  put 'settings', to: 'settings#update', as: 'settings'
  get 'settings', to: 'settings#show'

  get 'geocode', to: 'geocode#index'

end