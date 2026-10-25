(defsystem "spool"
  :description "A job server for the back office: named queues with workers, priorities, retries, over a line protocol."
  :version "0.6.0"
  :author "Back office tools"
  :license "MIT"
  :depends-on ("sb-bsd-sockets")
  :serial t
  :components ((:module "src"
                :serial t
                :components ((:file "package")
                             (:file "tokens")
                             (:file "log")
                             (:file "jobs")
                             (:file "heap")
                             (:file "server")
                             (:file "protocol")
                             (:file "network")
                             (:file "client"))))
  :in-order-to ((test-op (test-op "spool/tests"))))

(defsystem "spool/tests"
  :description "Tests for spool."
  :depends-on ("spool" "fiveam")
  :serial t
  :components ((:module "tests"
                :serial t
                :components ((:file "package")
                             (:file "tokens")
                             (:file "heap")
                             (:file "server")
                             (:file "protocol"))))
  :perform (test-op (o c)
             (unless (uiop:symbol-call :fiveam :run! :spool)
               (error "spool's tests failed"))))
