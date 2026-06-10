defmodule Dispatcher do
  use Matcher
  define_accept_types [
    json: ["application/json", "application/vnd.api+json"],
    html: ["text/html", "application/xhtml+html"],
    any: ["*/*"]
  ]

  @any %{}
  @json %{ accept: %{ json: true } }
  @html %{ accept: %{ html: true } }

  define_layers([:static, :api_services, :frontend, :not_found])

  ###############
  # RESOURCES
  ###############
  get "/articles/*path", @any do
    Proxy.forward conn, path, "http://resources/articles/"
  end

  get "/administrative-units/*path", @any do
    Proxy.forward conn, path, "http://resources/administrative-units/"
  end

  get "/administrative-unit-classification-codes/*path", @any do
    Proxy.forward conn, path, "http://resources/administrative-unit-classification-codes/"
  end

  get "/agenda-item-handlings/*path", @any do
    Proxy.forward conn, path, "http://resources/agenda-item-handlings/"
  end

  get "/agenda-items/*path", @any do
    Proxy.forward conn, path, "http://resources/agenda-items/"
  end

  get "/governing-bodies/*path", @any do
    Proxy.forward conn, path, "http://resources/governing-bodies/"
  end

  get "/governing-body-classification-codes/*path", @any do
    Proxy.forward conn, path, "http://resources/governing-body-classification-codes/"
  end

  get "/locations/*path", @any do
    Proxy.forward conn, path, "http://resources/locations/"
  end

  get "/places/*path", @any do
    Proxy.forward conn, path, "http://resources/places/"
  end

  get "/mandataries/*path", @any do
    Proxy.forward conn, path, "http://resources/mandataries/"
  end

  get "/memberships/*path", @any do
    Proxy.forward conn, path, "http://resources/memberships/"
  end

  get "/resolutions/*path", @any do
    Proxy.forward conn, path, "http://resources/resolutions/"
  end

  get "/sessions/*path", @any do
    Proxy.forward conn, path, "http://resources/sessions/"
  end

  get "/votes/*path", @any do
    Proxy.forward conn, path, "http://resources/votes/"
  end

  get "/concept-schemes/*path", @any do
    Proxy.forward conn, path, "http://resources/concept-schemes/"
  end

  get "/concepts/*path", @any do
    Proxy.forward conn, path, "http://resources/concepts/"
  end

  get "/addresses/*path", @any do
    Proxy.forward conn, path, "http://resources/addresses/"
  end

  get "/geometries/*path", @any do
    Proxy.forward conn, path, "http://resources/geometries/"
  end

  match "/sparql/*path" do
    Proxy.forward conn, path, "http://triplestore:8890/sparql/"
  end #remove this in production

  match "/adresses-register/*path" do
    forward conn, path, "http://adressenregister"
  end

  # match "/duplicate-uri/*path" do
  #   forward conn, path, "http://adressenregister"
  # end


  ###############################################################
  # SEARCH
  ###############################################################

  match "/search/*path", @json do
    Proxy.forward conn, path, "http://search/"
  end




  ###############
  # SSO
  ###############

  # Called server-to-server by the MBP backend to exchange an ACM token for a handover token.
  post "/auth/v1/token", @json do
    Proxy.forward conn, [], "http://mbp-sso/auth/v1/token"
  end

  # Called by the embed frontend to redeem the handover token and start a session.
  post "/auth/v1/exchange", @json do
    Proxy.forward conn, [], "http://mbp-sso/auth/v1/exchange"
  end

  # Called by the embed frontend on logout.
  delete "/auth/v1/session", @json do
    Proxy.forward conn, [], "http://mbp-sso/auth/v1/session"
  end

  ###############
  # MBP - PUSH NOTIFICATIONS (FILTERS)
  ###############

  # Manual test trigger — fires a simple notification to the signed-in user.
  # ( /send-notifications stays internal and is deliberately NOT exposed. )
  post "/test-notification", @json do
    Proxy.forward conn, [], "http://mbp-push-notifications/test-notification"
  end

  get "/saved-filters", @json do
    Proxy.forward conn, [], "http://mbp-push-notifications/saved-filters"
  end

  post "/saved-filters", @json do
    Proxy.forward conn, [], "http://mbp-push-notifications/saved-filters"
  end

  put "/saved-filters/*path", @json do
    Proxy.forward conn, path, "http://mbp-push-notifications/saved-filters/"
  end

  delete "/saved-filters/*path", @json do
    Proxy.forward conn, path, "http://mbp-push-notifications/saved-filters/"
  end

  ###############
  # FRONTEND
  ###############
  match "/assets/*path", @any do
    Proxy.forward conn, path, "http://mbp-frontend/assets/"
  end

  match "/@appuniversum/*path", @any do
    Proxy.forward conn, path, "http://mbp-frontend/@appuniversum/"
  end

  match "/*_path", @html do
    Proxy.forward conn, [], "http://mbp-frontend/index.html"
  end

  #################
  # NOT FOUND
  #################
  match "/*_", %{ last_call: true } do
    send_resp(conn, 404, "Route not found. See config/dispatcher/mbp-dispatcher.ex")
  end
end
