(in-package #:logsum)

;;; A session: the requests of one visitor (one IP address) with less
;;; than half an hour between each and the next. The logs of the web
;;; servers are merged, so their lines are not quite in the order of time.

(defparameter *session-gap* (* 30 60)
  "The seconds without a request after which a visitor's next request
starts a new session.")

(defstruct (session (:constructor make-session (ip start)))
  (ip "" :type string)
  (start 0 :type integer)
  (end 0 :type integer)
  (requests 0 :type (integer 0)))

(defun sessionize (requests)
  "Returns the sessions of REQUESTS, in the order they started, and those
that started at the same second in the order of their visitors."
  (let ((open (make-hash-table :test 'equal))
        (sessions '())
        ;; Each request with its time, parsed once.
        (timed (mapcar (lambda (request) (cons (request-seconds request) request))
                       requests)))
    (loop for (time . request) in (stable-sort timed #'< :key #'car)
          for ip = (request-ip request)
          for session = (gethash ip open)
          do (when (or (null session) (>= (- time (session-end session)) *session-gap*))
               (setf session (make-session ip time)
                     (gethash ip open) session)
               (push session sessions))
             (setf (session-end session) time)
             (incf (session-requests session)))
    (stable-sort (nreverse sessions)
                 (lambda (a b)
                   (or (< (session-start a) (session-start b))
                       (and (= (session-start a) (session-start b))
                            (string< (session-ip a) (session-ip b))))))))
