(in-package #:tally)

;;; One line of a till export is one sale, that is one line of a receipt:
;;;
;;;   id,time,store,till,receipt,sku,quantity,unit-price,discount,payment
;;;   1048577,2024-03-05T14:23:11,S017,3,88123,SKU-0042,3,1299,10,card
;;;
;;; Prices are in cents (øre) and the discount is a whole percentage, so
;;; every amount is an integer.

(defstruct sale
  (id 0 :type (integer 0))
  (day 0 :type integer)
  (time 0 :type (integer 0 86399))
  (store "" :type simple-string)
  (till 1 :type (integer 1))
  (receipt 0 :type (integer 0))
  (sku "" :type simple-string)
  (quantity 1 :type (integer 1))
  (unit-price 0 :type (integer 0))
  (discount 0 :type (integer 0 100))
  (payment "card" :type simple-string))

(defmethod print-object ((sale sale) stream)
  (print-unreadable-object (sale stream :type t)
    (format stream "~D ~A ~A ~A ~D x ~D~:[~; -~D%~]"
            (sale-id sale) (format-date (sale-day sale)) (sale-store sale)
            (sale-sku sale) (sale-quantity sale) (sale-unit-price sale)
            (plusp (sale-discount sale)) (sale-discount sale))))

(defun sale-amount (sale)
  "Returns what SALE brought in, in cents, after its discount."
  (round (* (sale-quantity sale) (sale-unit-price sale) (- 100 (sale-discount sale)))
         100))

(define-condition malformed-sale-line (error)
  ((line :initarg :line :reader malformed-sale-line-line)
   (reason :initarg :reason :reader malformed-sale-line-reason))
  (:report (lambda (condition stream)
             (format stream "Malformed sale line ~S: ~A"
                     (malformed-sale-line-line condition)
                     (malformed-sale-line-reason condition)))))

(defparameter *payment-methods* '("card" "cash" "mobile" "voucher")
  "The payment methods a till export may name.")

(defun split-fields (line &optional (separator #\,))
  "Returns the start and end of each field of LINE as a vector of conses."
  (coerce (loop for start = 0 then (1+ end)
                for end = (or (position separator line :start start) (length line))
                collect (cons start end)
                while (< end (length line)))
          'simple-vector))

(defun parse-sale-line (line &key (intern-string #'identity))
  "Returns the sale that LINE describes. INTERN-STRING is called on the
store, SKU and payment strings, so that an import can share one string
for every sale of the same store or product."
  (let ((fields (split-fields line)))
    (unless (= (length fields) 10)
      (error 'malformed-sale-line
             :line line :reason (format nil "~D fields, not 10" (length fields))))
    (labels ((bounds (index)
               (let ((field (svref fields index)))
                 (values (car field) (cdr field))))
             (text (index)
               (multiple-value-bind (start end) (bounds index)
                 (funcall intern-string (subseq line start end))))
             (number (index)
               (multiple-value-bind (start end) (bounds index)
                 (handler-case (parse-integer line :start start :end end)
                   (parse-error ()
                     (error 'malformed-sale-line
                            :line line
                            :reason (format nil "field ~D is not a number"
                                            (1+ index))))))))
      (multiple-value-bind (day time)
          (multiple-value-bind (start end) (bounds 1)
            (parse-timestamp line :start start :end end))
        (let ((payment (text 9))
              (discount (number 8)))
          (unless (member payment *payment-methods* :test #'string=)
            (error 'malformed-sale-line
                   :line line :reason (format nil "unknown payment ~S" payment)))
          (unless (<= 0 discount 100)
            (error 'malformed-sale-line
                   :line line :reason (format nil "discount ~D%" discount)))
          (make-sale :id (number 0)
                     :day day
                     :time time
                     :store (text 2)
                     :till (number 3)
                     :receipt (number 4)
                     :sku (text 5)
                     :quantity (number 6)
                     :unit-price (number 7)
                     :discount discount
                     :payment payment))))))

(defun format-sale-line (sale stream)
  "Writes SALE to STREAM as a line of a till export."
  (multiple-value-bind (hours rest) (floor (sale-time sale) 3600)
    (multiple-value-bind (minutes seconds) (floor rest 60)
      (format stream "~D,~AT~2,'0D:~2,'0D:~2,'0D,~A,~D,~D,~A,~D,~D,~D,~A~%"
              (sale-id sale) (format-date (sale-day sale)) hours minutes seconds
              (sale-store sale) (sale-till sale) (sale-receipt sale)
              (sale-sku sale) (sale-quantity sale) (sale-unit-price sale)
              (sale-discount sale) (sale-payment sale)))))
