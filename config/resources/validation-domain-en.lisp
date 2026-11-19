(in-package :mu-cl-resources)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; VALIDATION ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Evaluation results of the shacl-data-validation-service.

(define-resource validation-report ()
  :class (s-prefix "sh:ValidationReport")
  :properties `((:conforms :boolean ,(s-prefix "sh:conforms"))
                (:created :datetime ,(s-prefix "dct:created")))
  :has-one `((session :via ,(s-prefix "ext:validatedResource")
                      :as "session"))
  :has-many `((validation-result :via ,(s-prefix "sh:result")
                                 :as "results"))
  :resource-base (s-url "http://data.lblod.info/id/validation-reports/")
  :features '(include-uri)
  :on-path "validation-reports")

(define-resource validation-result ()
  :class (s-prefix "sh:ValidationResult")
  :properties `((:focus-node :url ,(s-prefix "sh:focusNode"))
                (:value :url ,(s-prefix "sh:value"))
                (:result-path :url ,(s-prefix "sh:resultPath"))
                (:severity :url ,(s-prefix "sh:resultSeverity"))
                (:message :language-string-set ,(s-prefix "sh:resultMessage"))
                (:source-constraint-component :url ,(s-prefix "sh:sourceConstraintComponent")))
  :has-one `((validation-report :via ,(s-prefix "sh:result")
                                :inverse t
                                :as "report")
             (validation-shape :via ,(s-prefix "sh:sourceShape")
                               :as "source-shape"))
  :resource-base (s-url "http://data.lblod.info/id/validation-results/")
  :features '(include-uri)
  :on-path "validation-results")

(define-resource validation-shape ()
  :class (s-prefix "sh:PropertyShape")
  :properties `((:name :string ,(s-prefix "sh:name")))
  :has-many `((validation-result :via ,(s-prefix "sh:sourceShape")
                                 :inverse t
                                 :as "results"))
  :resource-base (s-url "http://data.lblod.info/shapes/")
  :features '(include-uri)
  :on-path "validation-shapes")
