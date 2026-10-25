;;;; RESOLVE against a plain chronological search on random registries.
;;;; The search makes the same decisions in the same order, newest
;;;; release first, and parses every constraint afresh from its text, so
;;;; nothing it decides can depend on what it decided before. Backjumping
;;;; only skips choices that cannot lead to a solution, so both must find
;;;; the same first solution, or both none.

(in-package #:depot/tests)

(in-suite :depot)

(defun fresh-set (requirement)
  "Returns the version set of REQUIREMENT's constraint text, parsed anew."
  (constraint-version-set (parse-constraint (constraint-text (requirement-constraint requirement)))))

(defun search-solution (registry requirements)
  "Returns the releases chosen, sorted by package, or :FAIL."
  (labels ((on (package requirements)
             (remove package requirements :test-not #'string= :key #'requirement-package))
           (allows-p (version requirements)
             (every (lambda (requirement)
                      (satisfies-p version (constraint-text (requirement-constraint requirement))))
                    requirements))
           (solve (requirements order selected)
             (let ((next (find-if-not (lambda (package) (assoc package selected :test #'string=))
                                      order)))
               (if (null next)
                   selected
                   (dolist (release (package-releases registry next) nil)
                     (when (and (not (release-yanked-p release))
                                (allows-p (release-version release) (on next requirements)))
                       (let ((requirements requirements)
                             (order order)
                             (selected (acons next release selected))
                             (possible t))
                         (dolist (dependency (release-dependencies release))
                           (when (eq (dependency-kind dependency) :runtime)
                             (let* ((package (dependency-package dependency))
                                    (requirement (make-requirement package
                                                                   (dependency-constraint dependency)
                                                                   release))
                                    (chosen (cdr (assoc package selected :test #'string=))))
                               (setf requirements (append requirements (list requirement)))
                               (unless (member package order :test #'string=)
                                 (setf order (append order (list package))))
                               (when (or (and chosen
                                              (not (allows-p (release-version chosen)
                                                             (list requirement))))
                                         (version-set-empty-p
                                          (reduce #'version-set-intersection
                                                  (mapcar #'fresh-set (on package requirements)))))
                                 (setf possible nil)
                                 (return)))))
                         (when possible
                           (alexandria:when-let ((solution (solve requirements order selected)))
                             (return solution))))))))))
    (let ((solution (solve requirements
                           (remove-duplicates (mapcar #'requirement-package requirements)
                                              :test #'string= :from-end t)
                           '())))
      (if solution
          (sort (mapcar #'cdr solution) #'string< :key #'release-package)
          :fail))))

(defvar *random-state-of-registries* 12345)

(defun next-random (limit)
  "Returns the next number below LIMIT of a fixed sequence."
  (setf *random-state-of-registries* (mod (* *random-state-of-registries* 48271) 2147483647))
  (mod *random-state-of-registries* limit))

(defun random-element (list)
  (nth (next-random (length list)) list))

(defparameter *random-texts*
  '("^1.0.0" "^1.1.0" "~1.1.0" "^2.0.0" "^2.1.0" ">=1.0.0 <2.1.0" "1.x" "*"
    "^1.0.0 || ^2.0.0" "~2.0.1" ">=2.1.0" "<2.0.0" "=1.1.0"))

(defparameter *random-versions* '("1.0.0" "1.1.0" "1.1.3" "2.0.0" "2.0.1" "2.1.0" "2.2.0"))

(defun random-registry ()
  "Returns a registry of a few packages with random releases and
dependencies, and random requirements on it."
  (let* ((registry (make-registry))
         (names (loop for i below (+ 3 (next-random 5)) collect (format nil "p~D" i))))
    (dolist (name names)
      (dolist (version *random-versions*)
        (when (>= (next-random 10) 4)
          (add-release registry name version
                       :yanked (zerop (next-random 25))
                       :dependencies (loop repeat (next-random 3)
                                           for dependency = (random-element names)
                                           unless (string= dependency name)
                                             collect (list dependency
                                                           (random-element *random-texts*)))))))
    (values registry
            (remove-duplicates (loop repeat (1+ (next-random 3))
                                     collect (make-requirement
                                              (random-element (registry-package-names registry))
                                              (parse-constraint (random-element *random-texts*))))
                               :key #'requirement-package :test #'string= :from-end t))))

(test resolve-agrees-with-search
  (setf *random-state-of-registries* 12345)
  (let ((disagreements '())
        (count 3000))
    (dotimes (i count)
      (multiple-value-bind (registry requirements) (random-registry)
        (let ((expected (search-solution registry requirements))
              (got (handler-case (resolve registry requirements)
                     (resolution-failed () :fail))))
          (flet ((names (result) (if (listp result) (mapcar #'release-name result) result)))
            (unless (equal (names expected) (names got))
              (push (list i (names expected) (names got)) disagreements))))))
    (is (null disagreements)
        "~D of ~D random registries resolve otherwise than a plain search does, as~{~%  ~S~}"
        (length disagreements) count (subseq disagreements 0 (min 3 (length disagreements))))))
