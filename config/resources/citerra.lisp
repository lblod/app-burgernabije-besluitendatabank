(define-resource public-service ()
  :class (s-prefix "cpsv:PublicService")
  :properties `(
    (:label :string ,(s-prefix "skos:prefLabel"))
    (:value :string ,(s-prefix "prov:value"))
    (:extractedDecisionContent :uri ,(s-prefix "lblodBesluit:extractedDecisionContent"))
    (:outputType :uri ,(s-prefix "mobiliteit:heeftOutputtype"))
    (:uuid :string ,(s-prefix "mu:uuid"))
    (:publication-link :uri , (s-prefix "prov:wasDerivedFrom"))
  )
  :has-many `((requirement :via ,(s-prefix "belgifPublicService:hasRequirement")
                           :as "requirements"))
  :resource-base (s-url "http://data.lblod.info/id/public-services/")
  :features '(include-uri)
  :on-path "public-services")

(define-resource voorwaardecollectie ()
  :class (s-prefix "mobiliteit:Voorwaardecollectie")
  :properties `(
    (:operation :string ,(s-prefix "mobiliteit:operatie"))
    (:uuid :string ,(s-prefix "mu:uuid"))
  )
  :has-many `(
    (requirement :via ,(s-prefix "belgifPublicService:hasRequirement")
                 :as "requirements")
  )
  :resource-base (s-url "http://data.vlaanderen.be/id/voorwaardecollecties/")
  :features `(include-uri)
  :on-path "voorwaardecollecties"
)

(define-resource requirement ()
  :class (s-prefix "m8g:Requirement")
  :properties `(
    (:type :uri ,(s-prefix "dct:type"))
    (:expectedValue :string ,(s-prefix "ext:expectedValue"))
    (:uuid :string ,(s-prefix "mu:uuid"))
  )
  :has-many `(
    (evidenceTypeList :via ,(s-prefix "m8g:hasEvidenceTypeList")
                      :as "evidence-type-lists")
  )
  :resource-base (s-url "http://data.vlaanderen.be/id/requirements/")
  :features `(include-uri)
  :on-path "requirements"
)


(define-resource evidence-type-list ()
  :class (s-prefix "m8g:EvidenceTypeList")
  :properties `(
    (:uuid :string ,(s-prefix "mu:uuid"))
  )
  :has-many `(
    (evidenceType :via ,(s-prefix "m8g:specifiesEvidenceType")
                  :as "evidence-types")
  )
  :resource-base (s-url "http://data.vlaanderen.be/id/evidence-type-lists/")
  :features `(include-uri)
  :on-path "evidence-type-lists"
)

(define-resource evidence-type ()
  :class (s-prefix "m8g:EvidenceType")
  :properties `(
    (:classification :uri ,(s-prefix "m8g:evidenceTypeClassification"))
    (:uuid :string ,(s-prefix "mu:uuid"))
  )
  :resource-base (s-url "http://data.vlaanderen.be/id/evidence-types/")
  :features `(include-uri)
  :on-path "evidence-types"
)


(define-resource zone ()
  :class (s-prefix "locn:Location")
  :properties `((:label :string ,(s-prefix "rdfs:label"))
                (:publication-link :uri , (s-prefix "prov:wasDerivedFrom")))

  :has-one `((geo-point :via ,(s-prefix "locn:geometry")
                       :as "geo-point")
            (public-service :via ,(s-prefix "prov:wasDerivedFrom")
                                    :as "has-public-service")
            )
  :resource-base (s-url "http://data.lblod.info/id/zones/")
  :features '(include-uri)
  :on-path "zones")


(define-resource geo-point ()
  :class (s-prefix "locn:Geometry")
  :properties `(
    (:asWKT :geo ,(s-prefix "geosparql:asWKT"))
    (:coordinates :string ,(s-prefix "geosparql:asWKT"))
    )
  :resource-base (s-url "http://lblod.data.gift/id/geometrie/")
  :features `(include-uri)
  :on-path "geo-points"
)


(define-resource uittreksel ()
  :class (s-prefix "foaf:Document")
  :properties `(
    (:alternate-link :string-set ,(s-prefix "prov:wasDerivedFrom"))
    (:publication-date :datetime ,(s-prefix "eli:date_publication"))
    (:created-on :datetime ,(s-prefix "ext:createdOnTimestamp"))
  )
  :resource-base (s-url "http://lblod.data.gift/id/uittreksels/")
  :features `(include-uri)
  :on-path "uittreksels"
)



