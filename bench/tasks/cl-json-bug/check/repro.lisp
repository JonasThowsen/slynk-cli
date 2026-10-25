;;;; The reported case: a decoded document with objects nested three
;;;; deep does not encode; SBCL gives up with "Help! 11 nested errors".
;;;; Also checks chains of nested objects up to nine deep, and nested
;;;; records with several members, through both encoders the report
;;;; names: each must give back the JSON it was decoded from.

(in-package :cl-user)

(defun nested-chain (depth)
  "{\"a\":{\"b\":...\"test\"}} with DEPTH objects."
  (with-output-to-string (out)
    (dotimes (i depth) (format out "{\"~C\":" (code-char (+ (char-code #\a) i))))
    (write-string "\"test\"" out)
    (dotimes (i depth) (write-char #\} out))))

(defun nested-records (depth)
  "Records of an id, a name and a child record, DEPTH records deep."
  (if (= depth 1)
      "{\"id\":1,\"name\":\"leaf\"}"
      (format nil "{\"id\":~D,\"name\":\"node ~D\",\"child\":~A}"
              depth depth (nested-records (1- depth)))))

(defun reproduction-failures ()
  (let ((failures '())
        ;; SBCL does not signal a condition when nested errors exceed its
        ;; limit; it goes straight to the debugger, which a check has not.
        (sb-ext:*invoke-debugger-hook*
          (lambda (condition hook)
            (declare (ignore hook))
            (format t "~&FAIL: the reported case still goes wrong:~%  encoding dies: ~A~%"
                    condition)
            (finish-output)
            (uiop:quit 1))))
    (flet ((round-trip (json)
             (dolist (encoder '(json:encode-json-to-string json:encode-json-alist-to-string))
               (let ((got (handler-case
                              (funcall encoder (json:decode-json-from-string json))
                            (error (e) (format nil "~A: ~A" (type-of e) e)))))
                 (unless (equal got json)
                   (push (format nil "(~(~A~) (json:decode-json-from-string ~S)) => ~S"
                                 encoder json got)
                         failures))))))
      (round-trip "{\"a\":{\"b\":{\"c\":\"test\"}}}")
      (loop for depth from 1 to 9 do (round-trip (nested-chain depth)))
      (loop for depth from 1 to 8 do (round-trip (nested-records depth)))
      (round-trip "{\"user\":{\"name\":\"Kari\",\"address\":{\"city\":\"Oslo\",\"zip\":\"0150\",\"geo\":{\"lat\":59.9,\"lon\":10.7}}},\"active\":true}"))
    (nreverse failures)))
