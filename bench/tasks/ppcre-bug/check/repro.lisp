;;;; The reported case: a register in an optional group that does not
;;;; take part in the match must be NIL, whatever it matched in attempts
;;;; that failed.

(in-package :cl-user)

(defun reproduction-failures ()
  (let ((failures '()))
    (flet ((expect (regex target whole registers)
             (let ((got (multiple-value-list
                         (ppcre:scan-to-strings regex target))))
               (unless (equalp got (list whole registers))
                 (push (format nil "(scan-to-strings ~S ~S) => ~{~S~^ ~}, expected ~S ~S"
                               regex target got whole registers)
                       failures)))))
      (expect "(?:(\\d+)h)?\\s*(\\d+)m" "10m" "10m" #(nil "10"))
      (expect "(?:(\\d+)h)?\\s*(\\d+)m" "2h 10m" "2h 10m" #("2" "10"))
      (expect "(?:(\\d+)h)?\\s*(\\d+)m" "x 45m" " 45m" #(nil "45"))
      (expect "(?:(a)|b)c" "abc" "bc" #(nil))
      (expect "(?:(\\w+)@)?(\\w+)\\.com" "user.example.com" "example.com" #(nil "example"))
      (unless (equal (ppcre:register-groups-bind (hours minutes)
                         ("(?:(\\d+)h)?\\s*(\\d+)m" "10m")
                       (list hours minutes))
                     '(nil "10"))
        (push "register-groups-bind of \"10m\" does not give (NIL \"10\")" failures)))
    (nreverse failures)))
