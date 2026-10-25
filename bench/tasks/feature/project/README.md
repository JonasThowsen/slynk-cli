# timesheet

Hours and payroll for a small company. Employees record their hours as
lines of `DATE,EMPLOYEE-ID,HOURS,PROJECT`; a payroll run turns a period's
hours into regular and overtime hours and gross pay per employee.

```lisp
(let ((roster (timesheet:make-roster
               (make-instance 'timesheet:hourly-employee
                              :id "alice" :name "Alice Berg" :hourly-rate 2000)))
      (sheet (timesheet:make-timesheet)))
  (timesheet:load-entries sheet '("2026-03-02,alice,9.5,apollo"))
  (timesheet:write-payroll-report
   (timesheet:run-payroll roster sheet
                          (timesheet:parse-date "2026-03-01")
                          (timesheet:parse-date "2026-03-31")
                          :rules (timesheet:make-pay-rules :daily-threshold 8))))
```

Money is in cents and hours are exact rationals. Hourly employees get
overtime above the weekly threshold (and the daily one, if set);
contractors are paid a flat rate; salaried employees get their annual
salary divided by the pay periods in a year.

Run the tests with `(asdf:test-system "timesheet")`.
