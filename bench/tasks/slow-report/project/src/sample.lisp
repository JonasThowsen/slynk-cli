(in-package #:logsum)

;;; Sample logs with the shape of the shop's real ones, for development
;;; and demonstrations: the real logs have customers' addresses in them
;;; and do not leave the servers. The same seed gives the same log.
;;;
;;; Each day some of the visitors come, the regular ones more often; a
;;; visitor comes once, twice or three times a day, mostly at lunch and in
;;; the evening, and looks at a few pages each time, or only one. The
;;; merged logs of the web servers are nearly, not quite, in time order.

(defparameter *sample-visitor-count* 12000
  "The number of visitors, IP addresses, in the sample.")

(defparameter *sample-product-count* 2000
  "The number of products in the sample shop.")

(defparameter *hour-weights*
  #(1 1 1 1 1 2 4 8 10 10 11 12 16 14 11 10 10 11 13 16 18 15 8 3)
  "How likely a visit starts in each hour of the day, relatively.")

(defparameter *sample-agents*
  #("Mozilla/5.0 (Windows NT 10.0; Win64; x64) Firefox/131.0"
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_6) Safari/605.1.15"
    "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) Mobile/15E148"
    "Mozilla/5.0 (Linux; Android 14; Pixel 8) Chrome/130.0 Mobile"
    "Mozilla/5.0 (X11; Linux x86_64) Chrome/130.0"
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Edg/130.0"))

(defparameter *sample-referrers*
  '((40 . "-")
    (30 . "https://www.google.com/")
    (10 . "https://www.bing.com/")
    (12 . "https://mail.example.org/")
    (8 . "https://www.facebook.com/")))

(defparameter *sample-words*
  #("sokker" "regnjakke" "ullgenser" "termos" "sekk" "lue" "votter" "telt"
    "sovepose" "ski" "staver" "hodelykt" "kart" "kompass" "støvler"))

(defun percent-encode (string)
  "Returns STRING as a path writes it: the UTF-8 octets of each character
that is not an ASCII letter or digit as %XX."
  (with-output-to-string (out)
    (loop for octet across (sb-ext:string-to-octets string :external-format :utf-8)
          for char = (code-char octet)
          do (if (and (< octet 128) (alphanumericp char))
                 (write-char char out)
                 (format out "%~2,'0X" octet)))))

(defun sample-visitors (generator)
  "Returns a vector of the visitors' IP addresses, all different."
  (let ((visitors (make-array *sample-visitor-count*)))
    (dotimes (i *sample-visitor-count* visitors)
      (setf (aref visitors i)
            (format nil "~D.~D.~D.~D"
                    (+ 62 (mod i 150)) (mod (floor i 150) 256)
                    (next-below generator 256) (next-between generator 1 254))))))

(defun sample-paths (prefix count)
  "Returns a vector of COUNT paths, PREFIX followed by an id."
  (let ((paths (make-array count)))
    (dotimes (i count paths)
      (setf (aref paths i) (format nil "~A~D" prefix (+ 1001 i))))))

(defstruct (shop (:constructor make-shop (generator)))
  generator
  (visitors (sample-visitors generator))
  (products (sample-paths "/products/" *sample-product-count*))
  (stock (sample-paths "/api/stock/" *sample-product-count*)))

(defun landing-path (shop)
  "Returns the path of the first request of a visit."
  (let ((generator (shop-generator shop)))
    (pick-weighted generator
                   `((40 . "/")
                     (35 . ,(pick generator (shop-products shop)))
                     (15 . ,(format nil "/search?q=~A" (pick generator *sample-words*)))
                     (8 . "/campaign/spring")
                     ;; as the newsletter links it
                     (2 . "/Campaign/Spring/")))))

(defun next-path (shop)
  "Returns the path of a request after the first of a visit."
  (let ((generator (shop-generator shop)))
    (pick-weighted generator
                   `((30 . ,(pick generator (shop-products shop)))
                     (20 . ,(pick generator (shop-stock shop)))
                     (15 . ,(pick generator #("/static/app.js?v=12" "/static/site.css?v=12"
                                              "/static/logo.svg" "/static/fonts/inter.woff2")))
                     (10 . ,(format nil "/search?q=~A" (pick generator *sample-words*)))
                     (6 . ,(format nil "/kategori/~A" (percent-encode (pick generator *sample-words*))))
                     (8 . "/cart")
                     (4 . "/checkout")
                     (5 . ,(format nil "/account/orders/~D" (next-between generator 100000 999999)))
                     (8 . "/")))))

