(in-package #:spool/tests)
(in-suite :spool)

;;; The server over the network, through the client.

(defmacro with-client ((connection server) &body body)
  `(spool-client:with-connection (,connection :port (spool:server-port ,server))
     ,@body))

(test client-session
  (with-server (server :queues '(("mail" :workers 2) ("reports" :workers 1)))
    (with-client (connection server)
      (is (equal '("mail" "reports") (spool-client:queues connection)))
      (let ((id (spool-client:submit connection "mail" "echo" '("dear" "Kari Nordmann"))))
        (is (integerp id))
        (is (equal '(:done "dear Kari Nordmann")
                   (multiple-value-list (spool-client:wait connection id :timeout 10))))
        (is (eq :done (spool-client:status connection id))))
      (let ((id (spool-client:submit connection "reports" "fail" '("no" "data") :attempts 1)))
        (is (equal '(:failed "no data")
                   (multiple-value-list (spool-client:wait connection id :timeout 10)))))
      (is (equal '(:waiting 0 :running 0 :done 1 :failed 0 :cancelled 0)
                 (spool-client:stats connection "mail"))))))

(test client-pause-and-cancel
  (with-server (server :queues '(("reports" :workers 1)))
    (with-client (connection server)
      (is (eq :paused (spool-client:pause connection "reports")))
      (let ((first (spool-client:submit connection "reports" "echo" '("first")))
            (urgent (spool-client:submit connection "reports" "echo" '("urgent") :priority 8))
            (dropped (spool-client:submit connection "reports" "echo" '("dropped"))))
        (is (eq :queued (spool-client:status connection first)))
        (is (eq :cancelled (spool-client:cancel connection dropped)))
        (is (eq :resumed (spool-client:resume connection "reports")))
        (is (equal '(:done "first")
                   (multiple-value-list (spool-client:wait connection first :timeout 10))))
        (is (eq :done (spool-client:wait connection urgent :timeout 10)))
        (is (eq :cancelled (spool-client:wait connection dropped :timeout 10)))))))

(test client-errors
  (with-server (server)
    (with-client (connection server)
      (signals spool-error (spool-client:submit connection "nowhere" "echo" '()))
      (signals spool-error (spool-client:status connection 42))
      (signals spool-error (spool-client:request connection "FROBNICATE"))
      (signals spool-error (spool-client:request connection "STATUS" "x"))
      (signals spool-error (spool-client:request connection "SUBMIT" "default" "echo" ":priority"))
      ;; The connection still works after errors.
      (is (equal '("default") (spool-client:queues connection))))))

(test two-clients
  (with-server (server :queues '(("reports" :workers 1)))
    (with-client (one server)
      (with-client (two server)
        (spool-client:pause one "reports")
        (let ((id (spool-client:submit one "reports" "echo" '("from" "one"))))
          (is (eq :timeout (spool-client:wait two id :timeout 1)))
          (spool-client:resume two "reports")
          (is (equal '(:done "from one")
                     (multiple-value-list (spool-client:wait two id :timeout 10)))))))))
