(in-package #:timesheet/tests)

(def-suite* dates :in timesheet)

(test round-trip
  (dolist (string '("1970-01-01" "2000-02-29" "2026-03-02" "1999-12-31" "2400-02-29"))
    (is (string= string (format-date (d string))))))

(test fields
  (let ((date (d "2024-02-29")))
    (is (= 2024 (date-year date)))
    (is (= 2 (date-month date)))
    (is (= 29 (date-day date)))))

(test day-numbers
  (is (= 0 (date-day-number (d "1970-01-01"))))
  (is (= 365 (date-day-number (d "1971-01-01"))))
  (is (= -1 (date-day-number (d "1969-12-31")))))

(test weekdays
  ;; 2026-03-02 is a Monday, 2026-03-08 a Sunday.
  (is (= 0 (date-weekday (d "2026-03-02"))))
  (is (= 6 (date-weekday (d "2026-03-08"))))
  (is (= 3 (date-weekday (d "1970-01-01")))))

(test week-start
  (is (date= (d "2026-03-02") (week-start (d "2026-03-02"))))
  (is (date= (d "2026-03-02") (week-start (d "2026-03-08"))))
  (is (date= (d "2026-02-23") (week-start (d "2026-03-01")))))

(test arithmetic
  (is (date= (d "2026-03-01") (date+ (d "2026-02-28") 1)))
  (is (date= (d "2024-02-29") (date+ (d "2024-02-28") 1)))
  (is (date< (d "2026-03-01") (d "2026-03-02")))
  (is (date<= (d "2026-03-02") (d "2026-03-02"))))

(test invalid-dates
  (signals error (make-date 2026 2 29))
  (signals error (make-date 2026 13 1))
  (signals error (parse-date "2026-3-2"))
  (signals error (parse-date "yesterday")))
