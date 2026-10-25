(in-package #:spool)

;;; The server: its queues, its jobs and the workers that run them.
;;;
;;; One lock, the server's, guards every queue and job. Each queue's
;;; workers wait on the queue's READY waitqueue for a job to run, and
;;; anyone waiting for a job to finish waits on the server's CHANGED one.

(defstruct (queue (:constructor make-queue (name worker-count)))
  (name nil :type string)
  (worker-count 1 :type (integer 1))
  (heap (make-job-heap))
  (paused nil)
  (ready (sb-thread:make-waitqueue))
  (workers '())
  ;; How many of the queue's jobs are running, and how many ended so.
  (running 0)
  (done 0)
  (failed 0)
  (cancelled 0))

(defstruct (server (:constructor %make-server (log)))
  (lock (sb-thread:make-mutex :name "spool server"))
  (changed (sb-thread:make-waitqueue))
  (queues (make-hash-table :test 'equal))
  (jobs (make-hash-table))
  (last-id 0)
  (last-sequence 0)
  (stopping nil)
  log
  ;; The network side, when the server listens; see network.lisp.
  listener
  listener-thread
  (port nil)
  (connections '()))

(defmacro with-server-lock ((server) &body body)
  `(sb-thread:with-mutex ((server-lock ,server))
     ,@body))

(defun log-event (server control &rest arguments)
  (apply #'write-log (server-log server) control arguments))

(defun find-queue (server name)
  "Returns the queue NAME of SERVER, or signals SPOOL-ERROR."
  (or (gethash name (server-queues server))
      (spool-error "no queue ~A" name)))

(defun find-job (server id)
  "Returns the job ID of SERVER, or signals SPOOL-ERROR."
  (or (gethash id (server-jobs server))
      (spool-error "no job ~A" id)))

(defun job-queue-of (server job)
  (find-queue server (job-queue job)))

(defun server-queue-names (server)
  "Returns the names of SERVER's queues, sorted."
  (with-server-lock (server)
    (sort (loop for name being the hash-keys of (server-queues server) collect name)
          #'string<)))

;;; Starting and stopping

(defun start-server (&key (queues '(("default" :workers 2)))
                          (host "127.0.0.1") (port 0) (log *error-output*))
  "Starts a server with QUEUES, each a list of a name and :WORKERS, how
many jobs of the queue run at once. It listens for clients on HOST and
PORT, 0 for any free port, unless PORT is NIL. It writes its log to LOG,
a stream, or nowhere if LOG is NIL. Returns the server."
  (let ((server (%make-server log)))
    (loop for (name . options) in queues
          do (destructuring-bind (&key (workers 1)) options
               (setf (gethash name (server-queues server)) (make-queue name workers))))
    (loop for queue being the hash-values of (server-queues server)
          do (start-workers server queue))
    (when port
      (start-listener server host port))
    (log-event server "started~@[ on port ~D~] with ~{~A~^, ~}"
               (server-port server) (server-queue-names server))
    server))

(defun stop-server (server)
  "Stops SERVER: it takes no more requests, its clients are disconnected,
and its workers stop once their jobs are done."
  (with-server-lock (server)
    (setf (server-stopping server) t)
    (sb-thread:condition-broadcast (server-changed server))
    (loop for queue being the hash-values of (server-queues server)
          do (sb-thread:condition-broadcast (queue-ready queue))))
  (stop-listener server)
  (loop for queue being the hash-values of (server-queues server)
        do (dolist (worker (queue-workers queue))
             (sb-thread:join-thread worker :default nil :timeout 10)))
  (log-event server "stopped")
  server)

;;; Submitting and queueing

(defun parse-priority (value)
  (if (typep value '(integer 0 9))
      value
      (spool-error "priority must be from 0 to 9, not ~A" value)))

(defun enqueue (server queue job)
  "Puts JOB in QUEUE to wait for a worker. Called with the lock held."
  (setf (job-state job) :queued
        (job-sequence job) (incf (server-last-sequence server)))
  (heap-insert (queue-heap queue) job)
  (sb-thread:condition-notify (queue-ready queue)))

(defun submit (server queue-name kind args &key (priority 5) (attempts 1))
  "Queues a job of KIND on ARGS, a list of strings, in the queue
QUEUE-NAME of SERVER, and returns its id. Of the waiting jobs, the one of
the highest PRIORITY, from 0 to 9, runs first, and of those the one queued
first. A job whose kind signals JOB-ERROR is tried again until it has been
tried ATTEMPTS times."
  (unless (find-job-kind kind)
    (spool-error "no job kind ~A" kind))
  (parse-priority priority)
  (unless (typep attempts '(integer 1))
    (spool-error "attempts must be a positive integer, not ~A" attempts))
  (with-server-lock (server)
    (let* ((queue (find-queue server queue-name))
           (job (%make-job :id (incf (server-last-id server))
                           :queue (queue-name queue) :kind kind :args args
                           :priority priority :attempts attempts)))
      (setf (gethash (job-id job) (server-jobs server)) job)
      (enqueue server queue job)
      (job-id job))))

(defun job-status (server id)
  "Returns the state of the job ID: :QUEUED, :RUNNING, :DONE, :FAILED or
:CANCELLED."
  (with-server-lock (server)
    (job-state (find-job server id))))

(defun job-outcome (job)
  (case (job-state job)
    (:done (job-answer job))
    (:failed (job-message job))))

(defun job-result (server id)
  "Returns the state of the job ID, and its result when it is done or the
reason when it failed."
  (with-server-lock (server)
    (let ((job (find-job server id)))
      (values (job-state job) (job-outcome job)))))

(defun wait-for-job (server id &key timeout)
  "Waits until the job ID is done, failed or cancelled, and returns its
state and outcome as JOB-RESULT does. With TIMEOUT, waits at most that
many seconds, and returns :TIMEOUT if it is not finished by then."
  (let ((deadline (and timeout
                       (+ (get-internal-real-time)
                          (round (* timeout internal-time-units-per-second))))))
    (with-server-lock (server)
      (let ((job (find-job server id)))
        (loop until (finished-state-p (job-state job))
              do (when (server-stopping server)
                   (spool-error "the server is stopping"))
                 (let ((left (and deadline
                                  (/ (- deadline (get-internal-real-time))
                                     internal-time-units-per-second))))
                   (when (and left (<= left 0))
                     (return-from wait-for-job :timeout))
                   (unless (sb-thread:condition-wait (server-changed server)
                                                     (server-lock server)
                                                     :timeout left)
                     ;; Timed out, and without the lock.
                     (return-from wait-for-job :timeout))))
        (values (job-state job) (job-outcome job))))))

(defun cancel-job (server id)
  "Cancels the job ID, which must be waiting to run: a running or finished
job cannot be cancelled. Returns :CANCELLED."
  (with-server-lock (server)
    (let* ((job (find-job server id))
           (queue (job-queue-of server job)))
      (unless (eq (job-state job) :queued)
        (spool-error "job ~D is ~(~A~)" id (job-state job)))
      (heap-delete (queue-heap queue) job)
      (setf (job-state job) :cancelled)
      (incf (queue-cancelled queue))
      (sb-thread:condition-broadcast (server-changed server))
      :cancelled)))

(defun retry-job (server id)
  "Queues the failed job ID again, for as many attempts as it had at
first. Returns :QUEUED."
  (with-server-lock (server)
    (let* ((job (find-job server id))
           (queue (job-queue-of server job)))
      (unless (eq (job-state job) :failed)
        (spool-error "job ~D is ~(~A~), not failed" id (job-state job)))
      (decf (queue-failed queue))
      (setf (job-tries job) 0
            (job-message job) nil)
      (enqueue server queue job)
      (sb-thread:condition-broadcast (server-changed server))
      :queued)))

(defun pause-queue (server name)
  "Lets no more jobs of the queue NAME start until it is resumed. The jobs
running go on."
  (with-server-lock (server)
    (setf (queue-paused (find-queue server name)) t))
  :paused)

(defun resume-queue (server name)
  "Lets the jobs of the queue NAME start again."
  (with-server-lock (server)
    (let ((queue (find-queue server name)))
      (setf (queue-paused queue) nil)
      (sb-thread:condition-broadcast (queue-ready queue))))
  :resumed)

(defun queue-stats (server name)
  "Returns how many jobs of the queue NAME are waiting and running, and
how many are done, failed and cancelled, as a plist."
  (with-server-lock (server)
    (let ((queue (find-queue server name)))
      (list :waiting (heap-count (queue-heap queue))
            :running (queue-running queue)
            :done (queue-done queue)
            :failed (queue-failed queue)
            :cancelled (queue-cancelled queue)))))

;;; Workers

(defun start-workers (server queue)
  (setf (queue-workers queue)
        (loop for number from 1 to (queue-worker-count queue)
              for name = (format nil "~A-~D" (queue-name queue) number)
              collect (let ((name name))
                        (sb-thread:make-thread (lambda () (work server queue name))
                                               :name (format nil "spool worker ~A" name))))))

(defun next-job (server queue)
  "Waits until a job of QUEUE may start, and takes it out of the queue, or
returns NIL once the server is stopping."
  (with-server-lock (server)
    (loop
      (cond ((server-stopping server)
             (return nil))
            ((and (not (queue-paused queue))
                  (plusp (heap-count (queue-heap queue))))
             (return (heap-pop (queue-heap queue))))
            (t
             (sb-thread:condition-wait (queue-ready queue) (server-lock server)))))))

(defun begin-job (server job)
  "Marks JOB running and returns the function of its kind."
  (with-server-lock (server)
    (unless (eq (job-state job) :queued)
      (error "job ~D is ~(~A~), not queued" (job-id job) (job-state job)))
    (setf (job-state job) :running)
    (incf (job-tries job))
    (incf (queue-running (job-queue-of server job)))
    (sb-thread:condition-broadcast (server-changed server))
    (or (find-job-kind (job-kind job))
        (error "no job kind ~A" (job-kind job)))))

(defun end-job (server job state &key result message)
  "Ends JOB in STATE, :DONE with RESULT or :FAILED with MESSAGE."
  (with-server-lock (server)
    (let ((queue (job-queue-of server job)))
      (when (eq (job-state job) :running)
        (decf (queue-running queue)))
      (setf (job-state job) state
            (job-answer job) result
            (job-message job) message)
      (ecase state
        (:done (incf (queue-done queue)))
        (:failed (incf (queue-failed queue))))
      (sb-thread:condition-broadcast (server-changed server)))))

(defun try-again (server job)
  "Queues JOB, which failed but has attempts left, again."
  (with-server-lock (server)
    (let ((queue (job-queue-of server job)))
      (decf (queue-running queue))
      (enqueue server queue job))))

(defun run-job (server job)
  "Runs JOB and records how it ended."
  (let ((function (begin-job server job)))
    (handler-case
        (let ((result (apply function (job-args job))))
          (end-job server job :done :result (princ-to-string result)))
      (job-error (failure)
        (if (< (job-tries job) (job-attempts job))
            (try-again server job)
            (end-job server job :failed :message (princ-to-string failure)))))))

(defun work (server queue name)
  "Runs the jobs of QUEUE, one at a time, until SERVER stops."
  (loop for job = (next-job server queue)
        while job
        do (handler-case (run-job server job)
             (error (e)
               (log-event server "worker ~A: job ~D failed: ~A" name (job-id job) e)
               (end-job server job :failed :message (princ-to-string e))))))
