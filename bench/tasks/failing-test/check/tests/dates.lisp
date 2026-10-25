;;;; tests/dates.lisp

(in-package #:billing-tests)

(def-suite dates :in billing)
(in-suite dates)

(test parse-and-format-round-trip
  (dolist (string '("2026-03-01" "2024-02-29" "1999-12-31" "2000-01-01"))
    (is (string= string (format-date (parse-date string))))))

(test parse-date-rejects-other-forms
  (signals error (parse-date "1.3.2026"))
  (signals error (parse-date "2026-3-1")))

(test date-parts
  (let ((date (parse-date "2026-10-25")))
    (is (= 2026 (date-year date)))
    (is (= 10 (date-month date)))
    (is (= 25 (date-day date)))))

(test weekday-known-dates
  (is (= 6 (weekday (parse-date "2026-10-25"))))   ; a Sunday
  (is (= 0 (weekday (parse-date "2026-10-26"))))   ; a Monday
  (is (= 1 (weekday (parse-date "2000-02-29")))))  ; a Tuesday

(test days-in-month-leap-years
  (is (= 29 (days-in-month 2 2024)))
  (is (= 28 (days-in-month 2 2026)))
  (is (= 28 (days-in-month 2 1900)))
  (is (= 29 (days-in-month 2 2000)))
  (is (= 31 (days-in-month 12 2026))))

(test end-of-month
  (is (string= "2026-02-28" (format-date (end-of-month (parse-date "2026-02-10")))))
  (is (string= "2024-02-29" (format-date (end-of-month (parse-date "2024-02-29")))))
  (is (string= "2026-12-31" (format-date (end-of-month (parse-date "2026-12-01"))))))
