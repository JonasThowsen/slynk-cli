(in-package #:logsum)

;;; Times in the logs are written as 2026-03-14T09:15:27, in UTC. Inside,
;;; a time is a number of seconds since 2000-01-01T00:00:00, and a day the
;;; number of days since 2000-01-01.

(defun days-from-civil (year month day)
  "Returns the number of days from 2000-01-01 to YEAR-MONTH-DAY, in the
proleptic Gregorian calendar."
  ;; Howard Hinnant's days_from_civil, shifted to 2000-01-01.
  (let* ((year (if (<= month 2) (1- year) year))
         (era (floor year 400))
         (year-of-era (- year (* era 400)))
         (day-of-year (+ (floor (+ (* 153 (+ month (if (> month 2) -3 9))) 2) 5)
                         (1- day)))
         (day-of-era (+ (* year-of-era 365) (floor year-of-era 4)
                        (- (floor year-of-era 100)) day-of-year)))
    (- (+ (* era 146097) day-of-era) 730425)))

(defun civil-from-days (days)
  "Returns the year, month and day of the day DAYS days after 2000-01-01."
  (let* ((z (+ days 730425))
         (era (floor z 146097))
         (day-of-era (- z (* era 146097)))
         (year-of-era (floor (- day-of-era
                                (floor day-of-era 1460)
                                (- (floor day-of-era 36524))
                                (floor day-of-era 146096))
                             365))
         (day-of-year (- day-of-era
                         (+ (* 365 year-of-era) (floor year-of-era 4)
                            (- (floor year-of-era 100)))))
         (mp (floor (+ (* 5 day-of-year) 2) 153))
         (day (1+ (- day-of-year (floor (+ (* 153 mp) 2) 5))))
         (month (if (< mp 10) (+ mp 3) (- mp 9))))
    (values (+ year-of-era (* era 400) (if (<= month 2) 1 0)) month day)))

(defun timestamp-shape-p (string)
  "True when STRING has the shape of a timestamp, digits and separators."
  (and (= (length string) 19)
       (loop for char across string
             for index from 0
             always (case index
                      ((4 7) (char= char #\-))
                      (10 (char= char #\T))
                      ((13 16) (char= char #\:))
                      (t (digit-char-p char))))))

(defun parse-timestamp (string)
  "Returns the time STRING writes, as 2026-03-14T09:15:27, in seconds."
  (unless (timestamp-shape-p string)
    (error "Not a timestamp: ~S" string))
  (flet ((field (start end) (parse-integer string :start start :end end)))
    (let ((month (field 5 7))
          (day (field 8 10))
          (hour (field 11 13))
          (minute (field 14 16))
          (second (field 17 19)))
      (unless (and (<= 1 month 12) (<= 1 day 31) (< hour 24) (< minute 60) (< second 60))
        (error "Not a timestamp: ~S" string))
      (+ (* (days-from-civil (field 0 4) month day) 86400)
         (* hour 3600) (* minute 60) second))))

(defun day-string (day)
  "Returns the day DAY as 2026-03-14."
  (multiple-value-bind (year month date) (civil-from-days day)
    (format nil "~4,'0D-~2,'0D-~2,'0D" year month date)))

(defun format-timestamp (seconds)
  "Returns the time SECONDS as 2026-03-14T09:15:27."
  (multiple-value-bind (day rest) (floor seconds 86400)
    (multiple-value-bind (hour rest) (floor rest 3600)
      (multiple-value-bind (minute second) (floor rest 60)
        (format nil "~AT~2,'0D:~2,'0D:~2,'0D" (day-string day) hour minute second)))))

(defun timestamp-day (string)
  "Returns the day of the timestamp STRING."
  (floor (parse-timestamp string) 86400))

(defun timestamp-hour (string)
  "Returns the hour of the day, from 0 to 23, of the timestamp STRING."
  (parse-integer string :start 11 :end 13))