(defun sample-latency (generator route-path)
  "Returns how many milliseconds a request of ROUTE-PATH took."
  (let ((base (cond ((eql 0 (search "/static/" route-path)) (next-between generator 1 15))
                    ((eql 0 (search "/api/" route-path)) (next-between generator 8 60))
                    ((eql 0 (search "/search" route-path)) (next-between generator 90 600))
                    ((string= route-path "/checkout") (next-between generator 200 900))
                    (t (next-between generator 35 220)))))
    (if (chance generator 3)
        (+ base (next-between generator 400 2500))
        base)))

(defun sample-status (generator path day hour)
  "Returns the status of a request of PATH at HOUR of DAY, mostly 200."
  (cond ((and (= (mod day 30) 13) (= hour 20) (chance generator 5)) 503)
        ((< (next-below generator 1000) 3) 500)
        ((eql 0 (search "/static/" path)) (if (chance generator 40) 304 200))
        ((and (eql 0 (search "/products/" path)) (chance generator 2)) 404)
        (t 200)))

(defun sample-visit (shop visitor agent day start)
  "Returns the requests of one visit of VISITOR from START, a second of
DAY, as (seconds . request), and the second of its last request."
  (let* ((generator (shop-generator shop))
         (count (if (chance generator 35) 1 (+ 2 (next-below generator 9))))
         (referrer (pick-weighted generator *sample-referrers*))
         (time start)
         (requests '()))
    (dotimes (i count)
      ;; The logs are rotated at midnight; a visit going on past it is cut.
      (when (>= time (* (1+ day) 86400))
        (return))
      (let* ((path (if (zerop i) (landing-path shop) (next-path shop)))
             (hour (floor (mod time 86400) 3600))
             (status (sample-status generator path day hour)))
        (push (cons time
                    (make-request :time (format-timestamp time) :ip visitor
                                  :method (if (string= path "/checkout") "POST" "GET")
                                  :path path :status status
                                  :bytes (if (= status 304) 0 (next-between generator 300 90000))
                                  :latency (sample-latency generator path)
                                  :agent agent
                                  :referrer (if (zerop i) referrer "https://shop.example/")))
              requests)
        (incf time (next-between generator 3 240))))
    requests))

(defun sample-day (shop day visitors)
  "Returns the requests of DAY, when about VISITORS visitors come, by time."
  (let* ((generator (shop-generator shop))
         (hours (loop for weight across *hour-weights*
                      for hour from 0
                      collect (cons weight hour)))
         (requests '()))
    (dotimes (i visitors)
      ;; The regular visitors, at the start of the vector, come more often.
      (let* ((index (next-below generator (next-between generator 1 (length (shop-visitors shop)))))
             (visitor (aref (shop-visitors shop) index))
             (agent (aref *sample-agents* (mod index (length *sample-agents*)))))
        (dotimes (visit (pick-weighted generator '((45 . 1) (35 . 2) (20 . 3))))
          (let ((start (+ (* day 86400)
                          (* 3600 (pick-weighted generator hours))
                          (next-below generator 3600))))
            (setf requests (nconc (sample-visit shop visitor agent day start) requests))))))
    (let ((sorted (map 'vector #'cdr (sort requests #'< :key #'car))))
      ;; Requests a second or two apart may be logged by different servers
      ;; in the other order.
      (loop for i from 1 below (length sorted)
            when (chance generator 10)
              do (rotatef (aref sorted (1- i)) (aref sorted i)))
      (coerce sorted 'list))))

(defun make-sample-log (&key (seed 1) (start "2026-03-01") (days 30) (visitors 3600))
  "Returns the requests of a sample log of DAYS days from START, when
about VISITORS visitors come on a weekday, in the order of the log."
  (let ((shop (make-shop (make-generator seed)))
        (first-day (timestamp-day (format nil "~AT00:00:00" start))))
    (loop for day from first-day below (+ first-day days)
          ;; Fewer come at the weekend; 2000-01-01 was a Saturday.
          for weekday = (mod (+ day 5) 7)
          nconc (sample-day shop day (if (>= weekday 5)
                                         (floor (* visitors 3) 4)
                                         visitors)))))

(defun write-sample-log (stream &rest options)
  "Writes the sample log MAKE-SAMPLE-LOG makes with OPTIONS to STREAM."
  (dolist (request (apply #'make-sample-log options))
    (format-log-line request stream)))
