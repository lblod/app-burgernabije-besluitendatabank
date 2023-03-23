  defmodule Dispatcher do
    use Matcher
    define_accept_types [
      html: [ "text/html", "application/xhtml+html" ],
      json: [ "application/json", "application/vnd.api+json" ]
    ]

    @any %{}
    @json %{ accept: %{ json: true } }
    @html %{ accept: %{ html: true } }

    # In order to forward the 'themes' resource to the
    # resource service, use the following forward rule:
    #
    # match "/themes/*path", @json do
    #   Proxy.forward conn, path, "http://resource/themes/"
    # end
    #
    # Run `docker-compose restart dispatcher` after updating
    # this file.

    get "/api/decisions/*path", @json do
      Proxy.forward conn, path, "http://resources/decisions"
    end

    get "/api/agenda-items/*path", @json do
      Proxy.forward conn, path, "http://resources/agenda-items"
    end

    match "/api/uuid-generator/*path", @json do
      Proxy.forward conn, path, "http://uuid-generator/"
    end

    get "/*path", @json do
      Proxy.forward conn, path, "http://frontend/"
    end

    match "/*_", %{ last_call: true } do
      send_resp( conn, 404, "Route not found.  See config/dispatcher.ex" )
    end
  end