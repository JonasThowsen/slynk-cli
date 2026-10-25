(in-package #:timesheet/tests)

(def-suite* payroll :in timesheet)

(defun alice-entries (&rest lines)
  (employee-entries (apply #'sheet lines) "alice"))

(test weekly-overtime
  ;; Five days of 9 hours: 45 hours in the week, 5 of them overtime.
  (multiple-value-bind (regular overtime)
      (split-hours (alice-entries "2026-03-02,alice,9,apollo"
                                  "2026-03-03,alice,9,apollo"
                                  "2026-03-04,alice,9,apollo"
                                  "2026-03-05,alice,9,apollo"
                                  "2026-03-06,alice,9,apollo")
                   (make-pay-rules))
    (is (= 40 regular))
    (is (= 5 overtime))))

(test weeks-are-separate
  ;; 30 hours on Thursday to Sunday and 30 on Monday to Wednesday of
  ;; the next week: no overtime.
  (multiple-value-bind (regular overtime)
      (split-hours (alice-entries "2026-03-05,alice,8,apollo"
                                  "2026-03-06,alice,8,apollo"
                                  "2026-03-07,alice,7,apollo"
                                  "2026-03-08,alice,7,apollo"
                                  "2026-03-09,alice,10,apollo"
                                  "2026-03-10,alice,10,apollo"
                                  "2026-03-11,alice,10,apollo")
                   (make-pay-rules))
    (is (= 60 regular))
    (is (= 0 overtime))))

(test daily-overtime
  ;; Two entries on Monday make 10 hours; with an 8-hour day, 2 are
  ;; overtime.
  (multiple-value-bind (regular overtime)
      (split-hours (alice-entries "2026-03-02,alice,6,apollo"
                                  "2026-03-02,alice,4,zeus"
                                  "2026-03-03,alice,7.5,apollo")
                   (make-pay-rules :daily-threshold 8))
    (is (= 31/2 regular))
    (is (= 2 overtime))))

(test daily-and-weekly-overtime
  ;; Daily overtime does not count towards the week: 4 days of 10
  ;; hours and 9 hours on Friday is 8 daily overtime hours and 41
  ;; others, of which 1 more is overtime.
  (multiple-value-bind (regular overtime)
      (split-hours (alice-entries "2026-03-02,alice,10,apollo"
                                  "2026-03-03,alice,10,apollo"
                                  "2026-03-04,alice,10,apollo"
                                  "2026-03-05,alice,10,apollo"
                                  "2026-03-06,alice,9,apollo")
                   (make-pay-rules :daily-threshold 8))
    (is (= 40 regular))
    (is (= 9 overtime))))

(test hourly-pay
  (let ((line (compute-pay (hourly "alice" "Alice Berg" 2000)
                           (alice-entries "2026-03-02,alice,12,apollo"
                                          "2026-03-03,alice,12,apollo"
                                          "2026-03-04,alice,12,apollo"
                                          "2026-03-05,alice,8,apollo")
                           (make-pay-rules))))
    (is (string= "alice" (pay-line-employee-id line)))
    (is (= 40 (pay-line-regular-hours line)))
    (is (= 4 (pay-line-overtime-hours line)))
    ;; 40 x 20.00 + 4 x 30.00
    (is (= 92000 (pay-line-gross line)))))

(test contractor-pay
  (let ((line (compute-pay (make-instance 'contractor :id "carl" :name "Carl Dahl"
                                                      :hourly-rate 5000)
                           (employee-entries (sheet "2026-03-02,carl,12,apollo"
                                                    "2026-03-03,carl,12,apollo"
                                                    "2026-03-04,carl,12,apollo"
                                                    "2026-03-05,carl,12,apollo")
                                             "carl")
                           (make-pay-rules))))
    (is (= 48 (pay-line-regular-hours line)))
    (is (= 0 (pay-line-overtime-hours line)))
    (is (= 240000 (pay-line-gross line)))))

(test salaried-pay
  (let ((line (compute-pay (make-instance 'salaried-employee :id "sara" :name "Sara Lie"
                                                             :annual-salary 6000000)
                           (employee-entries (sheet "2026-03-02,sara,12,apollo"
                                                    "2026-03-03,sara,10,apollo")
                                             "sara")
                           (make-pay-rules))))
    (is (= 22 (pay-line-regular-hours line)))
    (is (= 0 (pay-line-overtime-hours line)))
    (is (= 500000 (pay-line-gross line))))
  (is (= 230769 (pay-line-gross
                 (compute-pay (make-instance 'salaried-employee :id "sara" :name "Sara Lie"
                                                                :annual-salary 6000000)
                              '()
                              (make-pay-rules :periods-per-year 26))))))

(test run-payroll
  (let* ((roster (make-roster (hourly "bob" "Bob Moe" 3000)
                              (hourly "alice" "Alice Berg" 2000)))
         (timesheet (sheet "2026-02-27,alice,8,apollo"
                           "2026-03-02,alice,8,apollo"
                           "2026-03-02,bob,4,zeus"))
         (lines (run-payroll roster timesheet (d "2026-03-01") (d "2026-03-31"))))
    (is (equal '("alice" "bob") (mapcar #'pay-line-employee-id lines)))
    (is (equal '(16000 12000) (mapcar #'pay-line-gross lines)))
    (is (equal '(:regular-hours 12 :overtime-hours 0 :gross 28000)
               (payroll-totals lines)))
    (signals error (run-payroll roster timesheet (d "2026-03-31") (d "2026-03-01")))))

(test roster
  (let ((roster (make-roster (hourly "alice" "Alice Berg" 2000))))
    (is (string= "Alice Berg" (employee-name (find-employee roster "alice"))))
    (is (null (find-employee roster "nobody" :errorp nil)))
    (signals error (find-employee roster "nobody"))
    (signals error (add-employee roster (hourly "alice" "Alice Again" 2000)))))
