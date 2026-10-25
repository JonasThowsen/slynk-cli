(in-package #:tally)

;;; Days are integers: the number of days since 1970-01-01. The
;;; conversions are Howard Hinnant's days_from_civil and civil_from_days,
;;; which are exact for the proleptic Gregorian calendar.

(defun days-from-civil (year month day)
  "Returns the day number of the date YEAR-MONTH-DAY."
  (let* ((y (if (<= month 2) (1- year) year))
         (era (floor y 400))
         (year-of-era (- y (* era 400)))
         (day-of-year (+ (floor (+ (* 153 (+ month (if (> month 2) -3 9))) 2) 5)
                         (1- day)))
         (day-of-era (+ (* year-of-era 365)
                        (floor year-of-era 4)
                        (- (floor year-of-era 100))
                        day-of-year)))
    (+ (* era 146097) day-of-era -719468)))

(defun civil-from-days (days)
  "Returns the year, month and day of the day number DAYS as three values."
  (let* ((z (+ days 719468))
         (era (floor z 146097))
         (day-of-era (- z (* era 146097)))
         (year-of-era (floor (+ day-of-era
                                (- (floor day-of-era 1460))
                                (floor day-of-era 36524)
                                (- (floor day-of-era 146096)))
                             365))
         (day-of-year (- day-of-era
                         (+ (* 365 year-of-era)
                            (floor year-of-era 4)
                            (- (floor year-of-era 100)))))
         (shifted-month (floor (+ (* 5 day-of-year) 2) 153))
         (day (1+ (- day-of-year (floor (+ (* 153 shifted-month) 2) 5))))
         (month (if (< shifted-month 10) (+ shifted-month 3) (- shifted-month 9)))
         (year (+ year-of-era (* era 400))))
    (values (if (<= month 2) (1+ year) year) month day)))

(defun parse-date (date &key (start 0) end)
  "Returns the day number of the ISO date (YYYY-MM-DD) in the string DATE
between START and END. A day number is returned as it is, so that every
query accepts either."
  (when (integerp date)
    (return-from parse-date date))
  (let ((end (or end (length date))))
    (flet ((field (from to)
             (parse-integer date :start (+ start from) :end (+ start to))))
      (unless (and (= (- end start) 10)
                   (char= (char date (+ start 4)) #\-)
                   (char= (char date (+ start 7)) #\-))
        (error "~S is not a date of the form YYYY-MM-DD." (subseq date start end)))
      (days-from-civil (field 0 4) (field 5 7) (field 8 10)))))

(defun parse-time-of-day (string &key (start 0) (end (length string)))
  "Returns the number of seconds since midnight of the time (HH:MM:SS) in
STRING between START and END."
  (flet ((field (from to)
           (parse-integer string :start (+ start from) :end (+ start to))))
    (unless (and (= (- end start) 8)
                 (char= (char string (+ start 2)) #\:)
                 (char= (char string (+ start 5)) #\:))
      (error "~S is not a time of the form HH:MM:SS." (subseq string start end)))
    (+ (* 3600 (field 0 2)) (* 60 (field 3 5)) (field 6 8))))

(defun parse-timestamp (string &key (start 0) (end (length string)))
  "Returns the day number and the seconds since midnight of the ISO
timestamp (YYYY-MM-DDTHH:MM:SS) in STRING between START and END."
  (unless (and (= (- end start) 19)
               (char= (char string (+ start 10)) #\T))
    (error "~S is not a timestamp of the form YYYY-MM-DDTHH:MM:SS."
           (subseq string start end)))
  (values (parse-date string :start start :end (+ start 10))
          (parse-time-of-day string :start (+ start 11) :end end)))

(defun format-date (day)
  "Returns the day number DAY as an ISO date string."
  (multiple-value-bind (year month day-of-month) (civil-from-days day)
    (format nil "~4,'0D-~2,'0D-~2,'0D" year month day-of-month)))
