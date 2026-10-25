(in-package #:trove)

;;; The sample archive: articles with the shape of the newspaper's, for
;;; development and demonstrations, since the real archive is not to
;;; leave the newsroom. The same seed gives the same archive on every
;;; run.
;;;
;;; MAKE-SAMPLE-INDEX replays a history, a day at a time, as the nightly
;;; import does it: the day's new articles, the corrections to earlier
;;; ones (mostly recent), the few withdrawn, and a commit.

;;; A small generator of our own, so that a seed gives the same archive
;;; on every Lisp: the "minimal standard" Lehmer generator (Park and
;;; Miller, with multiplier 48271).

(defconstant +modulus+ 2147483647)
(defconstant +multiplier+ 48271)

(defstruct (generator (:constructor %make-generator (state)))
  (state 1 :type (integer 1 2147483646)))

(defun make-generator (seed)
  "Returns a generator whose sequence is determined by the integer SEED."
  (%make-generator (1+ (mod seed (1- +modulus+)))))

(defun next-integer (generator limit)
  "Returns the next integer of GENERATOR's sequence, from 0 below LIMIT."
  (declare (type generator generator) (type (integer 1 #.+modulus+) limit))
  (let ((state (mod (* (generator-state generator) +multiplier+) +modulus+)))
    (setf (generator-state generator) state)
    (mod state limit)))

(defun next-between (generator low high)
  "Returns the next integer of GENERATOR's sequence from LOW to HIGH, both
included."
  (+ low (next-integer generator (1+ (- high low)))))

(defun chance (generator percent)
  "True PERCENT times in a hundred."
  (< (next-integer generator 100) percent))

(defun pick (generator vector)
  "Returns an element of VECTOR, the first ones more often than the last."
  (let ((u (/ (next-integer generator 1000000) 1000000)))
    (svref vector (floor (* (length vector) u u)))))

(defun pick-evenly (generator sequence)
  "Returns an element of SEQUENCE, each as often as the others."
  (elt sequence (next-integer generator (length sequence))))

;;; Words

(defparameter *desk-nouns*
  (map 'simple-vector (lambda (desk) (coerce (rest desk) 'simple-vector)) *desks*))

(defparameter *verb-vector* (coerce *verbs* 'simple-vector))
(defparameter *adjective-vector* (coerce *adjectives* 'simple-vector))
(defparameter *common-vector* (coerce *common-words* 'simple-vector))

(defun vowelp (character)
  (find character "aeiou"))

(defun add-s (word)
  "Returns WORD with the -s of a plural or of a verb's third person."
  (let ((last (char word (1- (length word)))))
    (cond ((or (find last "sxz")
               (alexandria:ends-with-subseq "ch" word)
               (alexandria:ends-with-subseq "sh" word))
           (concatenate 'string word "es"))
          ((and (char= last #\y) (not (vowelp (char word (- (length word) 2)))))
           (concatenate 'string (subseq word 0 (1- (length word))) "ies"))
          (t (concatenate 'string word "s")))))

(defun add-ed (verb)
  "Returns the past tense of the regular VERB."
  (let ((last (char verb (1- (length verb)))))
    (cond ((char= last #\e) (concatenate 'string verb "d"))
          ((and (char= last #\y) (not (vowelp (char verb (- (length verb) 2)))))
           (concatenate 'string (subseq verb 0 (1- (length verb))) "ied"))
          (t (concatenate 'string verb "ed")))))

(defun add-ing (verb)
  "Returns the present participle of VERB."
  (if (and (alexandria:ends-with #\e verb)
           (not (alexandria:ends-with-subseq "ee" verb)))
      (concatenate 'string (subseq verb 0 (1- (length verb))) "ing")
      (concatenate 'string verb "ing")))

(defun noun (generator desk)
  "Returns a noun of DESK, plural three times in ten."
  (let ((noun (pick generator (svref *desk-nouns* desk))))
    (if (chance generator 30) (add-s noun) noun)))

(defun verb (generator)
  "Returns a verb in one of its forms."
  (let ((verb (pick generator *verb-vector*)))
    (case (next-integer generator 4)
      (0 verb)
      (1 (add-s verb))
      (2 (add-ed verb))
      (t (add-ing verb)))))

(defun sentence (generator desks)
  "Returns a sentence of an article of DESKS, a list of desk numbers."
  (let ((words (loop repeat (next-between generator 7 18)
                     collect (let ((roll (next-integer generator 100)))
                               (cond ((< roll 38) (pick generator *common-vector*))
                                     ((< roll 66) (noun generator (pick-evenly generator desks)))
                                     ((< roll 72) (noun generator (next-integer generator
                                                                                (length *desks*))))
                                     ((< roll 86) (verb generator))
                                     (t (pick generator *adjective-vector*)))))))
    (format nil "~@(~A~)~{ ~A~}." (first words) (rest words))))

(defun headline (generator desks)
  "Returns a title of an article of DESKS."
  (let ((desk (first desks)))
    (format nil "~@(~@[~A ~]~A ~A~)~@[ ~A~] ~A~@[ ~A~]"
            (and (chance generator 50) (pick generator *adjective-vector*))
            (noun generator desk)
            (verb generator)
            (and (chance generator 40)
                 (pick-evenly generator #("after" "in" "for" "at" "over" "before")))
            (noun generator (pick-evenly generator desks))
            (and (chance generator 30) (noun generator desk)))))

(defun article-desks (generator)
  "Returns the desks of an article: one, or two."
  (let ((first (next-integer generator (length *desks*))))
    (if (chance generator 35)
        (list first (next-integer generator (length *desks*)))
        (list first))))

(defun article-id (number)
  "Returns the id of the sample article NUMBER."
  (format nil "doc-~6,'0D" number))

(defun day-string (day)
  "Returns the day DAY of the sample, counted from 2024-01-01, as text."
  (multiple-value-bind (second minute hour date month year)
      (decode-universal-time (+ (encode-universal-time 0 0 12 1 1 2024 0) (* day 86400)) 0)
    (declare (ignore second minute hour))
    (format nil "~D-~2,'0D-~2,'0D" year month date)))

(defun compact (text)
  "Returns TEXT as a base string, a byte a character: the sample is
ASCII, and the archive keeps its texts."
  (coerce text 'simple-base-string))

(defun sample-article (generator number day)
  "Returns the sample article NUMBER, published on DAY."
  (let ((desks (article-desks generator)))
    (make-document (article-id number)
                   :title (compact (headline generator desks))
                   :body (compact (format nil "~{~A~^ ~}"
                                          (loop repeat (next-between generator 4 9)
                                                collect (sentence generator desks))))
                   :published (day-string day))))

(defun revise-article (generator document)
  "Returns a corrected version of DOCUMENT: a new title, and a sentence
more."
  (let ((desks (article-desks generator)))
    (make-document (document-id document)
                   :title (compact (headline generator desks))
                   :body (compact (format nil "~A ~A" (document-body document)
                                          (sentence generator desks)))
                   :published (document-published document))))

(defun sample-documents (&key (seed 1) (count 1000) (first-number 1) (day 0))
  "Returns COUNT sample articles published on DAY, numbered from
FIRST-NUMBER, for adding to an index."
  (let ((generator (make-generator seed)))
    (loop for number from first-number below (+ first-number count)
          collect (sample-article generator number day))))

;;; The history

(defclass sample-history ()
  ((generator :initarg :generator)
   (live :initform (make-array 1024 :adjustable t :fill-pointer 0)
         :documentation "The ids of the articles not withdrawn.")
   (articles :initform (make-hash-table :test 'equal)
             :documentation "The current version of each article not
withdrawn, by id. The history keeps its own, so that what it does next
never depends on the index.")
   (next-number :initform 1))
  (:documentation "The state of a replay of the sample history."))

(defun withdraw (history position)
  "Forgets the article at POSITION of HISTORY's live ids, and returns its id."
  (with-slots (live articles) history
    (let ((id (aref live position)))
      (setf (aref live position) (aref live (1- (length live))))
      (vector-pop live)
      (remhash id articles)
      id)))

(defun correction-target (history)
  "Returns the id of an article to correct: a recent one four times in
five."
  (with-slots (generator live) history
    (let ((count (length live)))
      (aref live (if (and (> count 2000) (chance generator 80))
                     (- count 1 (next-integer generator 2000))
                     (next-integer generator count))))))

(defun replay-day (history index day articles-per-day)
  "Replays DAY of HISTORY into INDEX: ARTICLES-PER-DAY new articles, then
the corrections and withdrawals, then a commit."
  (with-slots (generator live articles next-number) history
    (dotimes (i articles-per-day)
      (let ((article (sample-article generator next-number day)))
        (add-document index article)
        (vector-push-extend (document-id article) live)
        (setf (gethash (document-id article) articles) article)
        (incf next-number)))
    (loop repeat (floor articles-per-day 25)
          do (let* ((id (correction-target history))
                    (revised (revise-article generator (gethash id articles))))
               (update-document index revised)
               (setf (gethash id articles) revised)))
    (loop repeat (floor articles-per-day 120)
          do (delete-document index (withdraw history (next-integer generator (length live)))))
    (commit index)))

(defun sample-history-documents (history)
  "Returns the current version of each article of HISTORY not withdrawn."
  (alexandria:hash-table-values (slot-value history 'articles)))

(defun make-sample-index (&key (seed 1) (days 263) (articles-per-day 800)
                               (flush-size 1000) (merge-factor 8))
  "Returns an index of the sample archive: DAYS days of ARTICLES-PER-DAY
new articles each, with their corrections and withdrawals, committed day
by day. The defaults make the archive of the demonstrations, which takes
a while to build. The second value is the history, whose
SAMPLE-HISTORY-DOCUMENTS are the articles the index should have."
  (let ((index (make-index :flush-size flush-size :merge-factor merge-factor))
        (history (make-instance 'sample-history :generator (make-generator seed))))
    (dotimes (day days)
      (replay-day history index day articles-per-day))
    (values index history)))
