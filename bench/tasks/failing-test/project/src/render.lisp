;;;; render.lisp
;;;;
;;;; A plain-text invoice, for e-mail and for the printer.

(in-package #:billing)

(defparameter *line-width* 64
  "The width of a rendered invoice, in characters.")

(defun write-columns (stream left right)
  "Writes LEFT at the start of a line and RIGHT against its right edge."
  (format stream "~A~VT~A~%"
          left
          (max (1+ (length left)) (- *line-width* (length right)))
          right))

(defun format-percent (percent)
  "Returns PERCENT, a rational, as a string such as \"25\" or \"7.5\"."
  (if (integerp percent)
      (princ-to-string percent)
      (string-right-trim "0" (format nil "~,2F" percent))))

(defun describe-line (line)
  (format nil "~D x ~A (~A)"
          (line-quantity line)
          (product-name (line-product line))
          (format-amount (line-unit-price line))))

(defun render-invoice (invoice &optional (stream *standard-output*))
  "Writes INVOICE as text to STREAM, or returns the text when STREAM is
NIL."
  (if (null stream)
      (with-output-to-string (out)
        (render-invoice invoice out))
      (let ((customer (invoice-customer invoice))
            (rule (make-string *line-width* :initial-element #\-)))
        (format stream "~:[Faktura~;Kreditnota~] ~A~%"
                (invoice-credits invoice) (invoice-number invoice))
        (when (invoice-credits invoice)
          (format stream "Krediterer faktura ~A~%"
                  (invoice-number (invoice-credits invoice))))
        (format stream "Kunde: ~A (~A)~%" (customer-name customer) (customer-id customer))
        (format stream "Dato: ~A  Forfall: ~A~%~A~%"
                (format-date (invoice-date invoice))
                (format-date (due-date invoice))
                rule)
        (dolist (line (invoice-lines invoice))
          (write-columns stream (describe-line line) (format-amount (line-net line))))
        (format stream "~A~%" rule)
        (write-columns stream "Sum" (format-amount (invoice-subtotal invoice)))
        (let ((discount (discount-amount invoice)))
          (unless (zerop discount)
            (write-columns stream
                           (format nil "Rabatt ~A %"
                                   (format-percent (discount-percent customer)))
                           (format-amount discount))))
        (dolist (vat-line (vat-breakdown invoice))
          (write-columns stream
                         (format nil "MVA ~A % av ~A"
                                 (format-percent (vat-line-rate vat-line))
                                 (format-amount (vat-line-base vat-line)))
                         (format-amount (vat-line-vat vat-line))))
        (write-columns stream "Å betale" (format-amount (invoice-total invoice)))
        nil)))
