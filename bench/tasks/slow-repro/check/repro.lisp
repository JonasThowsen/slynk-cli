;;;; The reported case: a query must not change the answers of the queries
;;;; after it. The day lists of the database must survive LARGEST-SALES
;;;; for any period, including a one-day period, for any store, and the
;;;; other period queries must agree before and after.

(in-package :cl-user)

(defun day-range (from to)
  "Returns the day numbers from FROM to TO, both included."
  (loop for day from (tally:parse-date from) to (tally:parse-date to) collect day))

(defun daily-revenues (database store from to)
  (loop for day in (day-range from to)
        collect (tally:daily-revenue database store day)))

(defun reproduction-failures ()
  (let ((failures '())
        (db (tally:make-sample-database)))
    (flet ((expect (what got expected)
             (unless (equalp got expected)
               (push (let ((*print-length* 4) (*print-level* 3))
                       (format nil "~A: got ~S, expected ~S" what got expected))
                     failures)))
           (amounts (sales) (mapcar #'tally:sale-amount sales)))
      ;; What the queries give on a fresh database.
      (let ((s017 (daily-revenues db "S017" "2024-03-01" "2024-03-03"))
            (s005-count (length (tally:day-sales db "S005" "2024-06-15")))
            (s005 (tally:daily-revenue db "S005" "2024-06-15"))
            (s042 (daily-revenues db "S042" "2024-07-01" "2024-07-31"))
            (s042-skus (tally:sku-totals db "S042" "2024-07-01" "2024-07-31"))
            (july (tally:store-ranking db "2024-07-01" "2024-07-31")))
        (expect "fresh daily-revenue S017 2024-03-03"
                (tally:daily-revenue db "S017" "2024-03-03") 4284138)
        (expect "fresh revenue-between S017 2024-03-01..03"
                (tally:revenue-between db "S017" "2024-03-01" "2024-03-03") 29597605)
        ;; The report's sequence.
        (expect "largest-sales S017 2024-03-01..03"
                (amounts (tally:largest-sales db "S017" "2024-03-01" "2024-03-03" :count 3))
                '(1349940 968950 935400))
        (expect "daily-revenue S017 2024-03-03 after largest-sales"
                (tally:daily-revenue db "S017" "2024-03-03") 4284138)
        (expect "daily revenues S017 2024-03-01..03 after largest-sales"
                (daily-revenues db "S017" "2024-03-01" "2024-03-03") s017)
        (expect "revenue-between S017 2024-03-01..03 after largest-sales"
                (tally:revenue-between db "S017" "2024-03-01" "2024-03-03") 29597605)
        (expect "largest-sales S017 2024-03-01..03 a second time"
                (amounts (tally:largest-sales db "S017" "2024-03-01" "2024-03-03" :count 3))
                '(1349940 968950 935400))
        ;; A one-day period of another store.
        (tally:largest-sales db "S005" "2024-06-15" "2024-06-15" :count 5)
        (expect "day-sales count S005 2024-06-15 after largest-sales of that day"
                (length (tally:day-sales db "S005" "2024-06-15")) s005-count)
        (expect "daily-revenue S005 2024-06-15 after largest-sales of that day"
                (tally:daily-revenue db "S005" "2024-06-15") s005)
        ;; A month, then the other period queries.
        (tally:largest-sales db "S042" "2024-07-01" "2024-07-31" :count 20)
        (expect "daily revenues S042 July after largest-sales"
                (daily-revenues db "S042" "2024-07-01" "2024-07-31") s042)
        (expect "sku-totals S042 July after largest-sales"
                (tally:sku-totals db "S042" "2024-07-01" "2024-07-31") s042-skus)
        (expect "store-ranking July after largest-sales"
                (tally:store-ranking db "2024-07-01" "2024-07-31") july)
        ;; Voiding a sale afterwards takes exactly its amount off its day.
        (let ((sale (first (tally:day-sales db "S017" "2024-03-03"))))
          (tally:void-sale db (tally:sale-id sale))
          (expect "daily-revenue S017 2024-03-03 after voiding a sale"
                  (tally:daily-revenue db "S017" "2024-03-03")
                  (- 4284138 (tally:sale-amount sale)))
          (expect "revenue-between S017 2024-03-01..03 after voiding a sale"
                  (tally:revenue-between db "S017" "2024-03-01" "2024-03-03")
                  (- 29597605 (tally:sale-amount sale))))))
    (nreverse failures)))
