(defpackage #:spool/tests
  (:use #:common-lisp #:fiveam)
  (:import-from #:spool #:define-job-kind #:spool-error))

(in-package #:spool/tests)

(def-suite :spool :description "Tests for spool.")
(in-suite :spool)

(defmacro with-server ((var &rest options) &body body)
  "Runs BODY with VAR a server started with OPTIONS, which logs nowhere,
and stops it after."
  `(let ((,var (spool:start-server :log nil ,@options)))
     (unwind-protect (progn ,@body)
       (spool:stop-server ,var))))

(defun wait-until (predicate &key (timeout 10))
  "Calls PREDICATE until it returns true, for at most TIMEOUT seconds, and
returns its value, or NIL when it never did."
  (loop with deadline = (+ (get-internal-real-time) (* timeout internal-time-units-per-second))
        for value = (funcall predicate)
        until (or value (> (get-internal-real-time) deadline))
        do (sleep 0.01)
        finally (return value)))

;;; Kinds of job for the tests.

(defvar *ran* '()
  "The arguments of the record jobs that ran, the last first.")

(defvar *ran-lock* (sb-thread:make-mutex :name "test record"))

(define-job-kind "record" (name)
  (sb-thread:with-mutex (*ran-lock*)
    (push name *ran*))
  name)

(defun ran ()
  "Returns the names of the record jobs that ran, in the order they ran,
and forgets them."
  (sb-thread:with-mutex (*ran-lock*)
    (prog1 (reverse *ran*)
      (setf *ran* '()))))

(defvar *flaky-tries* (make-hash-table :test 'equal :synchronized t))

(define-job-kind "flaky" (name failures)
  ;; Fails the first FAILURES times it runs for NAME.
  (let ((tries (incf (gethash name *flaky-tries* 0))))
    (if (<= tries (parse-integer failures))
        (spool:fail "try ~D of ~A failed" tries name)
        (format nil "~A after ~D tries" name tries))))

(define-job-kind "crash" ()
  (error "the job crashed"))
