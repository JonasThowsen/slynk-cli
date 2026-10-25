(in-package #:timesheet-check)

(def-suite* entries :in timesheet)

(test parse-hours
  (is (= 8 (parse-hours "8")))
  (is (= 15/2 (parse-hours "7.5")))
  (is (= 29/4 (parse-hours " 7.25 ")))
  (is (= 1/2 (parse-hours ".5")))
  (signals error (parse-hours ""))
  (signals error (parse-hours "7,5"))
  (signals error (parse-hours "-1")))

(test parse-entry-line
  (multiple-value-bind (date id hours project)
      (parse-entry-line "2026-03-02, alice, 7.5, apollo")
    (is (date= (d "2026-03-02") date))
    (is (string= "alice" id))
    (is (= 15/2 hours))
    (is (string= "apollo" project))))

(test malformed-lines
  (signals malformed-entry (parse-entry-line "2026-03-02,alice,7.5"))
  (signals malformed-entry (parse-entry-line "2026-03-32,alice,7.5,apollo"))
  (signals malformed-entry (parse-entry-line "2026-03-02,,7.5,apollo"))
  (signals malformed-entry (parse-entry-line "2026-03-02,alice,lots,apollo")))

(test record-hours-limits
  (let ((timesheet (make-timesheet)))
    (signals timesheet-error (record-hours timesheet "alice" (d "2026-03-02") 0 "apollo"))
    (signals timesheet-error (record-hours timesheet "alice" (d "2026-03-02") 25 "apollo"))))

(test load-entries
  (let ((timesheet (make-timesheet)))
    (is (= 2 (load-entries timesheet '("# March"
                                       "2026-03-03,alice,8,apollo"
                                       ""
                                       "2026-03-02,alice,6,zeus"))))
    (let ((entries (employee-entries timesheet "alice")))
      (is (equal '("zeus" "apollo") (mapcar #'entry-project entries))))
    (is (null (employee-entries timesheet "bob")))))

(test employee-entries-period
  (let ((timesheet (sheet "2026-02-27,alice,8,apollo"
                          "2026-03-02,alice,8,apollo"
                          "2026-03-31,alice,8,apollo"
                          "2026-04-01,alice,8,apollo")))
    (is (= 2 (length (employee-entries timesheet "alice"
                                       :start (d "2026-03-01")
                                       :end (d "2026-03-31")))))
    (is (= 3 (length (employee-entries timesheet "alice" :start (d "2026-03-01")))))))
