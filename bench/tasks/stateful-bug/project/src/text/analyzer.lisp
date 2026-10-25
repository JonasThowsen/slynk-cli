(in-package #:trove.text)

;;; An analyzer turns a text into the terms that are indexed and searched
;;; for: the tokenizer's words, without the stop words, stemmed. The same
;;; analyzer must analyze the documents and the queries, or a query for
;;; "harbours" would not find a document about "harbour".

(defparameter *english-stop-words*
  '("a" "an" "and" "are" "as" "at" "be" "but" "by" "for" "if" "in" "into" "is" "it"
    "no" "not" "of" "on" "or" "such" "that" "the" "their" "then" "there" "these"
    "they" "this" "to" "was" "will" "with")
  "The words too common to index.")

(defclass analyzer ()
  ((stop-words :initarg :stop-words
               :reader analyzer-stop-words
               :documentation "A hash table of the words left out.")
   (stemming :initarg :stemming :initform t :reader analyzer-stemming-p
             :documentation "True when terms are the stems of words."))
  (:documentation "Turns texts into terms."))

(defun make-analyzer (&key (stop-words *english-stop-words*) (stemming t))
  "Returns an analyzer that leaves out STOP-WORDS, a list of words, and
stems the others when STEMMING is true."
  (make-instance 'analyzer
                 :stop-words (alexandria:alist-hash-table
                              (mapcar (lambda (word) (cons word t)) stop-words)
                              :test 'equal)
                 :stemming stemming))

(defmethod print-object ((analyzer analyzer) stream)
  (print-unreadable-object (analyzer stream :type t :identity t)
    (format stream "~D stop word~:P~:[, no stemming~;~]"
            (hash-table-count (analyzer-stop-words analyzer))
            (analyzer-stemming-p analyzer))))

(defun word-term (analyzer word)
  "Returns the term of WORD, a lower case word, or NIL for a stop word."
  (with-slots (stop-words stemming) analyzer
    (cond ((gethash word stop-words) nil)
          (stemming (stem word))
          (t word))))

(defgeneric map-terms (function analyzer text)
  (:documentation "Calls FUNCTION with each term of TEXT that ANALYZER
makes, and its token."))

(defmethod map-terms (function (analyzer analyzer) text)
  (let ((function (alexandria:ensure-function function)))
    (do-tokens (token text)
      (alexandria:when-let ((term (word-term analyzer (token-text token))))
        (funcall function term token)))))

(defun analyze (analyzer text)
  "Returns the terms of TEXT, each (TERM . POSITION), in order. Positions
count the stop words too, so that a phrase matches only words that stand
together."
  (let ((terms '()))
    (map-terms (lambda (term token) (push (cons term (token-position token)) terms))
               analyzer text)
    (nreverse terms)))
