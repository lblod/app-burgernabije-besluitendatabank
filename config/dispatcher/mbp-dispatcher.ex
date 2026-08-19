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
  # cache
  ###############
  get "/articles/*path", @any do
    Proxy.forward conn, path, "http://cache/articles/"
  end

  get "/administrative-units/*path", @any do
    Proxy.forward conn, path, "http://cache/administrative-units/"
  end

  get "/administrative-unit-classification-codes/*path", @any do
    Proxy.forward conn, path, "http://cache/administrative-unit-classification-codes/"
  end

  get "/agenda-item-handlings/*path", @any do
    Proxy.forward conn, path, "http://cache/agenda-item-handlings/"
  end

  get "/agenda-items/*path", @any do
    Proxy.forward conn, path, "http://cache/agenda-items/"
  end

  get "/governing-bodies/*path", @any do
    Proxy.forward conn, path, "http://cache/governing-bodies/"
  end

  get "/governing-body-classification-codes/*path", @any do
    Proxy.forward conn, path, "http://cache/governing-body-classification-codes/"
  end

  get "/locations/*path", @any do
    Proxy.forward conn, path, "http://cache/locations/"
  end

  get "/places/*path", @any do
    Proxy.forward conn, path, "http://cache/places/"
  end

  get "/mandataries/*path", @any do
    Proxy.forward conn, path, "http://cache/mandataries/"
  end

  get "/memberships/*path", @any do
    Proxy.forward conn, path, "http://cache/memberships/"
  end

  get "/resolutions/*path", @any do
    Proxy.forward conn, path, "http://cache/resolutions/"
  end

  get "/sessions/*path", @any do
    Proxy.forward conn, path, "http://cache/sessions/"
  end

  get "/votes/*path", @any do
    Proxy.forward conn, path, "http://cache/votes/"
  end

  get "/concept-schemes/*path", @any do
    Proxy.forward conn, path, "http://cache/concept-schemes/"
  end

  get "/concepts/*path", @any do
    Proxy.forward conn, path, "http://cache/concepts/"
  end

  get "/addresses/*path", @any do
    Proxy.forward conn, path, "http://cache/addresses/"
  end

  get "/geometries/*path", @any do
    Proxy.forward conn, path, "http://cache/geometries/"
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

  # /send-notifications stays internal and is deliberately NOT exposed via the dispatcher.

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
