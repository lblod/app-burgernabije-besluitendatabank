(in-package :mu-cl-resources)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; VALIDATION ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Evaluation results of the shacl-data-validation-service.

(define-resource report ()
  :class (s-prefix "sh:ValidationReport")
  :properties `((:conforms :boolean ,(s-prefix "sh:conforms"))
                (:created :datetime ,(s-prefix "dct:created")))
  :has-many `((validationresult :via ,(s-prefix "sh:result")
                                :as "validationresults"))
  :resource-base (s-url "http://data.lblod.info/id/reports/")
  :features '(include-uri)
  :on-path "reports")

(define-resource validationresult ()
  :class (s-prefix "sh:ValidationResult")
  :properties `((:focus-node :url ,(s-prefix "sh:focusNode"))
                (:focus-node-id :string ,(s-prefix "ext:targetIdOfFocusNode"))
                (:target-class-of-focus-node :url ,(s-prefix "ext:targetClassOfFocusNode"))
                (:value :url ,(s-prefix "sh:value"))
                (:result-path :url ,(s-prefix "sh:resultPath"))
                (:severity :url ,(s-prefix "sh:resultSeverity"))
                (:message :language-string-set ,(s-prefix "sh:resultMessage"))
                (:source-constraint-component :url ,(s-prefix "sh:sourceConstraintComponent")))
  :has-one `((report :via ,(s-prefix "sh:result")
                     :inverse t
                     :as "report")
             (validationshape :via ,(s-prefix "sh:sourceShape")
                              :as "source-shape"))
  :resource-base (s-url "http://data.lblod.info/id/validationresults/")
  :features '(include-uri)
  :on-path "validationresults")

(define-resource validationshape ()
  :class (s-prefix "sh:PropertyShape")
  :properties `((:name :string ,(s-prefix "sh:name")))
  :has-many `((validationresult :via ,(s-prefix "sh:sourceShape")
                                :inverse t
                                :as "validationresults"))
  :resource-base (s-url "http://data.lblod.info/shapes/")
  :features '(include-uri)
  :on-path "validationshapes")
