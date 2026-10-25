(in-package #:trove.text)

;;; The Porter stemmer: M. F. Porter, "An algorithm for suffix
;;; stripping", Program 14(3), 1980. It takes a lower case English word
;;; to a stem shared by its inflections and derivations, so that
;;; "connected", "connecting" and "connections" are all "connect". The
;;; stems are not always words ("happy" is "happi"); they only have to be
;;; the same for words that belong together.
;;;
;;; The word is a string with a fill pointer, which the steps shorten and
;;; extend at its end. Each step tries its rules in order and applies at
;;; most one: the first rule whose suffix the word has ends the step,
;;; whether its condition on the stem holds or not.
;;;
;;; The conditions are on the measure of the stem, M in [C](VC)^M[V],
;;; where C is a run of consonants and V of vowels, so that "tree" has
;;; measure 0, "trouble" 1 and "troubles" 2... (see MEASURE).

(defun consonant-p (word i)
  "True when the letter at I of WORD is a consonant: not a, e, i, o or
u, and not a y after a consonant."
  (case (char word i)
    ((#\a #\e #\i #\o #\u) nil)
    (#\y (or (zerop i) (not (consonant-p word (1- i)))))
    (t t)))

(defun measure (word end)
  "Returns the measure of the first END letters of WORD: the number of
times a run of vowels is followed by a run of consonants."
  (let ((i 0)
        (count 0))
    (flet ((skip (consonants)
             (loop while (and (< i end) (eq consonants (consonant-p word i)))
                   do (incf i))))
      (skip t)
      (loop
        (skip nil)
        (when (>= i end)
          (return count))
        (skip t)
        (incf count)))))

(defun vowel-in-p (word end)
  "True when the first END letters of WORD have a vowel."
  (loop for i below end thereis (not (consonant-p word i))))

(defun double-consonant-p (word end)
  "True when the first END letters of WORD end with two of the same
consonant."
  (and (>= end 2)
       (char= (char word (- end 1)) (char word (- end 2)))
       (consonant-p word (1- end))))

(defun cvc-p (word end)
  "True when the first END letters of WORD end consonant, vowel,
consonant, and the last is not w, x or y: hop, but not snow or box."
  (and (>= end 3)
       (consonant-p word (- end 3))
       (not (consonant-p word (- end 2)))
       (consonant-p word (- end 1))
       (not (member (char word (- end 1)) '(#\w #\x #\y)))))

(defun ends-with-p (word suffix)
  "True when WORD ends with SUFFIX."
  (let ((start (- (length word) (length suffix))))
    (and (>= start 0)
         (string= suffix word :start2 start))))

(defun stem-end (word suffix)
  "Returns the length of WORD without SUFFIX, which it ends with."
  (- (length word) (length suffix)))

(defun replace-end (word count replacement)
  "Replaces the last COUNT letters of WORD with REPLACEMENT."
  (setf (fill-pointer word) (- (length word) count))
  (loop for character across replacement
        do (vector-push-extend character word)))

(defun apply-first-rule (word rules condition)
  "Applies the first of RULES, each (SUFFIX REPLACEMENT), whose suffix
WORD has, when CONDITION holds for the measure of the stem before the
suffix and the stem's length."
  (loop for (suffix replacement) in rules
        when (ends-with-p word suffix)
          do (let ((end (stem-end word suffix)))
               (when (funcall condition (measure word end) end)
                 (replace-end word (length suffix) replacement))
               (return))))

(defun step-1a (word)
  "Plurals: caresses to caress, ponies to poni, cats to cat."
  (cond ((ends-with-p word "sses") (replace-end word 4 "ss"))
        ((ends-with-p word "ies") (replace-end word 3 "i"))
        ((ends-with-p word "ss"))
        ((ends-with-p word "s") (replace-end word 1 ""))))

(defun step-1b-tidy (word)
  "After -ed or -ing is gone: conflat(ed) to conflate, hopp(ing) to hop,
fil(ing) to file."
  (let ((end (length word)))
    (cond ((ends-with-p word "at") (replace-end word 2 "ate"))
          ((ends-with-p word "bl") (replace-end word 2 "ble"))
          ((ends-with-p word "iz") (replace-end word 2 "ize"))
          ((and (double-consonant-p word end)
                (not (member (char word (1- end)) '(#\l #\s #\z))))
           (replace-end word 1 ""))
          ((and (= 1 (measure word end)) (cvc-p word end))
           (replace-end word 0 "e")))))

(defun step-1b (word)
  "Past tenses and participles: agreed to agree, plastered to plaster,
motoring to motor."
  (cond ((ends-with-p word "eed")
         (when (plusp (measure word (stem-end word "eed")))
           (replace-end word 3 "ee")))
        ((and (ends-with-p word "ed") (vowel-in-p word (stem-end word "ed")))
         (replace-end word 2 "")
         (step-1b-tidy word))
        ((and (ends-with-p word "ing") (vowel-in-p word (stem-end word "ing")))
         (replace-end word 3 "")
         (step-1b-tidy word))))

(defun step-1c (word)
  "A final y after a vowel in the stem: happy to happi, but sky stays."
  (when (and (ends-with-p word "y") (vowel-in-p word (stem-end word "y")))
    (replace-end word 1 "i")))

(defparameter *step-2-rules*
  '(("ational" "ate") ("tional" "tion") ("enci" "ence") ("anci" "ance") ("izer" "ize")
    ("abli" "able") ("alli" "al") ("entli" "ent") ("eli" "e") ("ousli" "ous")
    ("ization" "ize") ("ation" "ate") ("ator" "ate") ("alism" "al") ("iveness" "ive")
    ("fulness" "ful") ("ousness" "ous") ("aliti" "al") ("iviti" "ive") ("biliti" "ble"))
  "Double suffixes to single ones, for a stem of measure above 0.")

(defparameter *step-3-rules*
  '(("icate" "ic") ("ative" "") ("alize" "al") ("iciti" "ic") ("ical" "ic") ("ful" "")
    ("ness" ""))
  "More suffixes, for a stem of measure above 0.")

(defparameter *step-4-rules*
  '(("al" "") ("ance" "") ("ence" "") ("er" "") ("ic" "") ("able" "") ("ible" "") ("ant" "")
    ("ement" "") ("ment" "") ("ent" "") ("ion" "") ("ou" "") ("ism" "") ("ate" "") ("iti" "")
    ("ous" "") ("ive" "") ("ize" ""))
  "Suffixes that go from a stem of measure above 1; -ion only after s or t.")

(defun step-2 (word)
  (apply-first-rule word *step-2-rules* (lambda (measure end)
                                          (declare (ignore end))
                                          (plusp measure))))

(defun step-3 (word)
  (apply-first-rule word *step-3-rules* (lambda (measure end)
                                          (declare (ignore end))
                                          (plusp measure))))

(defun step-4 (word)
  (apply-first-rule word *step-4-rules*
                    (lambda (measure end)
                      (and (> measure 1)
                           (or (not (ends-with-p word "ion"))
                               (and (plusp end)
                                    (member (char word (1- end)) '(#\s #\t))))))))

(defun step-5 (word)
  "A final e, and a final double l, of a long enough stem: probate to
probat, controll to control."
  (when (ends-with-p word "e")
    (let* ((end (stem-end word "e"))
           (measure (measure word end)))
      (when (or (> measure 1)
                (and (= measure 1) (not (cvc-p word end))))
        (replace-end word 1 ""))))
  (let ((end (length word)))
    (when (and (> (measure word end) 1)
               (double-consonant-p word end)
               (char= (char word (1- end)) #\l))
      (replace-end word 1 ""))))

(defun stem (word)
  "Returns the Porter stem of WORD, a lower case word. Words of one or
two letters are their own stems."
  (if (<= (length word) 2)
      word
      (let ((buffer (make-array (length word) :element-type 'character
                                              :fill-pointer t
                                              :adjustable t
                                              :initial-contents word)))
        (step-1a buffer)
        (step-1b buffer)
        (step-1c buffer)
        (step-2 buffer)
        (step-3 buffer)
        (step-4 buffer)
        (step-5 buffer)
        (coerce buffer 'simple-string))))
