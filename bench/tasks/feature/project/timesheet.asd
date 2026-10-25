(defsystem "timesheet"
  :description "Timesheets and payroll for a small company: hours, overtime, pay."
  :version "0.4.0"
  :license "MIT"
  :serial t
  :components ((:module "src"
                :serial t
                :components ((:file "package")
                             (:file "dates")
                             (:file "employees")
                             (:file "entries")
                             (:file "rules")
                             (:file "payroll")
                             (:file "report"))))
  :in-order-to ((test-op (test-op "timesheet/tests"))))

(defsystem "timesheet/tests"
  :description "Tests for timesheet."
  :depends-on ("timesheet" "fiveam")
  :serial t
  :components ((:module "tests"
                :serial t
                :components ((:file "package")
                             (:file "dates")
                             (:file "entries")
                             (:file "payroll")
                             (:file "report"))))
  :perform (test-op (o c)
             (unless (uiop:symbol-call :fiveam :run!
                                       (uiop:find-symbol* :timesheet :timesheet/tests))
               (error "timesheet tests failed"))))
