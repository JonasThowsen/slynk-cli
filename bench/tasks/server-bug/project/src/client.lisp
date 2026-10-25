(in-package #:spool-client)

;;; A client of a spool server: a connection, and a function for each
;;; request (see protocol.lisp). A reply of ERR signals SPOOL-ERROR.

(defstruct (connection (:constructor make-connection (socket stream)))
  socket
  stream)

(defun connect (&key (host "127.0.0.1") port)
  "Connects to the spool server on HOST and PORT and returns the connection."
  (let ((socket (make-instance 'sb-bsd-sockets:inet-socket :type :stream :protocol :tcp)))
    (sb-bsd-sockets:socket-connect socket (sb-bsd-sockets:make-inet-address host) port)
    (make-connection socket
                     (sb-bsd-sockets:socket-make-stream socket :input t :output t
                                                               :element-type 'character
                                                               :external-format :utf-8
                                                               :buffering :full))))

(defun disconnect (connection)
  "Says goodbye to the server and closes CONNECTION."
  (ignore-errors (request connection "QUIT"))
  (ignore-errors (close (connection-stream connection)))
  (values))

(defmacro with-connection ((var &rest options) &body body)
  "Runs BODY with VAR a connection made with OPTIONS, as CONNECT takes them."
  `(let ((,var (connect ,@options)))
     (unwind-protect (progn ,@body)
       (disconnect ,var))))

(defun request (connection &rest tokens)
  "Sends the request of TOKENS and returns the tokens of the answer, the
strings after OK."
  (let ((stream (connection-stream connection)))
    (write-line (join-tokens tokens) stream)
    (force-output stream)
    (let ((line (read-line stream)))
      (cond ((or (string= line "OK") (eql 0 (search "OK " line)))
             (rest (split-tokens line)))
            ((eql 0 (search "ERR " line))
             (error 'spool-error :format-control "~A" :format-arguments (list (subseq line 4))))
            (t
             (error 'spool-error :format-control "not a reply: ~S" :format-arguments (list line)))))))

(defun keyword-token (token)
  (intern (string-upcase token) :keyword))

(defun submit (connection queue kind args &key priority attempts)
  "Submits a job of KIND on ARGS, a list of strings, to QUEUE, and returns
its id."
  (parse-integer
   (first (apply #'request connection "SUBMIT" queue kind
                 (append (and priority (list ":priority" priority))
                         (and attempts (list ":attempts" attempts))
                         args)))))

(defun status (connection id)
  "Returns the state of the job ID, a keyword."
  (keyword-token (first (request connection "STATUS" id))))

(defun wait (connection id &key timeout)
  "Waits for the job ID to finish, at most TIMEOUT seconds when given, and
returns its state, a keyword, and its result or the reason it failed;
or :TIMEOUT."
  (destructuring-bind (state &optional outcome)
      (if timeout
          (request connection "WAIT" id timeout)
          (request connection "WAIT" id))
    (values (keyword-token state) outcome)))

(defun cancel (connection id)
  "Cancels the job ID, which must be waiting."
  (keyword-token (first (request connection "CANCEL" id))))

(defun retry (connection id)
  "Queues the failed job ID again."
  (keyword-token (first (request connection "RETRY" id))))

(defun pause (connection queue)
  "Lets no more jobs of QUEUE start."
  (keyword-token (first (request connection "PAUSE" queue))))

(defun resume (connection queue)
  "Lets the jobs of QUEUE start again."
  (keyword-token (first (request connection "RESUME" queue))))

(defun stats (connection queue)
  "Returns the counts of QUEUE's jobs, a plist from :WAITING, :RUNNING,
:DONE, :FAILED and :CANCELLED to integers."
  (loop for (name count) on (request connection "STATS" queue) by #'cddr
        collect (keyword-token name)
        collect (parse-integer count)))

(defun queues (connection)
  "Returns the names of the server's queues."
  (request connection "QUEUES"))
