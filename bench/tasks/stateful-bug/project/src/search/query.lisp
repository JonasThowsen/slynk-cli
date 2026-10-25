(in-package #:trove.search)

;;; Queries are what the archive's search box takes:
;;;
;;;   harbour cranes          both words, in any field
;;;   "harbour cranes"        the phrase
;;;   title:harbour           the word in the title
;;;   title:"harbour cranes"  the phrase in the title
;;;   storm -harbour          storm, but not harbour
;;;   harbour OR port         either
;;;   (harbour OR port) storm grouping; AND between words is optional
;;;
;;; The words of a query go through the index's analyzer, so a query
;;; matches the stems, and a stop word in it matches anything. A query
;;; parses into QUERY objects, which MATCHING-NUMBERS and SCORE take.

(define-condition query-syntax-error (error)
  ((text :initarg :text :reader query-syntax-error-text)
   (position :initarg :position :reader query-syntax-error-position)
   (message :initarg :message :reader query-syntax-error-message))
  (:report (lambda (condition stream)
             (format stream "~A at character ~D of the query ~S"
                     (query-syntax-error-message condition)
                     (query-syntax-error-position condition)
                     (query-syntax-error-text condition))))
  (:documentation "A query that does not parse."))

(defclass query () ()
  (:documentation "A parsed query."))

(defclass term-query (query)
  ((field :initarg :field :reader query-field
          :documentation "The field to look in, or NIL for all.")
   (term :initarg :term :reader query-term))
  (:documentation "Documents with a term."))

(defclass phrase-query (query)
  ((field :initarg :field :reader query-field)
   (terms :initarg :terms :reader query-terms
          :documentation "The terms, each (TERM . OFFSET), OFFSET its
position after the first word of the phrase."))
  (:documentation "Documents with terms at positions that follow each other."))

(defclass boolean-query (query)
  ((must :initarg :must :initform '() :reader query-must)
   (should :initarg :should :initform '() :reader query-should)
   (must-not :initarg :must-not :initform '() :reader query-must-not))
  (:documentation "Documents that match all of MUST, or, without MUST, any
of SHOULD, and none of MUST-NOT."))

(defclass all-query (query) ()
  (:documentation "Every document: the query of stop words only."))

(defmethod print-object ((query term-query) stream)
  (print-unreadable-object (query stream :type t)
    (format stream "~@[~(~A~):~]~A" (query-field query) (query-term query))))

(defmethod print-object ((query phrase-query) stream)
  (print-unreadable-object (query stream :type t)
    (format stream "~@[~(~A~):~]~S" (query-field query) (mapcar #'car (query-terms query)))))

(defmethod print-object ((query boolean-query) stream)
  (print-unreadable-object (query stream :type t)
    (format stream "~@[must ~S~]~@[ should ~S~]~@[ not ~S~]"
            (query-must query) (query-should query) (query-must-not query))))

;;; The lexer

(defun query-error (text position control &rest arguments)
  "Signals a QUERY-SYNTAX-ERROR about TEXT at POSITION."
  (error 'query-syntax-error :text text :position position
                             :message (apply #'format nil control arguments)))

(defparameter *field-names* '(("title" . :title) ("body" . :body))
  "The field prefixes a query may have.")

(defun lex-query (text)
  "Returns the tokens of the query TEXT: :OPEN, :CLOSE, :OR, :AND, :NOT,
:REQUIRED, and (:WORD FIELD TEXT) and (:PHRASE FIELD TEXT)."
  (let ((tokens '())
        (i 0)
        (length (length text)))
    (labels ((at (j)
               (and (< j length) (char text j)))
             (space-p (character)
               (member character '(#\Space #\Tab #\Newline)))
             (delimiter-p (character)
               (or (null character) (space-p character) (member character '(#\( #\) #\"))))
             (read-phrase (field)
               ;; At the opening quote.
               (let ((end (position #\" text :start (1+ i))))
                 (unless end
                   (query-error text i "The phrase is not closed"))
                 (push (list :phrase field (subseq text (1+ i) end)) tokens)
                 (setf i (1+ end))))
             (read-word ()
               (let ((start i))
                 (loop until (delimiter-p (at i)) do (incf i))
                 (let* ((word (subseq text start i))
                        (colon (position #\: word))
                        (field (and colon
                                    (cdr (assoc (subseq word 0 colon) *field-names*
                                                :test #'string-equal)))))
                   (when field
                     (setf word (subseq word (1+ colon))))
                   (cond ((and field (string= word ""))
                          (if (eql (at i) #\")
                              (read-phrase field)
                              (query-error text start "A field name needs a word or a phrase")))
                         ((and (not field) (string= word "OR")) (push :or tokens))
                         ((and (not field) (string= word "AND")) (push :and tokens))
                         (t (push (list :word field word) tokens)))))))
      (loop
        (loop while (space-p (at i)) do (incf i))
        (let ((character (at i)))
          (cond ((null character) (return))
                ((char= character #\() (push :open tokens) (incf i))
                ((char= character #\)) (push :close tokens) (incf i))
                ((char= character #\") (read-phrase nil))
                ;; A sign before a word, a phrase or a group.
                ((and (member character '(#\- #\+))
                      (at (1+ i))
                      (not (space-p (at (1+ i)))))
                 (push (if (char= character #\-) :not :required) tokens)
                 (incf i))
                (t (read-word)))))
      (nreverse tokens))))

;;; The parser

(defun words-query (analyzer field text)
  "Returns the query of the words of TEXT in FIELD: a term query for one
term, a phrase query for several, NIL when they are all stop words."
  (let ((terms (analyze analyzer text)))
    (cond ((null terms) nil)
          ((null (rest terms))
           (make-instance 'term-query :field field :term (car (first terms))))
          (t
           (let ((first (cdr (first terms))))
             (make-instance 'phrase-query
                            :field field
                            :terms (mapcar (lambda (term) (cons (car term) (- (cdr term) first)))
                                           terms)))))))

(defun simplify (must should must-not)
  "Returns the query of the clauses: the clause itself when there is only
one, a boolean query otherwise."
  (cond ((and (null must-not) (null should) (= 1 (length must))) (first must))
        ((and (null must-not) (null must) (= 1 (length should))) (first should))
        ((and (null must) (null should) (null must-not)) (make-instance 'all-query))
        (t (make-instance 'boolean-query :must must :should should :must-not must-not))))

(defun parse-query (text analyzer)
  "Returns the query TEXT, its words analyzed by ANALYZER. A query that
does not parse signals QUERY-SYNTAX-ERROR."
  (let ((tokens (lex-query text)))
    (labels ((next () (pop tokens))
             (peek () (first tokens))
             (primary ()
               (let ((token (next)))
                 (cond ((eq token :open)
                        (prog1 (alternatives)
                          (unless (eq (next) :close)
                            (query-error text (length text) "A parenthesis is not closed"))))
                       ((and (consp token) (member (first token) '(:word :phrase)))
                        (destructuring-bind (kind field words) token
                          (declare (ignore kind))
                          (words-query analyzer field words)))
                       (t (query-error text (length text) "A word is missing")))))
             (clauses ()
               ;; Clauses up to OR, a closing parenthesis or the end. A
               ;; clause of stop words only is no clause.
               (let ((must '()) (must-not '()) (parsed 0))
                 (loop for token = (peek)
                       while (and token (not (member token '(:or :close))))
                       do (if (eq token :and)
                              (next)
                              (let ((sign (and (member token '(:not :required)) (next))))
                                (incf parsed)
                                (alexandria:when-let ((clause (primary)))
                                  (if (eq sign :not)
                                      (push clause must-not)
                                      (push clause must))))))
                 (when (zerop parsed)
                   (query-error text (length text) "A word is missing"))
                 (simplify (nreverse must) '() (nreverse must-not))))
             (alternatives ()
               (let ((alternatives (list (clauses))))
                 (loop while (eq (peek) :or)
                       do (next)
                          (push (clauses) alternatives))
                 (simplify '() (nreverse alternatives) '()))))
      (prog1 (alternatives)
        (when tokens
          (query-error text (length text) "A parenthesis closes nothing"))))))
