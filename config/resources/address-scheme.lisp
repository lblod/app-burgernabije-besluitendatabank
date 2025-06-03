(define-resource address ()
  :class (s-prefix "locn:Address")
  :has-one `((geometry :via ,(s-prefix "locn:geometry")
                       :as "geometries"))
  :resource-base (s-url "http://lblod.data.gift/addresses/")
  :features `(include-uri)
  :on-path "addresses"
)

(define-resource geometry ()
  :class (s-prefix "locn:Geometry")
  :properties `(
    (:coordinates :<http://www.openlinksw.com/schemas/virtrdf#Geometry> ,(s-prefix "geosparql:asWKT"))
    )
  :resource-base (s-url "http://lblod.data.gift/geometries/")
  :features `(include-uri)
  :on-path "geometries"
)