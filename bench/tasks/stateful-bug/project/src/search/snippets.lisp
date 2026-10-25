(in-package #:trove.search)

;;; A snippet is the part of a document's body that shows why a search
;;; found it: the window of words with the most of the query's terms,
;;; with those words between [ and ].

(defgeneric query-term-set (query)
  (:documentation "Returns the terms QUERY looks for, not those it
excludes.")
  (:method ((query term-query)) (list (query-term query)))
  (:method ((query phrase-query)) (mapcar #'car (query-terms query)))
  (:method ((query all-query)) '())
  (:method ((query boolean-query))
    (remove-duplicates (loop for clause in (append (query-must query) (query-should query))
                             append (query-term-set clause))
                       :test #'string=)))

(defun snippet (index document query &key (width 24))
  "Returns about WIDTH words of the body of DOCUMENT around the terms of
QUERY, a query or its text, with the words that have them marked."
  (let* ((query (ensure-query query index))
         (wanted (query-term-set query))
         (body (document-body document))
         (tokens (coerce (tokenize body) 'simple-vector))
         (hits (map 'simple-vector
                    (lambda (token)
                      (let ((term (word-term (index-analyzer index) (token-text token))))
                        (and term (member term wanted :test #'string=) t)))
                    tokens)))
    (if (zerop (length tokens))
        ""
        (let* ((width (min width (length tokens)))
               (best-start 0)
               (best (count t hits :end width)))
          ;; Slide the window, keeping the count of marked words in it.
          (loop with current = best
                for start from 1 to (- (length tokens) width)
                do (when (svref hits (1- start)) (decf current))
                   (when (svref hits (+ start width -1)) (incf current))
                   (when (> current best)
                     (setf best current
                           best-start start)))
          (with-output-to-string (stream)
            (when (plusp best-start)
              (write-string "... " stream))
            (loop for i from best-start below (+ best-start width)
                  for token = (svref tokens i)
                  for word = (subseq body (token-start token) (token-end token))
                  do (when (> i best-start)
                       (write-char #\Space stream))
                     (if (svref hits i)
                         (format stream "[~A]" word)
                         (write-string word stream)))
            (when (< (+ best-start width) (length tokens))
              (write-string " ..." stream)))))))
