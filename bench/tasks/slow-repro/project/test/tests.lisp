(defpackage #:tally/tests
  (:use #:common-lisp #:tally #:fiveam))

(in-package #:tally/tests)

(def-suite :tally :description "Tests for tally.")
(in-suite :tally)

(defparameter *lines*
  '("id,time,store,till,receipt,sku,quantity,unit-price,discount,payment"
    "1,2024-03-01T09:15:00,S001,1,1,SKU-0001,2,1500,0,card"
    "2,2024-03-01T09:15:00,S001,1,1,SKU-0002,1,9900,10,card"
    "3,2024-03-01T11:02:41,S002,2,1,SKU-0001,1,1500,0,cash"
    "4,2024-03-02T10:30:00,S001,1,2,SKU-0003,1,24900,0,mobile"
    "5,2024-03-02T16:45:12,S001,2,3,SKU-0001,4,1500,50,card"
    "6,2024-03-03T12:00:00,S002,1,2,SKU-0002,3,9900,0,voucher")
  "A small till export: two stores over three days.")

(defun small-database ()
  "Returns a database of the sales in *LINES*."
  (let ((database (make-sales-database)))
    (with-input-from-string (stream (format nil "~{~A~%~}" *lines*))
      (import-sales database stream))
    database))

(test dates
  (is (= 0 (parse-date "1970-01-01")))
  (is (= 19783 (parse-date "2024-03-01")))
  (is (string= "2024-02-29" (format-date (parse-date "2024-02-29"))))
  (is (= (1+ (parse-date "2024-02-29")) (parse-date "2024-03-01")))
  (is (= 19783 (parse-date 19783)))
  (loop for day from -1000 to 30000 by 37
        do (is (= day (parse-date (format-date day)))))
  (signals error (parse-date "2024-3-1")))

(test parse-sale-line
  (let ((sale (parse-sale-line "17,2024-03-01T09:15:30,S009,3,88,SKU-0042,3,1299,10,card")))
    (is (= 17 (sale-id sale)))
    (is (string= "2024-03-01" (format-date (sale-day sale))))
    (is (string= "S009" (sale-store sale)))
    (is (string= "SKU-0042" (sale-sku sale)))
    (is (= 3 (sale-quantity sale)))
    (is (= 1299 (sale-unit-price sale)))
    (is (= 3507 (sale-amount sale))))
  (signals malformed-sale-line (parse-sale-line "17,2024-03-01T09:15:30,S009"))
  (signals malformed-sale-line
    (parse-sale-line "17,2024-03-01T09:15:30,S009,3,88,SKU-0042,three,1299,0,card"))
  (signals malformed-sale-line
    (parse-sale-line "17,2024-03-01T09:15:30,S009,3,88,SKU-0042,3,1299,0,cheque")))

(test import
  (let ((database (small-database)))
    (is (= 6 (database-sale-count database)))
    (is (equal '("S001" "S002") (database-stores database)))
    (is (string= "2024-03-01" (format-date (database-first-day database))))
    (is (string= "2024-03-03" (format-date (database-last-day database))))
    (is (eq (sale-sku (find-sale database 1)) (sale-sku (find-sale database 3)))
        "The sales of one SKU share its string.")))

(test daily-revenue
  (let ((database (small-database)))
    (is (= (+ 3000 8910) (daily-revenue database "S001" "2024-03-01")))
    (is (= (+ 24900 3000) (daily-revenue database "S001" "2024-03-02")))
    (is (= 0 (daily-revenue database "S001" "2024-03-03")))
    (is (= 0 (daily-revenue database "S999" "2024-03-01")))
    (is (= (+ 3000 8910 24900 3000)
           (revenue-between database "S001" "2024-03-01" "2024-03-03")))))

(test largest-sales
  (let ((database (small-database)))
    (is (= 4 (length (largest-sales database "S001" "2024-03-01" "2024-03-31"))))
    (is (null (largest-sales database "S002" "2024-03-02" "2024-03-02")))
    (is (equal '(4 2)
               (mapcar #'sale-id
                       (largest-sales database "S001" "2024-03-01" "2024-03-02" :count 2))))))

(test sku-totals-and-ranking
  (let ((database (small-database)))
    (is (equal '(("SKU-0001" . 6) ("SKU-0002" . 1) ("SKU-0003" . 1))
               (sku-totals database "S001" "2024-03-01" "2024-03-03")))
    (is (equal '(("S002" . 31200) ("S001" . 39810))
               (reverse (store-ranking database "2024-03-01" "2024-03-03"))))))

(test void-sale
  (let ((database (small-database)))
    (is (= 2 (sale-id (void-sale database 2))))
    (is (null (find-sale database 2)))
    (is (= 3000 (daily-revenue database "S001" "2024-03-01")))
    (signals error (void-sale database 2))))

(test sample-is-reproducible
  (flet ((sample () (make-sample-database :seed 7 :stores 3 :days 10)))
    (let ((a (sample))
          (b (sample)))
      (is (= (database-sale-count a) (database-sale-count b)))
      (is (plusp (database-sale-count a)))
      (is (= (revenue-between a "S002" "2024-01-01" "2024-01-10")
             (revenue-between b "S002" "2024-01-01" "2024-01-10"))))))
