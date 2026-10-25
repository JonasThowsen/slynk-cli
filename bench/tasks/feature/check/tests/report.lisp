(in-package #:timesheet-check)

(def-suite* report :in timesheet)

(test format-money
  (is (string= "0.00" (format-money 0)))
  (is (string= "0.05" (format-money 5)))
  (is (string= "1234.50" (format-money 123450)))
  (is (string= "-12.30" (format-money -1230))))

(test format-hours
  (is (string= "7.50" (format-hours 15/2)))
  (is (string= "0.33" (format-hours 1/3)))
  (is (string= "40.00" (format-hours 40))))

(test payroll-report
  (let* ((roster (make-roster (hourly "alice" "Alice Berg" 2000)
                              (make-instance 'contractor :id "carl" :name "Carl Dahl"
                                                         :hourly-rate 5000)))
         (timesheet (sheet "2026-03-02,alice,8,apollo"
                           "2026-03-02,carl,2.5,zeus"))
         (report (with-output-to-string (out)
                   (write-payroll-report
                    (run-payroll roster timesheet (d "2026-03-01") (d "2026-03-31"))
                    out))))
    (is (string= (format nil "~
Id       Name                   Regular  Overtime   Holiday       Gross
alice    Alice Berg                8.00      0.00      0.00      160.00
carl     Carl Dahl                 2.50      0.00      0.00      125.00
         Total                    10.50      0.00      0.00      285.00
")
                 report))))

(test project-hours
  (let ((timesheet (sheet "2026-03-02,alice,8,apollo"
                          "2026-03-02,bob,4,zeus"
                          "2026-03-03,bob,4,hermes"
                          "2026-03-03,alice,4,zeus"
                          "2026-04-01,alice,8,hermes")))
    (is (equal '(("apollo" . 8) ("zeus" . 8) ("hermes" . 4))
               (project-hours timesheet (d "2026-03-01") (d "2026-03-31"))))))
