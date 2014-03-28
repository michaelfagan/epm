Epm::Application.routes.draw do

  root 'events#index'

  devise_for :users, controllers: { registrations: 'registrations' }
  resources :users, only: [:index, :show, :edit, :update] do
    resources :roles, only: [:create, :destroy], shallow: true
    patch 'deactivate', on: :member
  end

  resources :events, except: :destroy do
    get 'calendar', on: :collection
    member do
      get 'cancel', to: 'events#ask_to_cancel'
      patch 'cancel'
      patch 'approve'
      patch 'attend'
      patch 'unattend'
    end
  end

  # for configurable_engine gem; it generates its own routes as well which are unused
  put 'settings', to: 'settings#update', as: 'settings'
  get 'settings', to: 'settings#show'

  get 'geocode', to: 'geocode#index'

end