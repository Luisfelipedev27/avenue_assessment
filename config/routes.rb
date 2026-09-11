Rails.application.routes.draw do
  root "forecasts#index"
  resource :forecast, only: :create

  get "up" => "rails/health#show", as: :rails_health_check
end
