(in-package #:spool)

;;; The protocol is one line per request and one per reply, each a list of
;;; tokens separated by spaces. A token with a space, a double quote or a
;;; backslash in it, or an empty one, is written in double quotes, with a
;;; backslash before each double quote and backslash inside.

(define-condition spool-error (simple-error)
  ()
  (:documentation "A request the server cannot carry out, or a reply that
says so. Its message is what the reply says after ERR."))

(defun spool-error (control &rest arguments)
  (error 'spool-error :format-control control :format-arguments arguments))

(defun plain-token-p (string)
  "True when STRING can be written as it is, without quotes."
  (and (plusp (length string))
       (notany (lambda (char) (member char '(#\Space #\Tab #\" #\\))) string)))

(defun quote-token (string)
  "Returns STRING as a token of a line."
  (if (plain-token-p string)
      string
      (with-output-to-string (out)
        (write-char #\" out)
        (loop for char across string
              do (when (member char '(#\" #\\))
                   (write-char #\\ out))
                 (write-char char out))
        (write-char #\" out))))

(defun join-tokens (tokens)
  "Returns the line of TOKENS, each a string, or anything PRINC writes as a
token, such as a number or a keyword."
  (format nil "~{~A~^ ~}"
          (mapcar (lambda (token)
                    (quote-token (if (stringp token)
                                     token
                                     (string-downcase (princ-to-string token)))))
                  tokens)))

(defun split-tokens (line)
  "Returns the tokens of LINE, a list of strings. Signals SPOOL-ERROR for
a quoted token that does not end."
  (let ((tokens '())
        (index 0)
        (end (length line)))
    (flet ((skip-blanks ()
             (loop while (and (< index end) (member (char line index) '(#\Space #\Tab)))
                   do (incf index))))
      (loop
        (skip-blanks)
        (when (>= index end)
          (return (nreverse tokens)))
        (if (char= (char line index) #\")
            (let ((token (make-string-output-stream)))
              (incf index)
              (loop
                (when (>= index end)
                  (spool-error "unterminated string"))
                (let ((char (char line index)))
                  (incf index)
                  (cond ((char= char #\") (return))
                        ((and (char= char #\\) (< index end))
                         (write-char (char line index) token)
                         (incf index))
                        (t (write-char char token)))))
              (push (get-output-stream-string token) tokens))
            (let ((start index))
              (loop while (and (< index end)
                               (not (member (char line index) '(#\Space #\Tab))))
                    do (incf index))
              (push (subseq line start index) tokens)))))))
