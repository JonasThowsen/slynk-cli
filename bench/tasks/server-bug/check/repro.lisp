;;;; The reported case and related ones: a cancelled job never runs, every
;;;; other job runs once, in the order of the priorities, whatever came
;;;; before. The jobs here are gates the check opens, so that the check
;;;; knows which job runs at each moment and nothing depends on timing.

(in-package :cl-user)

(defvar *gate-lock* (sb-thread:make-mutex :name "check gates"))
(defvar *gate-changed* (sb-thread:make-waitqueue))
(defvar *opened* (make-hash-table :test 'equal))
(defvar *started* '()
  "The labels of the gate jobs that started, the latest first.")
(defvar *all-open* nil
  "True when every gate is open, as when a server of the check stops.")

(spool:define-job-kind "check-gate" (label)
  (sb-thread:with-mutex (*gate-lock*)
    (push label *started*)
    (sb-thread:condition-broadcast *gate-changed*)
    (loop until (or *all-open* (gethash label *opened*))
          do (sb-thread:condition-wait *gate-changed* *gate-lock*)))
  label)

(defun open-gate (label)
  (sb-thread:with-mutex (*gate-lock*)
    (setf (gethash label *opened*) t)
    (sb-thread:condition-broadcast *gate-changed*)))

(defun started-count ()
  (sb-thread:with-mutex (*gate-lock*)
    (length *started*)))

(defun await (predicate &optional (seconds 10))
  "Calls PREDICATE until it is true, for at most SECONDS; returns whether it was."
  (loop with deadline = (+ (get-internal-real-time) (* seconds internal-time-units-per-second))
        when (funcall predicate) return t
        when (> (get-internal-real-time) deadline) return nil
        do (sleep 0.005)))

(defun await-start (count)
  "Waits until COUNT gate jobs have started, and returns the label of the
last, or NIL if they did not."
  (and (await (lambda () (>= (started-count) count)))
       (sb-thread:with-mutex (*gate-lock*)
         (first *started*))))

(defun reset-gates ()
  (sb-thread:with-mutex (*gate-lock*)
    (clrhash *opened*)
    (setf *started* '()
          *all-open* nil)))

(defmacro with-check-server ((var queues) &body body)
  `(let ((,var (spool:start-server :log nil :queues ,queues)))
     (unwind-protect (progn ,@body)
       ;; Let every gate go, so that the workers can stop.
       (sb-thread:with-mutex (*gate-lock*)
         (setf *all-open* t)
         (sb-thread:condition-broadcast *gate-changed*))
       (spool:stop-server ,var))))

;;; The report, over the network, with gates for the exports.

(defun reported-sequence-failures ()
  (let ((failures '()))
    (flet ((expect (what got expected)
             (unless (equalp got expected)
               (push (format nil "~A: got ~S, expected ~S" what got expected) failures))))
      (reset-gates)
      (with-check-server (server '(("reports" :workers 1)))
        (spool-client:with-connection (c :port (spool:server-port server))
          (let ((export-1 (spool-client:submit c "reports" "check-gate" '("export 1"))))
            (expect "export 1 starts" (await-start 1) "export 1")
            (let ((export-2 (spool-client:submit c "reports" "check-gate" '("export 2")))
                  (reminder-1 (spool-client:submit c "reports" "echo" '("reminder" "1"))))
              (open-gate "export 1")
              (expect "wait for export 1" (spool-client:wait c export-1 :timeout 10) :done)
              (expect "export 2 starts" (await-start 2) "export 2")
              (let ((reminder-2 (spool-client:submit c "reports" "echo" '("reminder" "2"))))
                (expect "cancel reminder 1" (spool-client:cancel c reminder-1) :cancelled)
                (open-gate "export 2")
                (expect "wait for export 2" (spool-client:wait c export-2 :timeout 10) :done)
                (expect "wait for reminder 2"
                        (multiple-value-list (spool-client:wait c reminder-2 :timeout 10))
                        '(:done "reminder 2"))
                (expect "status of reminder 1" (spool-client:status c reminder-1) :cancelled)
                (expect "wait for reminder 1"
                        (multiple-value-list (spool-client:wait c reminder-1 :timeout 10))
                        '(:cancelled nil))
                (expect "stats" (spool-client:stats c "reports")
                        '(:waiting 0 :running 0 :done 3 :failed 0 :cancelled 1))))))))
    (nreverse failures)))

;;; Many submits and cancels in a random order, between the starts of the
;;; jobs, against a model of the queue: of the waiting jobs, the next to
;;; start is the one of the highest priority, and of those the one
;;; submitted first.

(defun model-failures (seed &key (steps 150))
  (let ((random (sb-ext:seed-random-state seed))
        (failures '())
        (waiting '())                   ; (label id priority sequence), in the model
        (running nil)                   ; the label running, in the model
        (cancelled '())
        (ids (make-hash-table :test 'equal))
        (sequence 0)
        (starts 0))
    (labels ((fail (control &rest arguments)
               (push (format nil "seed ~D: ~?" seed control arguments) failures)
               (return-from model-failures (nreverse failures)))
             (next-in-model ()
               (first (sort (copy-list waiting)
                            (lambda (a b)
                              (or (> (third a) (third b))
                                  (and (= (third a) (third b)) (< (fourth a) (fourth b)))))))))
      (reset-gates)
      (with-check-server (server '(("q" :workers 1)))
        (dotimes (step steps)
          (spool:pause-queue server "q")
          (dotimes (op (random 4 random))
            (if (or (null waiting) (< (random 10 random) 6))
                (let* ((label (format nil "job ~D" (incf sequence)))
                       (priority (random 4 random))
                       (id (spool:submit server "q" "check-gate" (list label) :priority priority)))
                  (setf (gethash label ids) id)
                  (push (list label id priority sequence) waiting))
                (let ((victim (nth (random (length waiting) random) waiting)))
                  (handler-case (spool:cancel-job server (second victim))
                    (spool:spool-error (e)
                      (fail "step ~D: cancelling waiting ~A: ~A" step (first victim) e)))
                  (setf waiting (remove victim waiting))
                  (push (first victim) cancelled))))
          (when (and running (zerop (random 3 random)))
            (when (ignore-errors (spool:cancel-job server (gethash running ids)) t)
              (fail "step ~D: cancelling the running ~A did not fail" step running)))
          (spool:resume-queue server "q")
          (when running
            (open-gate running)
            (unless (eq :done (spool:wait-for-job server (gethash running ids) :timeout 10))
              (fail "step ~D: ~A did not finish once let go" step running))
            (setf running nil))
          (let ((next (next-in-model)))
            (when next
              (let ((label (await-start (incf starts))))
                (unless (equal label (first next))
                  (fail "step ~D: ~A started, but ~A should have, of ~{~A~^, ~}"
                        step (or label "no job") (first next)
                        (mapcar #'first (sort (copy-list waiting) #'< :key #'fourth))))
                (setf waiting (remove next waiting)
                      running label)))))
        ;; The rest run in order.
        (loop
          (when running
            (open-gate running)
            (unless (eq :done (spool:wait-for-job server (gethash running ids) :timeout 10))
              (fail "at the end: ~A did not finish once let go" running))
            (setf running nil))
          (let ((next (next-in-model)))
            (unless next (return))
            (let ((label (await-start (incf starts))))
              (unless (equal label (first next))
                (fail "at the end: ~A started, but ~A should have" (or label "no job") (first next)))
              (setf waiting (remove next waiting)
                    running label))))
        (dolist (label cancelled)
          (unless (eq :cancelled (spool:job-status server (gethash label ids)))
            (fail "cancelled ~A is ~(~A~)" label (spool:job-status server (gethash label ids)))))
        (let ((stats (spool:queue-stats server "q")))
          (unless (equal stats (list :waiting 0 :running 0
                                     :done (- sequence (length cancelled)) :failed 0
                                     :cancelled (length cancelled)))
            (fail "the stats at the end are ~S, of ~D jobs, ~D cancelled"
                  stats sequence (length cancelled))))))
    (nreverse failures)))

(defun reproduction-failures ()
  (append (reported-sequence-failures)
          (loop for seed in '(1 2 3 4 5 6)
                append (model-failures seed))))
