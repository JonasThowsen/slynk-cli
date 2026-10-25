(in-package #:depot.semver)

;;; Constraints are the version ranges of package.json and Cargo.toml:
;;;
;;;   1.2.3  =1.2.3     exactly 1.2.3
;;;   1.2  1.2.x        >=1.2.0 <1.3.0-0          (and 1, 1.x: <2.0.0-0)
;;;   ^1.2.3            >=1.2.3 <2.0.0-0          ^0.2.3: <0.3.0-0, ^0.0.3: <0.0.4-0
;;;   ~1.2.3            >=1.2.3 <1.3.0-0          ~1: <2.0.0-0
;;;   >=1.2  >1.2       >=1.2.0, >=1.3.0          and <, <= the same way
;;;   1.2.3 - 2.3       >=1.2.3 <2.4.0-0          a hyphen range
;;;   * x  (empty)      any version
;;;
;;; Comparators separated by spaces must all hold; alternatives separated
;;; by || are a union. An upper bound that a range implies, such as the
;;; 2.0.0 of ^1.2.3, excludes the prereleases of that version too, which
;;; is what the -0 says: 2.0.0-0 is the first version before 2.0.0.
;;;
;;; A prerelease version satisfies a constraint only when the constraint
;;; names a prerelease itself, as ^2.0.0-rc.1 does: nobody gets a release
;;; candidate they did not ask for.

(defclass constraint ()
  ((text :initarg :text :reader constraint-text
         :documentation "The constraint as it was written.")
   (version-set :initarg :version-set :reader constraint-version-set
                :documentation "The versions the constraint allows.")
   (allows-prereleases :initarg :allows-prereleases
                       :reader constraint-allows-prereleases-p
                       :documentation "True when the constraint names a
prerelease, so that prereleases in its version set satisfy it."))
  (:documentation "A version constraint, as a dependency states it."))

(defmethod print-object ((constraint constraint) stream)
  (print-unreadable-object (constraint stream :type t)
    (write-string (constraint-text constraint) stream)))

(defun constraint-error (text control &rest arguments)
  "Signals a CONSTRAINT-SYNTAX-ERROR about TEXT."
  (error 'constraint-syntax-error :text text
                                  :reason (apply #'format nil control arguments)))

;;; Partial versions: 1, 1.2, 1.2.x, 1.2.3-beta.1. A missing or wildcard
;;; part is NIL.

(defun wildcard-p (part)
  "True when PART of a partial version is a wildcard."
  (member part '("x" "X" "*") :test #'string=))

(defun parse-partial (text whole)
  "Returns the parts of the partial version TEXT, of the constraint
WHOLE, as four values: the major, minor and patch numbers, NIL where
missing or a wildcard, and the prerelease identifiers."
  (let* ((text (subseq text 0 (position #\+ text)))
         (dash (position #\- text))
         (parts (split-text (subseq text 0 dash) #\.))
         (numbers '()))
    (when (> (length parts) 3)
      (constraint-error whole "~S has more than three parts" text))
    (loop for part in parts
          for wildcard = (wildcard-p part)
          do (cond (wildcard
                    (return))
                   ((digits-p part)
                    (push (parse-integer part) numbers))
                   (t
                    (constraint-error whole "~S is not a version" text))))
    (setf numbers (nreverse numbers))
    (when (and (< (length numbers) (length parts))
               (notevery #'wildcard-p (nthcdr (length numbers) parts)))
      (constraint-error whole "~S has a number after a wildcard" text))
    (when (and dash (< (length numbers) 3))
      (constraint-error whole "~S has a prerelease but is not a full version" text))
    (values (first numbers) (second numbers) (third numbers)
            (and dash
                 (version-prerelease (handler-case (parse-version text)
                                       (version-syntax-error ()
                                         (constraint-error whole "~S is not a version" text))))))))

(defun boundary (major &optional (minor 0) (patch 0))
  "Returns the first version before MAJOR.MINOR.PATCH, the exclusive
upper bound a range implies: it leaves out the prereleases of that
version too."
  (make-version major minor patch :prerelease '(0)))

(defun next-boundary (major minor)
  "Returns the boundary after the versions a partial version MAJOR or
MAJOR.MINOR (MINOR NIL for the first) stands for."
  (if minor
      (boundary major (1+ minor))
      (boundary (1+ major))))

(defun at-least (version)
  "Returns the interval of VERSION and the versions after it."
  (make-interval version t nil nil))

(defun below (version)
  "Returns the interval of the versions before VERSION."
  (make-interval nil nil version nil))

(defun from-below (low high)
  "Returns the interval from LOW, included, to HIGH, excluded."
  (make-interval low t high nil))

(defun comparator-interval (operator text whole)
  "Returns the interval of the comparator OPERATOR TEXT of the constraint
WHOLE: OPERATOR is a string such as \">=\" or \"^\", or \"\" for none."
  (multiple-value-bind (major minor patch prerelease) (parse-partial text whole)
    (let ((full (and patch (make-version major minor patch :prerelease prerelease)))
          (lowest (and major (make-version major (or minor 0) (or patch 0)))))
      (when (and (null major) (string/= operator ""))
        (constraint-error whole "a wildcard takes no operator"))
      (cond
        ((null major) (make-interval nil nil nil nil))
        ((member operator '("" "=") :test #'string=)
         (if full
             (make-interval full t full t)
             (from-below lowest (next-boundary major minor))))
        ((string= operator ">=") (at-least lowest))
        ((string= operator ">")
         (if full
             (make-interval full nil nil nil)
             (at-least (next-boundary major minor))))
        ((string= operator "<")
         (below (or full lowest)))
        ((string= operator "<=")
         (if full
             (make-interval nil nil full t)
             (below (next-boundary major minor))))
        ((string= operator "~")
         (from-below (or full lowest)
                     (if minor
                         (boundary major (1+ minor))
                         (boundary (1+ major)))))
        ((string= operator "^")
         (from-below (or full lowest)
                     (cond ((plusp major) (boundary (1+ major)))
                           ((null minor) (boundary 1))
                           ((plusp minor) (boundary 0 (1+ minor)))
                           ((null patch) (boundary 0 1))
                           (t (boundary 0 0 (1+ patch))))))
        (t (constraint-error whole "~S is not an operator" operator))))))

(defparameter *operators* '(">=" "<=" ">" "<" "=" "~" "^")
  "The comparator operators, the longer before the shorter they start with.")

(defun split-operator (comparator)
  "Returns the operator of the comparator text COMPARATOR, or \"\", and
the version text after it."
  (let ((operator (find-if (lambda (operator)
                             (eql 0 (search operator comparator)))
                           *operators*)))
    (if operator
        (values operator (subseq comparator (length operator)))
        (values "" comparator))))

(defun words (text)
  "Returns the parts of TEXT between runs of spaces."
  (remove "" (split-text text #\Space) :test #'string=))

(defun hyphen-range-interval (words whole)
  "Returns the interval of the hyphen range WORDS, (LOW \"-\" HIGH), of
the constraint WHOLE."
  (destructuring-bind (low dash high) words
    (declare (ignore dash))
    (let ((from (comparator-interval ">=" low whole))
          (to (comparator-interval "<=" high whole)))
      (intersect-intervals from to))))

(defun alternative-set (text whole)
  "Returns the version set of TEXT, one alternative of the constraint
WHOLE: comparators that must all hold, or a hyphen range."
  (let ((words (words text)))
    (cond ((null words) (any-version))
          ((and (= (length words) 3) (string= (second words) "-"))
           (make-version-set (hyphen-range-interval words whole)))
          ((member "-" words :test #'string=)
           (constraint-error whole "a hyphen range is LOW - HIGH"))
          (t
           (reduce #'version-set-intersection
                   (mapcar (lambda (word)
                             (multiple-value-bind (operator version) (split-operator word)
                               (when (zerop (length version))
                                 (constraint-error whole "~S has no version" word))
                               (make-version-set (comparator-interval operator version whole))))
                           words))))))

(defun split-alternatives (text)
  "Returns the alternatives of the constraint TEXT, the parts between
its occurrences of \"||\"."
  (loop for start = 0 then (+ end 2)
        for end = (search "||" text :start2 start)
        collect (subseq text start end)
        while end))

(defun parse-constraint (text)
  "Returns the constraint TEXT, as in \"^1.2.0\" or \">=1.4 <3 || 4.x\".
A text that is not one signals a CONSTRAINT-SYNTAX-ERROR."
  (check-type text string)
  (let ((alternatives (split-alternatives text)))
    (make-instance 'constraint
                   :text text
                   :version-set (reduce #'version-set-union
                                        (mapcar (lambda (alternative)
                                                  (alternative-set alternative text))
                                                alternatives))
                   :allows-prereleases (and (position #\- (remove-hyphen-ranges text))
                                            t))))

(defun remove-hyphen-ranges (text)
  "Returns TEXT without the \" - \" of its hyphen ranges, so that the
dashes left are those of prereleases."
  (let ((at (search " - " text)))
    (if at
        (concatenate 'string (subseq text 0 at) " "
                     (remove-hyphen-ranges (subseq text (+ at 3))))
        text)))

(defun ensure-constraint (thing)
  "Returns THING if it is a constraint, or the constraint the text THING
is."
  (etypecase thing
    (constraint thing)
    (string (parse-constraint thing))))

(defun satisfies-p (version constraint)
  "True when VERSION satisfies CONSTRAINT. Either may be a text."
  (let ((version (ensure-version version))
        (constraint (ensure-constraint constraint)))
    (and (or (not (version-prerelease-p version))
             (constraint-allows-prereleases-p constraint))
         (version-set-contains-p (constraint-version-set constraint) version))))
