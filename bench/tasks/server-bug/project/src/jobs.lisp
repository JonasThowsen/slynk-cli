(in-package #:spool)

;;; Jobs and the kinds of job there are.
;;;
;;; A job is a request to run a kind of job on some arguments, in a queue.
;;; It is queued, then running, then done or failed; a queued job may be
;;; cancelled instead, and a failed one retried, which queues it again.

(defstruct (job (:constructor %make-job))
  (id 0 :type (integer 1))
  (queue nil :type string)
  (kind nil :type string)
  (args '() :type list)
  (priority 5 :type (integer 0 9))
  (attempts 1 :type (integer 1))
  (tries 0 :type (integer 0))
  ;; Orders the jobs of one priority: the job queued first runs first.
  (sequence 0 :type (integer 0))
  (state :queued :type (member :queued :running :done :failed :cancelled))
  ;; The job's place in its queue's heap while it is queued, else NIL.
  (heap-index nil :type (or null (integer 0)))
  (answer nil :type (or null string))
  (message nil :type (or null string)))

(defmethod print-object ((job job) stream)
  (print-unreadable-object (job stream :type t)
    (format stream "~D ~A ~A ~(~A~)"
            (job-id job) (job-queue job) (job-kind job) (job-state job))))

(defun finished-state-p (state)
  "True when a job in STATE will not change again unless it is retried."
  (member state '(:done :failed :cancelled)))

;;; Kinds

(define-condition job-error (simple-error)
  ()
  (:documentation "Signalled by a job kind's function when the job cannot
be done, with the reason as the message. The job is tried again while it
has attempts left, and fails after."))

(defun fail (control &rest arguments)
  "Ends the job being run with the failure CONTROL and ARGUMENTS say."
  (error 'job-error :format-control control :format-arguments arguments))

(defvar *job-kinds* (make-hash-table :test 'equal :synchronized t)
  "The function of each kind of job, by the kind's name.")

(defmacro define-job-kind (name lambda-list &body body)
  "Defines the kind of job NAME, a string. Its function takes the job's
arguments, strings, as LAMBDA-LIST says, and returns the job's result,
a string."
  `(progn
     (setf (gethash ,name *job-kinds*)
           (lambda ,lambda-list ,@body))
     ,name))

(defun find-job-kind (name)
  "Returns the function of the kind of job NAME, or NIL if there is none."
  (values (gethash name *job-kinds*)))

(defun job-kind-names ()
  "Returns the names of the kinds of job, sorted."
  (sort (loop for name being the hash-keys of *job-kinds* collect name) #'string<))

(defun parse-number-argument (string what)
  "Returns the non-negative number STRING writes, an integer or a decimal
such as 0.25, or fails the job naming the argument WHAT."
  (let ((dot (position #\. string)))
    (or (ignore-errors
         (let ((whole (parse-integer string :end dot))
               (fraction (if dot (subseq string (1+ dot)) "")))
           (when (and (>= whole 0) (every #'digit-char-p fraction))
             (+ whole (if (plusp (length fraction))
                          (/ (parse-integer fraction) (expt 10 (length fraction)))
                          0)))))
        (fail "~A must be a number, not ~S" what string))))

;;; The kinds every server has; an application defines its own as well.

(define-job-kind "echo" (&rest words)
  (format nil "~{~A~^ ~}" words))

(define-job-kind "sleep" (seconds)
  (let ((seconds (parse-number-argument seconds "seconds")))
    (sleep seconds)
    (format nil "slept ~A" (if (integerp seconds) seconds (float seconds 1.0)))))

(define-job-kind "checksum" (text)
  ;; Adler-32 of the text's UTF-8 octets, as eight hex digits.
  (let ((a 1) (b 0))
    (loop for octet across (sb-ext:string-to-octets text :external-format :utf-8)
          do (setf a (mod (+ a octet) 65521)
                   b (mod (+ b a) 65521)))
    (format nil "~(~8,'0X~)" (logior (ash b 16) a))))

(define-job-kind "count-words" (text)
  (let ((count 0) (in-word nil))
    (loop for char across text
          do (if (or (alphanumericp char) (char= char #\'))
                 (unless in-word (setf in-word t) (incf count))
                 (setf in-word nil)))
    (princ-to-string count)))

(define-job-kind "fail" (&rest words)
  (fail "~{~A~^ ~}" (or words '("failed as asked"))))
