;;;;;;;;;;;;;;;;;;;
;;; delta messenger
(in-package :delta-messenger)

;;(add-delta-logger)
(add-delta-messenger "http://delta-notifier/")

;;;;;;;;;;;;;;;;;
;;; configuration
(in-package :client)
(setf *log-sparql-query-roundtrip* nil)
(setf *backend* "http://triplestore:8890/sparql")


(in-package :server)
(setf *log-incoming-requests-p* nil)

;;;;;;;;;;;;;;;;;
;;; access rights
(in-package :acl)

(defparameter *access-specifications* nil
  "All known ACCESS specifications.")

(defparameter *graphs* nil
  "All known GRAPH-SPECIFICATION instances.")

(defparameter *rights* nil
  "All known GRANT instances connecting ACCESS-SPECIFICATION to GRAPH.")

(define-graph public ("http://mu.semte.ch/graphs/public")
  (_ -> _))

(define-graph harvester0 ("http://mu.semte.ch/graphs/harvester-0")
  (_ -> _))

(define-graph harvester1 ("http://mu.semte.ch/graphs/harvester-1")
  (_ -> _))

(define-graph harvester2 ("http://mu.semte.ch/graphs/harvester-2")
  (_ -> _))

(define-graph harvester3 ("http://mu.semte.ch/graphs/harvester-3")
  (_ -> _))

(define-graph mandaten ("http://mu.semte.ch/graphs/mandaten")
  (_ -> _))

(define-graph organisations ("http://mu.semte.ch/graphs/organisations")
  (_ -> _))

(define-prefixes
  :sh "http://www.w3.org/ns/shacl#")

;; One graph per bestuur: evaluations/<uuid of the bestuurseenheid in the
;; organisations graph>. Harvested data can give a bestuur another mu:uuid.
(define-graph evaluations ("http://mu.semte.ch/graphs/evaluations/")
  ("sh:ValidationReport" -> _)
  ("sh:ValidationResult" -> _)
  ("sh:PropertyShape" -> _))



(supply-allowed-group "public")

;; TODO: the role values are placeholders until the ACM/IDM client registration.

;; Only the besturen that own a report (ext:ownedBy, as in LMB): a group for
;; every bestuur makes queries too large for Virtuoso. Computed at login, so ABB
;; sees the reports of newly evaluated besturen after logging in again.
(supply-allowed-group "abb"
  :parameters ("session_group")
  :query "PREFIX ext: <http://mu.semte.ch/vocabularies/ext/>
          PREFIX mu: <http://mu.semte.ch/vocabularies/core/>
          PREFIX sh: <http://www.w3.org/ns/shacl#>
          SELECT DISTINCT ?session_group WHERE {
            <SESSION_ID> ext:sessionRole ?session_role .
            FILTER(?session_role = \"LokaalBeslist-ABB\")
            ?report a sh:ValidationReport ;
              ext:ownedBy ?bestuurseenheid .
            GRAPH <http://mu.semte.ch/graphs/organisations> {
              ?bestuurseenheid mu:uuid ?session_group .
            }
          }")

(supply-allowed-group "bestuur"
  :parameters ("session_group")
  :query "PREFIX ext: <http://mu.semte.ch/vocabularies/ext/>
          PREFIX mu: <http://mu.semte.ch/vocabularies/core/>
          SELECT DISTINCT ?session_group WHERE {
            <SESSION_ID> ext:sessionGroup ?group ;
              ext:sessionRole ?session_role .
            FILTER(?session_role = \"LokaalBeslist-bestuur\")
            GRAPH <http://mu.semte.ch/graphs/organisations> {
              ?group mu:uuid ?session_group .
            }
          }")

;; TODO: how suppliers log in for real is still open; for now the user is a
;; foaf:member of the vendor (as in the mock login sample data).
(supply-allowed-group "supplier"
  :parameters ("session_group")
  :query "PREFIX ext: <http://mu.semte.ch/vocabularies/ext/>
          PREFIX mu: <http://mu.semte.ch/vocabularies/core/>
          PREFIX muAccount: <http://mu.semte.ch/vocabularies/account/>
          PREFIX session: <http://mu.semte.ch/vocabularies/session/>
          PREFIX foaf: <http://xmlns.com/foaf/0.1/>
          SELECT DISTINCT ?session_group WHERE {
            <SESSION_ID> session:account ?account ;
              ext:sessionRole ?session_role .
            FILTER(?session_role = \"LokaalBeslist-leverancier\")
            ?person foaf:account ?account ;
              foaf:member ?vendor .
            ?vendor a ext:Vendor ;
              muAccount:canActOnBehalfOf ?bestuurseenheid .
            GRAPH <http://mu.semte.ch/graphs/organisations> {
              ?bestuurseenheid mu:uuid ?session_group .
            }
          }")

(grant (read)
  :to-graph (public)
  :for-allowed-group "public")

(grant (read)
  :to-graph (harvester0)
  :for-allowed-group "public")

(grant (read)
  :to-graph (harvester1)
  :for-allowed-group "public")

(grant (read)
  :to-graph (harvester2)
  :for-allowed-group "public")

(grant (read)
  :to-graph (harvester3)
  :for-allowed-group "public")

(grant (read)
  :to-graph (mandaten)
  :for-allowed-group "public")

(grant (read)
  :to-graph (organisations)
  :for-allowed-group "public")

(grant (read)
  :to-graph (evaluations)
  :for-allowed-group "abb")

(grant (read)
  :to-graph (evaluations)
  :for-allowed-group "bestuur")

(grant (read)
  :to-graph (evaluations)
  :for-allowed-group "supplier")

;; increase the default read timeout. this allows waiting heavier queries
(setf dexador.util:*default-read-timeout* 300)

