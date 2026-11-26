(in-package :mu-cl-resources)

;; Only the mock users of the dev sample data are readable (public graph).

(define-resource user ()
  :class (s-prefix "foaf:Person")
  :properties `((:first-name :string ,(s-prefix "foaf:firstName"))
                (:family-name :string ,(s-prefix "foaf:familyName")))
  :has-many `((account :via ,(s-prefix "foaf:account")
                       :as "accounts")
              (administrative-unit :via ,(s-prefix "foaf:member")
                                   :as "groups"))
  :resource-base (s-url "http://data.lblod.info/id/persoon/")
  :on-path "users")

(define-resource account ()
  :class (s-prefix "foaf:OnlineAccount")
  :properties `((:provider :url ,(s-prefix "foaf:accountServiceHomepage"))
                (:role :string ,(s-prefix "ext:sessionRole"))
                (:mock-login-group-id :string ,(s-prefix "ext:mockLoginGroupId")))
  :has-one `((user :via ,(s-prefix "foaf:account")
                   :inverse t
                   :as "user"))
  :resource-base (s-url "http://data.lblod.info/id/account/")
  :on-path "accounts")
