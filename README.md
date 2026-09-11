# Avenue

Avenue takes a US street address and returns the current temperature and today's high and low. Forecasts are cached by ZIP code for 30 minutes, and the page indicates whether the result came from cache.

## Running the application

Requires Ruby 3.3.8, Bundler, and PostgreSQL. No API keys are needed.

```sh
bundle install
bin/rails db:prepare
bin/dev
```

Open [localhost:3000](http://localhost:3000) and search for an address such as:

```text
233 S Wacker Drive, Chicago, IL 60606
```

Submit the same address again to see the **From cache** indicator.

`bin/dev` runs Rails and the Tailwind watcher, installing Foreman if necessary. To run without the watcher:

```sh
bin/rails tailwindcss:build
bin/rails server
```

PostgreSQL uses a local connection with your OS username by default. Adjust `config/database.yml` or set `DATABASE_URL` if your setup differs. The default databases are `avenue_development` and `avenue_test`.

## Approach

The application follows a short request flow: resolve the address, check the forecast cache, and call the weather provider only on a cache miss.

`ForecastsController` handles the form and response rendering. `Addresses::Resolve` validates the address and obtains its ZIP code and coordinates. `Forecasts::Fetch` retrieves the weather and exposes the result through `success?`, `forecast`, and `cached?`. Both services return an `error_message` when the request cannot be completed.

Provider requests live in separate clients under `app/clients`. A shared HTTP client handles timeouts, unsuccessful HTTP responses, and malformed JSON. This keeps network handling out of the controller and allows the tests to replace external responses.

## Technical choices

- **Rails views and Tailwind CSS:** the application needs one form and one result page. ERB keeps that flow in Rails, while Tailwind provides a layout without a separate frontend application...
- **Nominatim and Open-Meteo:** Nominatim supplies address details and coordinates; Open-Meteo supplies current and daily weather. Both can be used without API keys for this demonstration, making local setup straightforward.
- **`Net::HTTP`:** Ruby's standard library covers the two GET integrations, so an additional HTTP library was unnecessary. Requests have timeouts and do not retry automatically.
- **`Rails.cache`:** the built-in cache API supports expiration and avoids storing temporary forecasts as application records. Development uses the memory store; production uses the generated PostgreSQL-backed Solid Cache configuration.
- **RSpec and RuboCop:** specs cover service behavior and HTTP requests through the application. RuboCop uses the Rails Omakase rules to keep formatting consistent.

Rails 8.1.3.1 is used to keep the application on a supported release. The existing Rails 8.0 configuration defaults are retained.

## Caching

The forecast key includes the country, normalized ZIP code, and temperature unit. ZIP+4 values are reduced to five digits, preserving leading zeros. Different addresses within the same ZIP share a forecast, but the page still displays the address resolved for the current search.

Entries expire 30 minutes after they are written. Reading an entry does not extend its lifetime. Failed requests and invalid responses are not stored.

Successful address lookups are cached separately for 30 minutes using a hash of the normalized input. This avoids repeating geocoding requests when the same address is submitted again. The visible cache indicator refers only to the forecast.

The development cache is cleared when the server restarts. HTML responses use `Cache-Control: no-store`, so the forecast indicator is determined by the application rather than a cached page in the browser.

## Assumptions and limitations

the application supports US street addresses and displays Fahrenheit. Daily highs and lows follow the location's timezone; the weather update timestamp is labeled in UTC.

Address resolution was the main source of ambiguity. A query such as `350` can match a road without identifying the intended address. Numeric-only input is therefore rejected before a lookup. The application checks up to two matches, asks for a more specific address when they have different ZIP codes, and requires a house number, street, and ZIP in the selected result. This improves the result without attempting to implement postal address validation. The resolved address is shown so the user can check it.

The public Nominatim service allows at most one request per second across an application. A mutex protects an in-memory timestamp, and requests made too quickly receive a retry message. **The application must run as one process on one instance.** Puma is configured in single mode.... this limiter does not coordinate separate servers or console processes. Successful address caching reduces how often the limit is reached.

Searches are explicitly submitted rather than triggered on every keystroke. The client identifies the application, and the page includes provider attribution. The Nominatim endpoint can be changed through the optional `NOMINATIM_URL` variable. See the [Nominatim usage policy](https://operations.osmfoundation.org/policies/nominatim/) for its restrictions, including the prohibition on submitting confidential or personal information. Open-Meteo's free endpoint is intended for [non-commercial use](https://open-meteo.com/en/docs).

## Verification

```sh
bin/rails tailwindcss:build
bundle exec rspec
bin/rubocop
```

Tests simulate provider responses and do not depend on public API availability. Cache specs use isolated memory stores and advance time to verify expiration. Request specs cover successful searches, the cache indicator, invalid addresses, escaped input, and provider failures.

The setup was also checked in a clean local checkout with the pending changes applied, without local credentials or prebuilt assets, using newly created databases. Manual browser checks covered a real search, a repeated cached search, validation errors, and the mobile layout.

## Considerations

I encountered no difficulties in developing this, as it is part of my daily work and has been for years. The coding patterns used here are part of my routine, I always strive to follow architectural best practices, ensuring that each structure maintains a separation of responsibilities.
