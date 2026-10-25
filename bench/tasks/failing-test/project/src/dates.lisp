;;;; dates.lisp
;;;;
;;;; A date is an integer: the number of days since 1900-01-01, the epoch
;;;; of universal time. That makes comparing dates and adding days plain
;;;; arithmetic; the calendar only matters when a date is made or shown.

(in-package #:billing)

(defconstant +seconds-per-day+ 86400)

(defun make-date (year month day)
  "Returns the date of DAY in MONTH of YEAR."
  (values (floor (encode-universal-time 0 0 0 day month year 0)
                 +seconds-per-day+)))

(defun decode-date (date)
  "Returns the year, month and day of DATE as three values."
  (multiple-value-bind (second minute hour day month year)
      (decode-universal-time (* date +seconds-per-day+) 0)
    (declare (ignore second minute hour))
    (values year month day)))

(defun date-year (date) (nth-value 0 (decode-date date)))
(defun date-month (date) (nth-value 1 (decode-date date)))
(defun date-day (date) (nth-value 2 (decode-date date)))

(defun parse-date (string)
  "Parses an ISO 8601 calendar date, such as \"2026-03-01\"."
  (unless (and (= (length string) 10)
               (char= (char string 4) #\-)
               (char= (char string 7) #\-))
    (error "~S is not a date of the form YYYY-MM-DD." string))
  (make-date (parse-integer string :start 0 :end 4)
             (parse-integer string :start 5 :end 7)
             (parse-integer string :start 8 :end 10)))

(defun format-date (date &optional stream)
  "Writes DATE as YYYY-MM-DD to STREAM, or returns it as a string when
STREAM is NIL."
  (multiple-value-bind (year month day) (decode-date date)
    (format stream "~4,'0D-~2,'0D-~2,'0D" year month day)))

(defun add-days (date days)
  "Returns the date DAYS days after DATE."
  (+ date days))

(defun weekday (date)
  "Returns DATE's day of the week, 0 for Monday to 6 for Sunday."
  ;; Day 0, 1900-01-01, was a Monday.
  (mod date 7))

(defun leap-year-p (year)
  (and (zerop (mod year 4))
       (or (plusp (mod year 100))
           (zerop (mod year 400)))))

(defun days-in-month (month year)
  "Returns the number of days in MONTH of YEAR."
  (if (and (= month 2) (leap-year-p year))
      29
      (svref #(31 28 31 30 31 30 31 31 30 31 30 31) (1- month))))

(defun end-of-month (date)
  "Returns the last day of DATE's month."
  (multiple-value-bind (year month) (decode-date date)
    (make-date year month (days-in-month month year))))
