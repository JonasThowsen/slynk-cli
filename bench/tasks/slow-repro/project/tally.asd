(defsystem "tally"
  :description "Sales figures for a chain of shops: import, daily revenue and period reports."
  :version "0.4.0"
  :author "Retail analytics"
  :license "MIT"
  :depends-on ("alexandria")
  :serial t
  :components ((:module "src"
                :serial t
                :components ((:file "package")
                             (:file "dates")
                             (:file "random")
                             (:file "sales")
                             (:file "database")
                             (:file "queries")
                             (:file "sample"))))
  :in-order-to ((test-op (test-op "tally/tests"))))

(defsystem "tally/tests"
  :description "Tests for tally."
  :depends-on ("tally" "fiveam")
  :components ((:module "test"
                :components ((:file "tests"))))
  :perform (test-op (o c)
             (unless (uiop:symbol-call :fiveam :run! :tally)
               (error "tally's tests failed"))))
