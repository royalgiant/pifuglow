require 'sidekiq/web'

Rails.application.routes.draw do
  get 'skincare_analyses/new'
  get 'skincare_analyses/create'
  
  devise_for :users, controllers: { sessions: 'users/sessions', passwords: 'users/passwords', registrations: 'users/registrations', omniauth_callbacks: 'users/omniauth_callbacks', confirmations: 'users/confirmations' }
  get 'auth/failure', to: 'users/omniauth_callbacks#failure'
  
  devise_scope :user do
    # authentication logic routes
    get "signup", to: "devise/registrations#new"
    post "signup", to: "devise/registrations#create"
    get "login", to: "devise/sessions#new"
    post "login", to: "devise/sessions#create"
    delete "logout", to: "devise/sessions#destroy"
    post "logout", to: "devise/sessions#destroy"
    get "logout", to: "devise/sessions#destroy"
  end

  resources :skincare_analyses, only: [:new, :create]
  root to: "skincare_analyses#new"

  scope controller: :static do
    get :terms
    get :privacy
  end

  namespace :api do
    namespace :v1 do
    end
  end

  # For sidekiq dashboard
  sidekiq_username = Rails.application.credentials.dig(Rails.env.to_sym, :sidekiqweb, :username)
  sidekiq_password = Rails.application.credentials.dig(Rails.env.to_sym, :sidekiqweb, :password)

  if sidekiq_username.nil? || sidekiq_password.nil?
    Rails.logger.error "Sidekiq web credentials are not set!"
  else
    Sidekiq::Web.use(Rack::Auth::Basic) do |username, password|
      ActiveSupport::SecurityUtils.secure_compare(::Digest::SHA256.hexdigest(username), ::Digest::SHA256.hexdigest(sidekiq_username)) &
      ActiveSupport::SecurityUtils.secure_compare(::Digest::SHA256.hexdigest(password), ::Digest::SHA256.hexdigest(sidekiq_password))
    end
  end

  mount Sidekiq::Web => '/sidekiq'
  get "up" => "rails/health#show", as: :rails_health_check
end
