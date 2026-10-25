(in-package #:spool)

;;; The requests a client sends and the server's replies. A request is a
;;; command and its arguments; the reply is OK and the answer, or ERR and
;;; what went wrong:
;;;
;;;   SUBMIT queue kind [:priority n] [:attempts n] [arg ...]   OK id
;;;   STATUS id                       OK queued|running|done|failed|cancelled
;;;   WAIT id [seconds]               OK done result | OK failed reason
;;;                                   | OK cancelled | OK timeout
;;;   CANCEL id                       OK cancelled
;;;   RETRY id                        OK queued
;;;   PAUSE queue                     OK paused
;;;   RESUME queue                    OK resumed
;;;   STATS queue                     OK waiting n running n done n failed n cancelled n
;;;   QUEUES                          OK name ...
;;;   KINDS                           OK name ...
;;;   QUIT                            OK bye

(defun parse-natural (token what)
  "Returns the non-negative integer TOKEN writes, or signals SPOOL-ERROR
naming it WHAT."
  (or (and (plusp (length token))
           (every #'digit-char-p token)
           (parse-integer token))
      (spool-error "~A must be a whole number, not ~A" what token)))

(defun parse-submit-options (tokens)
  "Returns the options at the start of TOKENS, as a plist for SUBMIT, and
the tokens after them."
  (let ((options '()))
    (loop while (and tokens
                     (plusp (length (first tokens)))
                     (char= (char (first tokens) 0) #\:))
          do (let ((option (pop tokens)))
               (unless tokens
                 (spool-error "~A needs a value" option))
               (let ((value (parse-natural (pop tokens) option)))
                 (cond ((string-equal option ":priority")
                        (setf (getf options :priority) value))
                       ((string-equal option ":attempts")
                        (setf (getf options :attempts) value))
                       (t (spool-error "no option ~A" option))))))
    (values options tokens)))

(defun expect-arguments (command arguments count)
  (unless (= (length arguments) count)
    (spool-error "~A takes ~D argument~:P" command count)))

(defun reply-state (state &optional outcome)
  (if outcome
      (list state outcome)
      (list state)))

(defun answer (server command arguments)
  "Carries out the request COMMAND, an upper-case string, with ARGUMENTS,
and returns the tokens of the answer."
  (flet ((id (token) (parse-natural token "a job id")))
    (cond
      ((string= command "SUBMIT")
       (when (< (length arguments) 2)
         (spool-error "SUBMIT takes a queue, a kind and the job's arguments"))
       (destructuring-bind (queue kind &rest rest) arguments
         (multiple-value-bind (options args) (parse-submit-options rest)
           (list (apply #'submit server queue kind args options)))))
      ((string= command "STATUS")
       (expect-arguments command arguments 1)
       (list (job-status server (id (first arguments)))))
      ((string= command "WAIT")
       (unless (<= 1 (length arguments) 2)
         (spool-error "WAIT takes a job id and, if you like, the seconds to wait"))
       (multiple-value-call #'reply-state
         (wait-for-job server (id (first arguments))
                       :timeout (and (second arguments)
                                     (parse-natural (second arguments) "seconds")))))
      ((string= command "CANCEL")
       (expect-arguments command arguments 1)
       (list (cancel-job server (id (first arguments)))))
      ((string= command "RETRY")
       (expect-arguments command arguments 1)
       (list (retry-job server (id (first arguments)))))
      ((string= command "PAUSE")
       (expect-arguments command arguments 1)
       (list (pause-queue server (first arguments))))
      ((string= command "RESUME")
       (expect-arguments command arguments 1)
       (list (resume-queue server (first arguments))))
      ((string= command "STATS")
       (expect-arguments command arguments 1)
       (queue-stats server (first arguments)))
      ((string= command "QUEUES")
       (expect-arguments command arguments 0)
       (server-queue-names server))
      ((string= command "KINDS")
       (expect-arguments command arguments 0)
       (job-kind-names))
      ((string= command "QUIT")
       (list "bye"))
      (t (spool-error "no command ~A" command)))))

(defun handle-request (server line)
  "Returns the reply to the request LINE."
  (handler-case
      (let ((tokens (split-tokens line)))
        (if tokens
            (join-tokens (cons "OK" (answer server (string-upcase (first tokens)) (rest tokens))))
            "ERR empty request"))
    (spool-error (e)
      (format nil "ERR ~A" e))
    (error (e)
      (log-event server "request ~S failed: ~A" line e)
      "ERR internal error")))
