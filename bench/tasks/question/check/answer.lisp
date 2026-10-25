;;;; Reads the "key: value" lines of the file ANSWER names and compares
;;;; them with the facts create-scanner works out for
;;;; "[A-Z]{2}-\\d{4}-(?:ab|cd)-XY\\z", verified in an image of the
;;;; pristine cl-ppcre 2.1.2:
;;;;
;;;;   min-len 13, start-anchored-p NIL, starts-with NIL, end string "-XY",
;;;;   end-string-offset 10, end-anchored-p 0 (\z allows no final
;;;;   newline), clause 7 (only END-STRING-TEST).
;;;;
;;;; A value may be quoted or in backticks; the key line may be a list
;;;; item. NONE, FALSE and () count as NIL.

(require :asdf)

(defparameter *expected*
  '(("min-len" . "13")
    ("start-anchored-p" . :nil)
    ("starts-with" . :nil)
    ("end-string" . "-XY")
    ("end-string-offset" . "10")
    ("end-anchored-p" . "0")
    ("clause" . "7")))

(defun trim (string)
  (string-trim '(#\Space #\Tab #\Return #\` #\* #\-) string))

(defun key-value (line)
  "If LINE is of the form KEY: VALUE, possibly as a list item and with
the key in backticks, returns KEY in lower case and VALUE."
  (let* ((line (string-left-trim '(#\Space #\Tab #\- #\* #\>) line))
         (colon (position #\: line)))
    (when colon
      (values (string-downcase (trim (subseq line 0 colon)))
              (string-trim '(#\Space #\Tab #\Return #\`) (subseq line (1+ colon)))))))

(defun first-value (text)
  "The value at the start of TEXT: a double-quoted string, or the first
word without trailing punctuation."
  (cond ((zerop (length text)) "")
        ((char= (char text 0) #\")
         (let ((end (position #\" text :start 1)))
           (if end (subseq text 1 end) (subseq text 1))))
        (t
         (let ((end (position-if (lambda (c) (member c '(#\Space #\Tab #\` #\, #\; #\( #\[)))
                                 text)))
           (string-right-trim "." (subseq text 0 end))))))

(defun nil-word-p (value)
  (member value '("nil" "none" "false" "no" "()") :test #'string-equal))

(defun matches (expected value)
  (if (eq expected :nil)
      (nil-word-p value)
      (string= expected value)))

(let ((answers (make-hash-table :test 'equal))
      (wrong '()))
  (with-open-file (in (uiop:getenv "ANSWER"))
    (loop for line = (read-line in nil)
          while line
          do (multiple-value-bind (key value) (key-value line)
               (when (and key (assoc key *expected* :test #'string=)
                          (not (gethash key answers)))
                 (setf (gethash key answers) (first-value value))))))
  (loop for (key . expected) in *expected*
        for value = (gethash key answers)
        do (cond ((null value)
                  (push (format nil "~A: missing" key) wrong))
                 ((not (matches expected value))
                  (push (format nil "~A: ~S is wrong" key value) wrong))))
  (cond (wrong
         (format t "~&FAIL: ~{~A~^; ~}~%" (nreverse wrong))
         (uiop:quit 1))
        (t
         (format t "~&PASS: all seven values are right~%")
         (uiop:quit 0))))
