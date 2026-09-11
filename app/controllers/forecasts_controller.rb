class ForecastsController < ApplicationController
  def index
  end

  def create
    @address = params.permit(:address)[:address].to_s
    service = Forecasts::Fetch.call(address: @address)
    response.headers["Cache-Control"] = "no-store"

    if service.success?
      @location = service.location
      @forecast = service.forecast
      @cached = service.cached?
      render :index
    else
      @error = service.error_message
      render :index, status: :unprocessable_content
    end
  end
end
