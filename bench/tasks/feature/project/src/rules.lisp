(in-package #:timesheet)

;;; The rules a payroll run follows. They are kept apart from the
;;; employees so that a run can be redone under other rules, as when
;;; the collective agreement changes.

(defclass pay-rules ()
  ((weekly-threshold :initarg :weekly-threshold
                     :reader weekly-threshold
                     :documentation "Hours in a week, Monday to Sunday, above
which hourly employees are paid overtime.")
   (daily-threshold :initarg :daily-threshold
                    :reader daily-threshold
                    :documentation "Hours in a day above which hourly employees
are paid overtime, or NIL for no daily limit.")
   (overtime-multiplier :initarg :overtime-multiplier
                        :reader overtime-multiplier
                        :documentation "Overtime pay as a multiple of the hourly rate.")
   (periods-per-year :initarg :periods-per-year
                     :reader periods-per-year
                     :documentation "Pay periods in a year: a salaried employee
is paid this fraction of the annual salary per run."))
  (:documentation "How hours turn into pay."))

(defun make-pay-rules (&key (weekly-threshold 40)
                            (daily-threshold nil)
                            (overtime-multiplier 3/2)
                            (periods-per-year 12))
  "Returns pay rules. The defaults are a 40-hour week, no daily limit,
time and a half for overtime and monthly pay."
  (check-type weekly-threshold (rational 0))
  (check-type daily-threshold (or null (rational 0 24)))
  (check-type overtime-multiplier (rational 1))
  (check-type periods-per-year (integer 1))
  (make-instance 'pay-rules
                 :weekly-threshold weekly-threshold
                 :daily-threshold daily-threshold
                 :overtime-multiplier overtime-multiplier
                 :periods-per-year periods-per-year))

(defmethod print-object ((rules pay-rules) stream)
  (print-unreadable-object (rules stream :type t)
    (format stream "~Ah/week~@[ ~Ah/day~] x~A"
            (weekly-threshold rules)
            (daily-threshold rules)
            (overtime-multiplier rules))))
