(in-package #:depot.semver)

;;; Versions are semantic versions as https://semver.org/ defines them:
;;; MAJOR.MINOR.PATCH, then optionally a prerelease after "-", as in
;;; 2.0.0-rc.1, and build metadata after "+". The build metadata is kept
;;; for printing, and precedence ignores it.

(defstruct (version (:constructor %make-version (major minor patch prerelease build))
                    (:copier nil))
  "A semantic version. PRERELEASE is a list of its identifiers, each an
integer or a string; it is empty for a release."
  (major 0 :type (integer 0) :read-only t)
  (minor 0 :type (integer 0) :read-only t)
  (patch 0 :type (integer 0) :read-only t)
  (prerelease '() :type list :read-only t)
  (build "" :type string :read-only t))

(defun make-version (major minor patch &key prerelease (build ""))
  "Returns the version MAJOR.MINOR.PATCH, with the PRERELEASE identifiers
and the BUILD metadata."
  (%make-version major minor patch prerelease build))

(defmethod print-object ((version version) stream)
  (if *print-escape*
      (print-unreadable-object (version stream :type t)
        (write-string (version-string version) stream))
      (write-string (version-string version) stream)))

(defun version-string (version)
  "Returns the text of VERSION, as \"2.0.0-rc.1\"."
  (format nil "~D.~D.~D~@[-~{~A~^.~}~]~@[+~A~]"
          (version-major version) (version-minor version) (version-patch version)
          (version-prerelease version)
          (let ((build (version-build version)))
            (and (plusp (length build)) build))))

(defun version-prerelease-p (version)
  "True when VERSION is a prerelease."
  (not (null (version-prerelease version))))

;;; Parsing

(defun split-text (text character)
  "Returns the parts of TEXT between the occurrences of CHARACTER."
  (loop for start = 0 then (1+ end)
        for end = (position character text :start start)
        collect (subseq text start end)
        while end))

(defun identifier-character-p (character)
  "True when CHARACTER may be in a prerelease or build identifier."
  (or (char<= #\0 character #\9)
      (char<= #\a character #\z)
      (char<= #\A character #\Z)
      (char= character #\-)))

(defun digits-p (text)
  "True when TEXT is one or more decimal digits."
  (and (plusp (length text))
       (every (lambda (character) (char<= #\0 character #\9)) text)))

(defun parse-numeric-part (text whole what)
  "Returns the number TEXT, the WHAT part of the version WHOLE. Leading
zeros are not allowed."
  (cond ((not (digits-p text))
         (error 'version-syntax-error :text whole
                                      :reason (format nil "the ~A is not a number" what)))
        ((and (> (length text) 1) (char= (char text 0) #\0))
         (error 'version-syntax-error :text whole
                                      :reason (format nil "the ~A has a leading zero" what)))
        (t (parse-integer text))))

(defun parse-identifiers (text whole what)
  "Returns the dot-separated identifiers of TEXT, the WHAT of the version
WHOLE. Numeric identifiers become integers, the others stay strings."
  (mapcar (lambda (identifier)
            (cond ((or (zerop (length identifier))
                       (notevery #'identifier-character-p identifier))
                   (error 'version-syntax-error
                          :text whole
                          :reason (format nil "the ~A has an empty or invalid identifier" what)))
                  ((digits-p identifier)
                   (parse-numeric-part identifier whole what))
                  (t identifier)))
          (split-text text #\.)))

(defun parse-version (text)
  "Returns the version TEXT names, as \"1.4.2\", \"2.0.0-rc.1\" or
\"1.0.0+build.5\". Any other text signals a VERSION-SYNTAX-ERROR."
  (check-type text string)
  (let* ((plus (position #\+ text))
         (dash (position #\- text :end plus))
         (core (split-text (subseq text 0 (or dash plus)) #\.)))
    (unless (= 3 (length core))
      (error 'version-syntax-error :text text
                                   :reason "a version has three numbers, as in 1.4.2"))
    (destructuring-bind (major minor patch) core
      (%make-version (parse-numeric-part major text "major version")
                     (parse-numeric-part minor text "minor version")
                     (parse-numeric-part patch text "patch version")
                     (and dash
                          (parse-identifiers (subseq text (1+ dash) plus) text "prerelease"))
                     (if plus
                         (progn (parse-identifiers (subseq text (1+ plus)) text "build metadata")
                                (subseq text (1+ plus)))
                         "")))))

(defun ensure-version (thing)
  "Returns THING if it is a version, or the version the text THING names."
  (etypecase thing
    (version thing)
    (string (parse-version thing))))

;;; Precedence

(defun compare-numbers (a b)
  "Returns -1, 0 or 1 as A is less than, equal to or greater than B."
  (cond ((< a b) -1)
        ((> a b) 1)
        (t 0)))

(defun compare-identifiers (a b)
  "Compares two prerelease identifiers: numeric ones numerically, others
by their characters, and a numeric one before any other."
  (cond ((and (integerp a) (integerp b)) (compare-numbers a b))
        ((integerp a) -1)
        ((integerp b) 1)
        ((string< a b) -1)
        ((string= a b) 0)
        (t 1)))

(defun compare-prereleases (a b)
  "Compares the prerelease identifier lists A and B. A release, with no
identifiers, comes after any prerelease of the same version; otherwise
the first identifier that differs decides, and a list that is a prefix
of the other comes first."
  (cond ((and (null a) (null b)) 0)
        ((null a) 1)
        ((null b) -1)
        (t (loop
             (cond ((and (null a) (null b)) (return 0))
                   ((null a) (return -1))
                   ((null b) (return 1)))
             (let ((order (compare-identifiers (pop a) (pop b))))
               (unless (zerop order)
                 (return order)))))))

(defun compare-versions (a b)
  "Returns -1, 0 or 1 as version A has lower, the same or higher
precedence than version B. Build metadata does not count."
  (let ((a (ensure-version a))
        (b (ensure-version b)))
    (let ((order (or (find-if-not #'zerop
                                  (list (compare-numbers (version-major a) (version-major b))
                                        (compare-numbers (version-minor a) (version-minor b))
                                        (compare-numbers (version-patch a) (version-patch b))))
                     0)))
      (if (zerop order)
          (compare-prereleases (version-prerelease a) (version-prerelease b))
          order))))

(defun version= (a b)
  "True when versions A and B have the same precedence."
  (zerop (compare-versions a b)))

(defun version< (a b)
  "True when version A comes before version B."
  (minusp (compare-versions a b)))

(defun version<= (a b)
  "True when version A comes before version B or is the same."
  (not (plusp (compare-versions a b))))

(defun version> (a b)
  "True when version A comes after version B."
  (plusp (compare-versions a b)))
