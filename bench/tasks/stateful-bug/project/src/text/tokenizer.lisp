(in-package #:trove.text)

;;; The tokenizer cuts a text into words: runs of letters and digits.
;;; An apostrophe inside a word belongs to it ("don't"), except for a
;;; final "'s", which is dropped ("harbour's" is "harbour"). Everything
;;; else separates words, hyphens included: "follow-up" is two words.
;;;
;;; Each token has its place in the text, START and END, for snippets, and
;;; its POSITION, the number of words before it, for phrase queries.

(defstruct (token (:constructor make-token (text start end position)))
  "A word of a text: its TEXT, lower case, where it is, from START to
END, and its POSITION among the words."
  (text "" :type simple-string)
  (start 0 :type fixnum)
  (end 0 :type fixnum)
  (position 0 :type fixnum))

(declaim (inline word-character-p))
(defun word-character-p (character)
  "True when CHARACTER is a letter or a digit."
  (alphanumericp character))

(defun word-end (text start)
  "Returns the end of the word of TEXT that starts at START. An apostrophe
followed by a word character continues the word."
  (declare (type string text) (type fixnum start))
  (let ((length (length text)))
    (loop with end fixnum = start
          while (< end length)
          do (let ((character (char text end)))
               (cond ((word-character-p character)
                      (incf end))
                     ((and (char= character #\')
                           (< (1+ end) length)
                           (word-character-p (char text (1+ end))))
                      (incf end))
                     (t (return end))))
          finally (return end))))

(defun word-text (text start end)
  "Returns the word of TEXT from START to END, lower case and without a
final \"'s\"."
  (let ((end (if (and (>= (- end start) 3)
                      (char= (char text (- end 2)) #\')
                      (char-equal (char text (1- end)) #\s))
                 (- end 2)
                 end)))
    (let ((word (make-string (- end start))))
      (loop for i from start below end
            for j from 0
            do (setf (schar word j) (char-downcase (char text i))))
      word)))

(defun map-tokens (function text)
  "Calls FUNCTION with each token of TEXT, in order."
  (declare (type function function) (type string text))
  (let ((length (length text))
        (position 0)
        (start 0))
    (declare (type fixnum length position start))
    (loop
      (loop while (and (< start length)
                       (not (word-character-p (char text start))))
            do (incf start))
      (when (>= start length)
        (return))
      (let ((end (word-end text start)))
        (funcall function (make-token (word-text text start end) start end position))
        (incf position)
        (setf start end)))))

(defmacro do-tokens ((token text) &body body)
  "Evaluates BODY with TOKEN bound to each token of TEXT in turn."
  `(block nil
     (map-tokens (lambda (,token) ,@body) ,text)))

(defun tokenize (text)
  "Returns the tokens of TEXT, in order."
  (let ((tokens '()))
    (do-tokens (token text)
      (push token tokens))
    (nreverse tokens)))
