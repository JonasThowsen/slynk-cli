;;;; depot.asd

(defsystem "depot"
  :description "Resolves the dependencies of a project against the package registry and writes its lock file."
  :version "0.7.0"
  :license "MIT"
  :depends-on ("alexandria")
  :pathname "src/"
  :serial t
  :components ((:file "package")
               (:file "conditions")
               (:file "versions")
               (:file "version-sets")
               (:file "constraints")
               (:file "registry")
               (:file "projects")
               (:file "resolver")
               (:file "locks")
               (:file "explain")
               (:file "depot"))
  :in-order-to ((test-op (test-op "depot/tests"))))

(defsystem "depot/tests"
  :description "Tests for depot."
  :depends-on ("depot" "fiveam")
  :pathname "tests/"
  :serial t
  :components ((:file "package")
               (:file "versions")
               (:file "constraints")
               (:file "registry")
               (:file "resolver")
               (:file "locks"))
  :perform (test-op (operation component)
             (declare (ignore operation component))
             (unless (uiop:symbol-call :fiveam :run! :depot)
               (error "depot's tests failed"))))
