(in-package #:timesheet)

;;; A date is a day in the proleptic Gregorian calendar, kept as the
;;; number of days since 1970-01-01. Day numbers make the arithmetic
;;; and the hash keys trivial; the calendar fields are computed when
;;; they are asked for.

(defstruct (date (:constructor %make-date (day-number)))
  (day-number 0 :type integer :read-only t))

(defmethod print-object ((date date) stream)
  (if *print-readably*
      (call-next-method)
      (print-unreadable-object (date stream :type t)
        (write-string (format-date date) stream))))

(defun days-from-civil (year month day)
  "Returns the number of days from 1970-01-01 to YEAR-MONTH-DAY."
  ;; Howard Hinnant's algorithm: count in 400-year eras of years that
  ;; start on the first of March, so the leap day comes last.
  (let* ((y (if (<= month 2) (1- year) year))
         (era (floor y 400))
         (year-of-era (- y (* era 400)))
         (month-from-march (mod (+ month 9) 12))
         (day-of-year (+ (floor (+ (* 153 month-from-march) 2) 5) (1- day)))
         (day-of-era (+ (* year-of-era 365)
                        (floor year-of-era 4)
                        (- (floor year-of-era 100))
                        day-of-year)))
    (+ (* era 146097) day-of-era -719468)))

(defun civil-from-days (day-number)
  "Returns the year, month and day of DAY-NUMBER days after 1970-01-01."
  (let* ((z (+ day-number 719468))
         (era (floor z 146097))
         (day-of-era (- z (* era 146097)))
         (year-of-era (floor (- (+ (- day-of-era (floor day-of-era 1460))
                                   (floor day-of-era 36524))
                                (floor day-of-era 146096))
                             365))
         (day-of-year (- day-of-era (- (+ (* 365 year-of-era) (floor year-of-era 4))
                                       (floor year-of-era 100))))
         (month-from-march (floor (+ (* 5 day-of-year) 2) 153))
         (day (1+ (- day-of-year (floor (+ (* 153 month-from-march) 2) 5))))
         (month (if (< month-from-march 10) (+ month-from-march 3) (- month-from-march 9)))
         (year (+ year-of-era (* era 400))))
    (values (if (<= month 2) (1+ year) year) month day)))

(defun leap-year-p (year)
  (and (zerop (mod year 4))
       (or (plusp (mod year 100)) (zerop (mod year 400)))))

(defun days-in-month (year month)
  (case month
    (2 (if (leap-year-p year) 29 28))
    ((4 6 9 11) 30)
    (t 31)))

(defun make-date (year month day)
  "Returns the date YEAR-MONTH-DAY, checking that it exists."
  (unless (and (integerp year) (integerp month) (integerp day)
               (<= 1 month 12)
               (<= 1 day (days-in-month year month)))
    (error "There is no date ~A-~A-~A." year month day))
  (%make-date (days-from-civil year month day)))

(defun parse-date (string)
  "Parses an ISO date, YYYY-MM-DD, into a date."
  (let ((string (string-trim " " string)))
    (flet ((field (start end)
             (handler-case (parse-integer string :start start :end end)
               (error () (error "Not a date: ~S" string)))))
      (unless (and (= (length string) 10)
                   (char= (char string 4) #\-)
                   (char= (char string 7) #\-))
        (error "Not a date: ~S" string))
      (make-date (field 0 4) (field 5 7) (field 8 10)))))

(defun format-date (date)
  "Returns DATE as an ISO date string."
  (multiple-value-bind (year month day) (civil-from-days (date-day-number date))
    (format nil "~4,'0D-~2,'0D-~2,'0D" year month day)))

(defun date-year (date)
  (nth-value 0 (civil-from-days (date-day-number date))))

(defun date-month (date)
  (nth-value 1 (civil-from-days (date-day-number date))))

(defun date-day (date)
  (nth-value 2 (civil-from-days (date-day-number date))))

(defun date-weekday (date)
  "Returns the day of the week of DATE, 0 for Monday to 6 for Sunday."
  ;; 1970-01-01 was a Thursday.
  (mod (+ (date-day-number date) 3) 7))

(defun date+ (date days)
  "Returns the date DAYS days after DATE."
  (%make-date (+ (date-day-number date) days)))

(defun date= (a b)
  (= (date-day-number a) (date-day-number b)))

(defun date< (a b)
  (< (date-day-number a) (date-day-number b)))

(defun date<= (a b)
  (<= (date-day-number a) (date-day-number b)))

(defun week-start (date)
  "Returns the Monday of DATE's week. Weeks run from Monday to Sunday."
  (date+ date (- (date-weekday date))))
