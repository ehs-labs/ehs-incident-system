Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins ENV.fetch("CORS_ORIGINS", "http://localhost:5173").split(",")

    resource "/api/*",
             headers: :any,
             methods: [:get, :post, :put, :patch, :delete, :options, :head],
             expose: %w[Authorization Link X-Total-Count],
             # Required because the frontend axios client sets withCredentials:true
             # (it sends the refresh cookie alongside the Bearer JWT). With
             # credentials, CORS spec requires the server to acknowledge them or
             # the browser silently drops the response — axios then surfaces it
             # as a generic "Error 0 / Cannot reach the API" with no detail.
             credentials: true

    # ActiveStorage proxy/redirect endpoints — the browser embeds these as
    # <img src> on the incident detail page, which is a cross-origin request
    # (frontend at :5173, core-api at :3000). Without this rule the
    # AttachmentSerializer#url returns 200 to curl but the browser drops it.
    resource "/rails/active_storage/*",
             headers: :any,
             methods: [:get, :head, :options]
  end
end
