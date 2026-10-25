(in-package #:logsum)

;;; The monthly report: a line for each day, then the month's routes. A
;;; visitor is an IP address; a bounce is a session of one request; an
;;; error is a reply with a 5xx status.

(defstruct (day-summary (:constructor make-day-summary))
  ;; The day, as 2026-03-14.
  (day "" :type string)
  (requests 0 :type (integer 0))
  ;; The IP addresses of the day's visitors.
  (visitors '() :type list)
  (sessions 0 :type (integer 0))
  (bounces 0 :type (integer 0))
  (median-latency 0 :type (integer 0))
  (slow-latency 0 :type (integer 0))
  (errors 0 :type (integer 0))
  ;; The day's most requested routes, as (route . requests).
  (top-routes '() :type list))

(defstruct (route-summary (:constructor make-route-summary))
  (route "" :type string)
  (requests 0 :type (integer 0))
  (median-latency 0 :type (integer 0))
  (slow-latency 0 :type (integer 0))
  (errors 0 :type (integer 0)))

(defstruct (month-summary (:constructor make-month-summary))
  (days '() :type list)
  (requests 0 :type (integer 0))
  (visitors 0 :type (integer 0))
  (returning 0 :type (integer 0))
  (busiest-hour nil)
  (routes '() :type list))

(defun server-error-p (request)
  (>= (request-status request) 500))

(defun request-date (request)
  "Returns the day of REQUEST, as 2026-03-14."
  (subseq (request-time request) 0 10))

(defun requests-by-day (requests)
  "Returns the requests grouped by day, as a list of (day . requests) in
the order of the days, each day's requests in the order of REQUESTS. The
days are written as 2026-03-14."
  (let ((days (make-hash-table :test 'equal)))
    (dolist (request requests)
      (push request (gethash (request-date request) days)))
    (sort (loop for day being the hash-keys of days using (hash-value requests)
                collect (cons day (reverse requests)))
          #'string< :key #'car)))

(defun summarize-day (day requests)
  "Returns the summary of the REQUESTS of DAY."
  (let ((sessions (sessionize requests))
        (latencies (mapcar #'request-latency requests)))
    (make-day-summary :day day
                      :requests (length requests)
                      :visitors (mapcar #'car (count-by #'request-ip requests))
                      :sessions (length sessions)
                      :bounces (count 1 sessions :key #'session-requests)
                      :median-latency (percentile latencies 50)
                      :slow-latency (percentile latencies 95)
                      :errors (count-if #'server-error-p requests)
                      :top-routes (most-common (count-by #'request-route requests) 3))))

(defun summarize-route (route requests)
  "Returns the summary of REQUESTS, all of ROUTE."
  (let ((latencies (mapcar #'request-latency requests)))
    (make-route-summary :route route
                        :requests (length requests)
                        :median-latency (percentile latencies 50)
                        :slow-latency (percentile latencies 95)
                        :errors (count-if #'server-error-p requests))))

(defun summarize-routes (requests)
  "Returns the summaries of the routes of REQUESTS, the most requested
first, and routes as often requested in the order of their names."
  (let ((summaries '())
        ;; Sorted by route, the requests of each route come together.
        (sorted (stable-sort (copy-list requests) #'string< :key #'request-route)))
    (loop while sorted
          do (let* ((route (request-route (first sorted)))
                    (end (position route sorted :key #'request-route :test-not #'string=)))
               (push (summarize-route route (subseq sorted 0 end)) summaries)
               (setf sorted (and end (nthcdr end sorted)))))
    (sort summaries (lambda (a b)
                      (or (> (route-summary-requests a) (route-summary-requests b))
                          (and (= (route-summary-requests a) (route-summary-requests b))
                               (string< (route-summary-route a) (route-summary-route b))))))))

(defun summarize (requests)
  "Returns the summary of REQUESTS, the requests of a month."
  (let* ((days (loop for (day . requests) in (requests-by-day requests)
                     collect (summarize-day day requests)))
         ;; For each visitor, on how many days it came.
         (visitors (count-by #'identity (loop for day in days
                                              append (day-summary-visitors day))))
         (hours (count-by (lambda (request) (subseq (request-time request) 0 13))
                          requests)))
    (make-month-summary
     :days days
     :requests (length requests)
     :visitors (length visitors)
     :returning (count-if (lambda (entry) (> (cdr entry) 1)) visitors)
     :busiest-hour (first (most-common hours 1))
     :routes (summarize-routes requests))))

(defun write-report (summary stream)
  "Writes the report of SUMMARY, a month's, to STREAM."
  (let ((days (month-summary-days summary)))
    (format stream "Access report ~A to ~A~%~%"
            (day-summary-day (first days))
            (day-summary-day (car (last days))))
    (format stream "~A requests from ~A visitors, ~A of whom came on more than one day.~%"
            (format-count (month-summary-requests summary))
            (format-count (month-summary-visitors summary))
            (format-count (month-summary-returning summary)))
    (destructuring-bind (hour . count) (month-summary-busiest-hour summary)
      (format stream "The busiest hour was ~A ~A:00, with ~A requests.~%~%"
              (subseq hour 0 10) (subseq hour 11 13) (format-count count)))
    (format stream "~10A ~9@A ~9@A ~9@A ~7@A ~7@A ~7@A ~6@A  ~A~%"
            "Day" "Requests" "Visitors" "Sessions" "Bounce" "p50 ms" "p95 ms" "5xx ‰"
            "Top routes")
    (dolist (day days)
      (format stream "~10A ~9@A ~9@A ~9@A ~6@A% ~7D ~7D ~6@A  ~{~A~^, ~}~%"
              (day-summary-day day)
              (format-count (day-summary-requests day))
              (format-count (length (day-summary-visitors day)))
              (format-count (day-summary-sessions day))
              (format-tenths (percent-tenths (day-summary-bounces day)
                                             (day-summary-sessions day)))
              (day-summary-median-latency day)
              (day-summary-slow-latency day)
              (format-tenths (per-mille (day-summary-errors day) (day-summary-requests day)))
              (loop for (route . count) in (day-summary-top-routes day)
                    collect (format nil "~A ~A" route (format-count count)))))
    (format stream "~%~24A ~9@A ~7@A ~7@A ~6@A~%" "Route" "Requests" "p50 ms" "p95 ms" "5xx ‰")
    (dolist (route (month-summary-routes summary))
      (format stream "~24A ~9@A ~7D ~7D ~6@A~%"
              (route-summary-route route)
              (format-count (route-summary-requests route))
              (route-summary-median-latency route)
              (route-summary-slow-latency route)
              (format-tenths (per-mille (route-summary-errors route)
                                        (route-summary-requests route)))))))

(defun monthly-report (requests)
  "Returns the report of REQUESTS, the requests of a month, as a string."
  (with-output-to-string (stream)
    (write-report (summarize requests) stream)))
