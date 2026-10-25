(in-package #:tally)

;;; Every query takes days either as day numbers or as ISO date strings.

(defun day-sales (database store day)
  "Returns the sales of STORE on DAY."
  (let ((days (store-days database store)))
    (and days (values (gethash (parse-date day) days)))))

(defun sales-between (database store from to)
  "Returns the sales of STORE from day FROM to day TO, both included,
day by day."
  (let ((from (parse-date from))
        (to (parse-date to)))
    (apply #'append
           (loop for day from from to to
                 collect (day-sales database store day)))))

(defun total-amount (sales)
  "Returns the sum of the amounts of SALES."
  (loop for sale in sales sum (sale-amount sale)))

(defun daily-revenue (database store day)
  "Returns the revenue of STORE on DAY, in cents."
  (total-amount (day-sales database store day)))

(defun revenue-between (database store from to)
  "Returns the revenue of STORE from day FROM to day TO, both included,
in cents."
  (total-amount (sales-between database store from to)))

(defun largest-sales (database store from to &key (count 10))
  "Returns the COUNT sales of STORE from day FROM to day TO with the
largest amounts, the largest first. Sales with the same amount come in
the order of SALES-BETWEEN."
  (let ((sorted (stable-sort (sales-between database store from to)
                             #'> :key #'sale-amount)))
    (subseq sorted 0 (min count (length sorted)))))

(defun sku-totals (database store from to)
  "Returns an alist from SKU to the quantity of it that STORE sold from day
FROM to day TO, the best selling first, and SKUs that sold as many in
the order of their names."
  (let ((totals (make-hash-table :test 'equal)))
    (dolist (sale (sales-between database store from to))
      (incf (gethash (sale-sku sale) totals 0) (sale-quantity sale)))
    (sort (alexandria:hash-table-alist totals)
          (lambda (a b)
            (or (> (cdr a) (cdr b))
                (and (= (cdr a) (cdr b))
                     (string< (car a) (car b))))))))

(defun store-ranking (database from to)
  "Returns an alist from store id to its revenue from day FROM to day TO,
the highest revenue first."
  (sort (loop for store in (database-stores database)
              collect (cons store (revenue-between database store from to)))
        #'> :key #'cdr))
