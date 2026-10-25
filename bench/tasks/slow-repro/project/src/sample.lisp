(in-package #:tally)

;;; Sample data with the shape of the real till exports, for development
;;; and demonstrations: the real exports are not to leave the customer.
;;; The same seed gives the same sales, on every run.
;;;
;;; Each store has a size that sets how many receipts it writes a day;
;;; Saturdays are busier and Sundays quieter. A receipt has from one to
;;; six lines, each a sale. Each SKU has a fixed unit price. Most sales
;;; are of one item and without a discount.

(defparameter *sample-sku-count* 800
  "The number of products in the sample catalogue.")

(defun sample-store-id (index)
  "Returns the id of the sample store number INDEX, counted from 1."
  (format nil "S~3,'0D" index))

(defun sample-sku-id (index)
  "Returns the SKU of the sample product number INDEX, counted from 1."
  (format nil "SKU-~4,'0D" index))

(defun sample-catalogue (generator)
  "Returns a vector of (SKU . UNIT-PRICE) for the sample products."
  (let ((catalogue (make-array *sample-sku-count*)))
    (dotimes (i *sample-sku-count* catalogue)
      (setf (aref catalogue i)
            (cons (sample-sku-id (1+ i))
                  ;; from 9.90 to 2499.00, mostly cheap
                  (let ((tier (next-integer generator 10)))
                    (* 10 (cond ((< tier 6) (next-between generator 99 999))
                                ((< tier 9) (next-between generator 1000 9999))
                                (t (next-between generator 10000 24990))))))))))

(defun receipts-per-day (generator size day)
  "Returns how many receipts a store of SIZE writes on DAY."
  (let ((base (* size (next-between generator 30 50)))
        (weekday (mod (+ day 3) 7)))    ; 0 is Monday
    (floor (* base (case weekday (5 140) (6 60) (t 100))) 100)))

(defun sample-discount (generator)
  "Returns the discount of a sample sale line: mostly none."
  (let ((roll (next-integer generator 100)))
    (cond ((< roll 85) 0)
          ((< roll 93) 10)
          ((< roll 97) 20)
          ((< roll 99) 30)
          (t 50))))

(defun sample-payment (generator)
  "Returns the payment method of a sample receipt."
  (let ((roll (next-integer generator 100)))
    (cond ((< roll 70) "card")
          ((< roll 85) "mobile")
          ((< roll 97) "cash")
          (t "voucher"))))

(defun write-sample-day (stream generator catalogue store-sizes day first-id)
  "Writes the sample sales of DAY for every store to STREAM, as the lines
of a till export, numbering them from FIRST-ID. Returns the next free id."
  (let ((id first-id))
    (loop for size across store-sizes
          for store-index from 1
          for store = (sample-store-id store-index)
          for receipts = (receipts-per-day generator size day)
          do (loop for receipt from 1 to receipts
                   ;; the shop is open from 08:00 to 21:00
                   for time = (+ (* 8 3600) (floor (* receipt 13 3600) (1+ receipts)))
                   for till = (next-between generator 1 (* 2 size))
                   for payment = (sample-payment generator)
                   do (dotimes (line (next-between generator 1 6))
                        (destructuring-bind (sku . price)
                            (aref catalogue (next-integer generator (length catalogue)))
                          (format-sale-line
                           (make-sale :id id :day day :time time
                                      :store store :till till
                                      :receipt (+ (* 10000 day) receipt)
                                      :sku sku
                                      :quantity (if (< (next-integer generator 10) 7)
                                                    1
                                                    (next-between generator 2 6))
                                      :unit-price price
                                      :discount (sample-discount generator)
                                      :payment payment)
                           stream)
                          (incf id)))))
    id))

(defun write-sample-sales (stream &key (seed 1) (stores 50) (start "2024-01-01")
                                       (days 366))
  "Writes sample sales of STORES stores for DAYS days from START to STREAM,
with a header line, in the format of a till export."
  (let* ((generator (make-generator seed))
         (catalogue (sample-catalogue generator))
         (store-sizes (sample-store-sizes generator stores))
         (start (parse-date start))
         (id 1))
    (write-line "id,time,store,till,receipt,sku,quantity,unit-price,discount,payment"
                stream)
    (dotimes (offset days)
      (setf id (write-sample-day stream generator catalogue store-sizes
                                 (+ start offset) id)))
    (values)))

(defun sample-store-sizes (generator stores)
  "Returns a vector of the sizes of STORES sample stores."
  (let ((sizes (make-array stores)))
    (dotimes (i stores sizes)
      (setf (aref sizes i) (next-between generator 1 3)))))

(defun make-sample-database (&key (seed 1) (stores 50) (start "2024-01-01")
                                  (days 366))
  "Returns a database of the sample sales that WRITE-SAMPLE-SALES writes
with the same arguments. The sales go through IMPORT-SALES one day's
export at a time, as the nightly import reads them, so that the sample
exercises the import too."
  (let* ((database (make-sales-database))
         (generator (make-generator seed))
         (catalogue (sample-catalogue generator))
         (store-sizes (sample-store-sizes generator stores))
         (start (parse-date start))
         (id 1))
    (dotimes (offset days database)
      (let ((export (with-output-to-string (stream)
                      (setf id (write-sample-day stream generator catalogue
                                                 store-sizes (+ start offset) id)))))
        (with-input-from-string (stream export)
          (import-sales database stream))))))
