(defsystem "logsum"
  :description "Monthly reports from the web shop's access logs: visitors, sessions, latency, errors, routes."
  :version "1.3.0"
  :author "Web shop operations"
  :license "MIT"
  :serial t
  :components ((:module "src"
                :serial t
                :components ((:file "package")
                             (:file "time")
                             (:file "random")
                             (:file "requests")
                             (:file "stats")
                             (:file "sessions")
                             (:file "report")
                             (:file "sample"))))
  :in-order-to ((test-op (test-op "logsum/tests"))))

(defsystem "logsum/tests"
  :description "Tests for logsum."
  :depends-on ("logsum" "fiveam")
  :components ((:module "tests"
                :components ((:file "tests"))))
  :perform (test-op (o c)
             (unless (uiop:symbol-call :fiveam :run! :logsum)
               (error "logsum's tests failed"))))
