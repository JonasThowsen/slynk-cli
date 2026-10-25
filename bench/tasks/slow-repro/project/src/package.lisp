(defpackage #:tally
  (:use #:common-lisp)
  (:export
   ;; Dates
   #:parse-date
   #:format-date
   ;; Sales
   #:sale
   #:make-sale
   #:sale-id
   #:sale-day
   #:sale-store
   #:sale-sku
   #:sale-quantity
   #:sale-unit-price
   #:sale-amount
   #:parse-sale-line
   #:malformed-sale-line
   ;; The database
   #:sales-database
   #:make-sales-database
   #:add-sale
   #:find-sale
   #:void-sale
   #:import-sales
   #:database-stores
   #:database-sale-count
   #:database-first-day
   #:database-last-day
   ;; Queries
   #:day-sales
   #:sales-between
   #:daily-revenue
   #:revenue-between
   #:largest-sales
   #:sku-totals
   #:store-ranking
   ;; Sample data
   #:write-sample-sales
   #:make-sample-database))
