(defpackage #:logsum/tests
  (:use #:common-lisp #:logsum #:fiveam))

(in-package #:logsum/tests)

(def-suite :logsum :description "Tests for logsum.")
(in-suite :logsum)

(defun line (time ip path &key (status 200) (latency 100) (method "GET"))
  (format nil "~A~C~A~C~A~C~A~C~D~C~D~C~D~C~A~C~A"
          time #\Tab ip #\Tab method #\Tab path #\Tab status #\Tab 512 #\Tab latency #\Tab
          "Mozilla/5.0" #\Tab "-"))

(defun requests (&rest lines)
  (with-input-from-string (stream (format nil "~{~A~%~}" lines))
    (read-log stream)))

(test timestamps
  (is (= 0 (parse-timestamp "2000-01-01T00:00:00")))
  (is (= 86399 (parse-timestamp "2000-01-01T23:59:59")))
  (is (= (+ (* 9569 86400) (* 9 3600) (* 15 60) 27) (parse-timestamp "2026-03-14T09:15:27")))
  (is (string= "2026-03-14T09:15:27" (format-timestamp (parse-timestamp "2026-03-14T09:15:27"))))
  (is (string= "2024-02-29" (day-string (timestamp-day "2024-02-29T12:00:00"))))
  (is (= 1 (- (timestamp-day "2024-03-01T00:00:00") (timestamp-day "2024-02-29T23:59:59"))))
  (is (= 9 (timestamp-hour "2026-03-14T09:15:27")))
  (loop for seconds from -100000000 to 1000000000 by 7777777
        do (is (= seconds (parse-timestamp (format-timestamp seconds)))))
  (signals error (parse-timestamp "2026-03-14 09:15:27"))
  (signals error (parse-timestamp "2026-13-14T09:15:27")))

(test parse-log-line
  (let ((request (parse-log-line (line "2026-03-14T09:15:27" "62.1.2.3" "/cart" :status 503 :latency 840))))
    (is (string= "2026-03-14T09:15:27" (request-time request)))
    (is (string= "62.1.2.3" (request-ip request)))
    (is (string= "/cart" (request-path request)))
    (is (= 503 (request-status request)))
    (is (= 840 (request-latency request)))
    (is (= (parse-timestamp "2026-03-14T09:15:27") (request-seconds request))))
  (signals malformed-log-line (parse-log-line "2026-03-14T09:15:27	62.1.2.3	GET"))
  (signals malformed-log-line (parse-log-line (line "2026-03-14 09:15:27" "62.1.2.3" "/")))
  (signals malformed-log-line (parse-log-line (line "2026-03-14T09:15:27" "62.1.2.3" "/" :status 999)))
  (let ((request (parse-log-line (line "2026-03-14T09:15:27" "62.1.2.3" "/search?q=telt"))))
    (is (string= (with-output-to-string (out) (format-log-line request out))
                 (format nil "~A~%" (line "2026-03-14T09:15:27" "62.1.2.3" "/search?q=telt"))))))

(test routes
  (is (string= "/" (route-of "/")))
  (is (string= "/" (route-of "/?utm_source=mail")))
  (is (string= "/products/:id" (route-of "/products/1234")))
  (is (string= "/products/:id" (route-of "/products/1234?ref=mail")))
  (is (string= "/account/orders/:id" (route-of "/account/orders/481516")))
  (is (string= "/static/*" (route-of "/static/fonts/inter.woff2")))
  (is (string= "/campaign/spring" (route-of "/Campaign/Spring/")))
  (is (string= "/kategori/støvler" (route-of "/kategori/st%C3%B8vler")))
  (is (string= "/search" (route-of "/search?q=sokker"))))

(test count-by
  (is (equal '(("b" . 2) ("a" . 1) ("c" . 3))
             (count-by #'identity '("b" "a" "c" "b" "c" "c"))))
  (is (equal '((2 . 2) (1 . 2) (3 . 1)) (count-by #'length '("ab" "c" "de" "f" "ghi"))))
  (is (null (count-by #'identity '()))))

(test percentile
  (is (= 1 (percentile '(1) 50)))
  (is (= 3 (percentile '(5 1 4 2 3) 50)))
  (is (= 20 (percentile '(15 20 35 40 50) 30)))
  (is (= 50 (percentile #(15 20 35 40 50) 95)))
  (let ((numbers (list 3 1 2)))
    (percentile numbers 50)
    (is (equal '(3 1 2) numbers))))

(test sessions
  (let ((sessions (sessionize
                   (requests (line "2026-03-14T10:10:00" "62.1.1.1" "/cart")
                             (line "2026-03-14T10:00:00" "62.1.1.1" "/")
                             (line "2026-03-14T10:05:00" "62.2.2.2" "/")
                             (line "2026-03-14T10:39:59" "62.1.1.1" "/checkout")
                             (line "2026-03-14T11:10:00" "62.1.1.1" "/")
                             (line "2026-03-14T10:00:00" "62.0.0.9" "/")))))
    (is (equal '(("62.0.0.9" 1) ("62.1.1.1" 3) ("62.2.2.2" 1) ("62.1.1.1" 1))
               (mapcar (lambda (session) (list (session-ip session) (session-requests session)))
                       sessions)))
    (is (= (parse-timestamp "2026-03-14T10:39:59") (session-end (second sessions))))))

(test summarize-day
  (let ((day (summarize-day "2026-03-14"
                            (requests (line "2026-03-14T10:00:00" "62.1.1.1" "/products/1" :latency 50)
                                      (line "2026-03-14T10:01:00" "62.1.1.1" "/products/2" :latency 70)
                                      (line "2026-03-14T10:02:00" "62.1.1.1" "/cart" :latency 90 :status 500)
                                      (line "2026-03-14T12:00:00" "62.2.2.2" "/" :latency 300)))))
    (is (= 4 (logsum::day-summary-requests day)))
    (is (equal '("62.1.1.1" "62.2.2.2") (logsum::day-summary-visitors day)))
    (is (= 2 (logsum::day-summary-sessions day)))
    (is (= 1 (logsum::day-summary-bounces day)))
    (is (= 70 (logsum::day-summary-median-latency day)))
    (is (= 300 (logsum::day-summary-slow-latency day)))
    (is (= 1 (logsum::day-summary-errors day)))
    (is (equal '(("/products/:id" . 2) ("/" . 1) ("/cart" . 1))
               (logsum::day-summary-top-routes day)))))

(test small-report
  (let* ((log (make-sample-log :seed 3 :days 3 :visitors 60))
         (report (monthly-report log))
         (lines (with-input-from-string (in report)
                  (loop for line = (read-line in nil) while line collect line))))
    (is (string= "Access report 2026-03-01 to 2026-03-03" (first lines)))
    (is (search (format nil "~:D requests from" (length log)) report))
    ;; A day's line for each day, and the routes after.
    (is (= 3 (count-if (lambda (line) (eql 0 (search "2026-03-0" line))) lines)))
    (is (find "/products/:id" lines :test (lambda (route line) (eql 0 (search route line)))))
    ;; The same report from the log written and read back.
    (is (string= report
                 (monthly-report
                  (with-input-from-string (in (with-output-to-string (out)
                                                (write-sample-log out :seed 3 :days 3 :visitors 60)))
                    (read-log in)))))))

(test sample-is-reproducible
  (flet ((sample () (make-sample-log :seed 7 :days 2 :visitors 30)))
    (let ((a (sample))
          (b (sample)))
      (is (plusp (length a)))
      (is (equalp a b)))))
