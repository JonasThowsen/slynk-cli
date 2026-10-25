(in-package #:timesheet-check)

(def-suite* holidays :in timesheet)

(defun easter-calendar ()
  "Easter 2026: Maundy Thursday and Good Friday, 2 and 3 April."
  (let ((calendar (make-holiday-calendar)))
    (add-holiday calendar (d "2026-04-02") "Skjærtorsdag")
    (add-holiday calendar (d "2026-04-03") "Langfredag")
    calendar))

(test holiday-calendar
  (let ((calendar (make-holiday-calendar)))
    (is (null (holiday-name calendar (d "2026-05-17"))))
    (is (eq calendar (add-holiday calendar (d "2026-05-17") "Nasjonaldag")))
    (is (string= "Nasjonaldag" (holiday-name calendar (d "2026-05-17"))))
    (add-holiday calendar (d "2026-05-17") "Grunnlovsdag")
    (is (string= "Grunnlovsdag" (holiday-name calendar (d "2026-05-17"))))
    (is (null (holiday-name calendar (d "2026-05-18"))))))

(test holiday-rules-defaults
  (let ((rules (make-pay-rules)))
    (is (null (holidays rules)))
    (is (= 2 (holiday-multiplier rules)))))

(test holiday-hours-are-paid-apart
  ;; Monday to Wednesday 10 hours, Good Friday 10: 30 regular hours,
  ;; 10 holiday hours at double pay.
  (let ((line (compute-pay (hourly "alice" "Alice Berg" 2000)
                           (alice-entries "2026-03-30,alice,10,apollo"
                                          "2026-03-31,alice,10,apollo"
                                          "2026-04-01,alice,10,apollo"
                                          "2026-04-03,alice,10,apollo")
                           (make-pay-rules :holidays (easter-calendar)))))
    (is (= 30 (pay-line-regular-hours line)))
    (is (= 0 (pay-line-overtime-hours line)))
    (is (= 10 (pay-line-holiday-hours line)))
    (is (= 100000 (pay-line-gross line)))))

(test holiday-hours-do-not-count-towards-the-week
  ;; 44 hours from Monday to Wednesday and 8 on Maundy Thursday: the
  ;; 4 hours above 40 are overtime, the holiday hours are not.
  (let ((line (compute-pay (hourly "alice" "Alice Berg" 2000)
                           (alice-entries "2026-03-30,alice,15,apollo"
                                          "2026-03-31,alice,15,apollo"
                                          "2026-04-01,alice,14,apollo"
                                          "2026-04-02,alice,8,apollo")
                           (make-pay-rules :holidays (easter-calendar)))))
    (is (= 40 (pay-line-regular-hours line)))
    (is (= 4 (pay-line-overtime-hours line)))
    (is (= 8 (pay-line-holiday-hours line)))
    (is (= 124000 (pay-line-gross line)))))

(test holiday-hours-and-the-daily-threshold
  ;; 10 hours on a Monday and 10 on Good Friday with an 8-hour day
  ;; and pay and a half on holidays.
  (let ((line (compute-pay (hourly "alice" "Alice Berg" 2000)
                           (alice-entries "2026-03-30,alice,10,apollo"
                                          "2026-04-03,alice,6,apollo"
                                          "2026-04-03,alice,4,zeus")
                           (make-pay-rules :daily-threshold 8
                                           :holidays (easter-calendar)
                                           :holiday-multiplier 5/2))))
    (is (= 8 (pay-line-regular-hours line)))
    (is (= 2 (pay-line-overtime-hours line)))
    (is (= 10 (pay-line-holiday-hours line)))
    (is (= 72000 (pay-line-gross line)))))

(test holidays-leave-others-alone
  (let ((rules (make-pay-rules :holidays (easter-calendar)))
        (timesheet (sheet "2026-04-03,carl,8,apollo"
                          "2026-04-03,sara,8,apollo")))
    (let ((line (compute-pay (make-instance 'contractor :id "carl" :name "Carl Dahl"
                                                        :hourly-rate 5000)
                             (employee-entries timesheet "carl")
                             rules)))
      (is (= 8 (pay-line-regular-hours line)))
      (is (= 0 (pay-line-holiday-hours line)))
      (is (= 40000 (pay-line-gross line))))
    (let ((line (compute-pay (make-instance 'salaried-employee :id "sara" :name "Sara Lie"
                                                               :annual-salary 6000000)
                             (employee-entries timesheet "sara")
                             rules)))
      (is (= 8 (pay-line-regular-hours line)))
      (is (= 0 (pay-line-holiday-hours line)))
      (is (= 500000 (pay-line-gross line))))))

(test no-holidays-no-holiday-hours
  (let ((line (compute-pay (hourly "alice" "Alice Berg" 2000)
                           (alice-entries "2026-04-03,alice,8,apollo")
                           (make-pay-rules))))
    (is (= 8 (pay-line-regular-hours line)))
    (is (= 0 (pay-line-holiday-hours line)))
    (is (= 16000 (pay-line-gross line)))))

(test holiday-payroll
  (let* ((roster (make-roster (hourly "alice" "Alice Berg" 2000)
                              (hourly "bob" "Bob Moe" 3000)))
         (timesheet (sheet "2026-04-01,alice,8,apollo"
                           "2026-04-02,alice,8,apollo"
                           "2026-04-03,bob,4,zeus"))
         (lines (run-payroll roster timesheet (d "2026-04-01") (d "2026-04-30")
                             :rules (make-pay-rules :holidays (easter-calendar)))))
    (is (equal '(8 4) (mapcar #'pay-line-holiday-hours lines)))
    (is (equal '(48000 24000) (mapcar #'pay-line-gross lines)))
    (is (equal '(:regular-hours 8 :overtime-hours 0 :holiday-hours 12 :gross 72000)
               (payroll-totals lines)))
    (is (string= (format nil "~
Id       Name                   Regular  Overtime   Holiday       Gross
alice    Alice Berg                8.00      0.00      8.00      480.00
bob      Bob Moe                   0.00      0.00      4.00      240.00
         Total                     8.00      0.00     12.00      720.00
")
                 (with-output-to-string (out)
                   (write-payroll-report lines out))))))
