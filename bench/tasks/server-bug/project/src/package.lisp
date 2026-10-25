(defpackage #:spool
  (:use #:common-lisp)
  (:export
   ;; Tokens of the protocol
   #:split-tokens
   #:quote-token
   #:join-tokens
   ;; Job kinds
   #:define-job-kind
   #:find-job-kind
   #:job-kind-names
   #:job-error
   #:fail
   ;; The server
   #:spool-error
   #:start-server
   #:stop-server
   #:server-port
   #:server-queue-names
   #:submit
   #:job-status
   #:job-result
   #:wait-for-job
   #:cancel-job
   #:retry-job
   #:pause-queue
   #:resume-queue
   #:queue-stats))

(defpackage #:spool-client
  (:use #:common-lisp)
  (:import-from #:spool #:split-tokens #:join-tokens #:spool-error)
  (:export
   #:connect
   #:disconnect
   #:with-connection
   #:request
   #:submit
   #:status
   #:wait
   #:cancel
   #:retry
   #:pause
   #:resume
   #:stats
   #:queues))
