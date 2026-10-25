(in-package #:depot)

;;; The resolver chooses a release of each package a project needs, so
;;; that each release chosen satisfies every requirement on its package,
;;; preferring newer releases. It is a backtracking search:
;;;
;;; - A requirement says that a package must have a version a constraint
;;;   allows. The project's dependencies are the first requirements, and
;;;   choosing a release adds its runtime dependencies as more.
;;;
;;; - For each package required, the resolver keeps the set of the
;;;   versions all the requirements on it allow. It decides the packages
;;;   one at a time, in the order they were first required, and tries the
;;;   newest release in the set first.
;;;
;;; - A conflict is a requirement that leaves its package no version, or
;;;   that the release already chosen for its package does not satisfy.
;;;   Then the resolver goes back to the most recent decision the
;;;   conflict depends on, and tries that decision's next release: the
;;;   decisions in between have nothing to do with the conflict, and
;;;   trying their other releases would only meet it again. This is
;;;   conflict-directed backjumping; each decision collects the earlier
;;;   decisions its releases conflicted with, and when it runs out of
;;;   releases the resolver goes back to the most recent of those.
;;;
;;; Every change to the state goes on a trail, with a function that
;;; undoes it, so that going back to a decision is undoing the trail to
;;; the length it had when the decision was made.

(defvar *step-limit* 100000
  "The number of releases RESOLVE tries before it gives up.")

(define-condition unknown-package (depot-error)
  ((name :initarg :name :reader unknown-package-name))
  (:report (lambda (condition stream)
             (format stream "The project requires ~A, which is not in the registry."
                     (unknown-package-name condition))))
  (:documentation "A project requires a package the registry does not
have."))

(defun skip-requirement (&optional condition)
  "Invokes the SKIP-REQUIREMENT restart: the project is resolved without
its requirement on an unknown package."
  (invoke-restart (find-restart 'skip-requirement condition)))

(define-condition resolution-failed (depot-error)
  ((project :initarg :project :initform nil :reader resolution-failed-project)
   (conflicts :initarg :conflicts :initform '() :reader resolution-failed-conflicts
              :documentation "The conflicts the resolver met, the first first.")
   (message :initarg :message :initform nil :reader resolution-failed-message))
  (:report (lambda (condition stream)
             (let ((conflicts (resolution-failed-conflicts condition)))
               (format stream "Cannot resolve the dependencies~@[ of ~A~]: ~A~@[~%(and ~D other conflict~:P)~]"
                       (resolution-failed-project condition)
                       (cond ((resolution-failed-message condition))
                             (conflicts (describe-conflict (first conflicts)))
                             (t "there are no versions left to try."))
                       (and (rest conflicts) (length (rest conflicts)))))))
  (:documentation "No choice of releases satisfies all the requirements."))

;;; Requirements and conflicts

(defstruct (requirement (:constructor make-requirement
                            (package constraint &optional source (level 0))))
  "A requirement that PACKAGE have a version that satisfies CONSTRAINT.
SOURCE is the release whose dependency it is, or NIL for the project's
own. LEVEL is the number of the decision that added it, 0 for the
project's."
  (package "" :type string :read-only t)
  (constraint nil :type constraint :read-only t)
  (source nil :type (or null release) :read-only t)
  (level 0 :type (integer 0) :read-only t))

(defun requirement-source-name (requirement)
  "Returns what added REQUIREMENT, as \"template 1.3.0\" or \"the project\"."
  (let ((source (requirement-source requirement)))
    (if source (release-name source) "the project")))

(defun describe-requirement (requirement)
  "Returns REQUIREMENT as its constraint and source, as \"^2.1.0
(template 1.3.0)\"."
  (format nil "~A (~A)"
          (constraint-text (requirement-constraint requirement))
          (requirement-source-name requirement)))

(defmethod print-object ((requirement requirement) stream)
  (print-unreadable-object (requirement stream :type t)
    (format stream "~A ~A" (requirement-package requirement)
            (describe-requirement requirement))))

(defun requirement-versions (requirement)
  "Returns the set of the versions REQUIREMENT allows."
  (constraint-version-set (requirement-constraint requirement)))

(defstruct (conflict (:constructor make-conflict (kind package requirements levels
                                                  &optional selected)))
  "A conflict the resolver met on PACKAGE. KIND is :UNKNOWN-PACKAGE when
the registry has no such package, :NO-RELEASE when no release satisfies
all of REQUIREMENTS, and :EXCLUDES-SELECTED when the last of
REQUIREMENTS excludes SELECTED, the release chosen for PACKAGE. LEVELS
are the decisions the conflict depends on."
  (kind :no-release :type (member :unknown-package :no-release :excludes-selected) :read-only t)
  (package "" :type string :read-only t)
  (requirements '() :type list :read-only t)
  (levels '() :type list :read-only t)
  (selected nil :read-only t))

(defun describe-conflict (conflict)
  "Returns a sentence that says what CONFLICT is."
  (let ((package (conflict-package conflict))
        (requirements (conflict-requirements conflict)))
    (ecase (conflict-kind conflict)
      (:unknown-package
       (format nil "There is no package ~A, which ~{~A~^, ~} require~:[~;s~]."
               package (mapcar #'requirement-source-name requirements)
               (= 1 (length requirements))))
      (:no-release
       (format nil "No release of ~A satisfies ~{~A~^, ~}."
               package (mapcar #'describe-requirement requirements)))
      (:excludes-selected
       (format nil "~A, chosen for ~{~A~^, ~}, does not satisfy ~A."
               (release-name (conflict-selected conflict))
               (mapcar #'describe-requirement (butlast requirements))
               (describe-requirement (first (last requirements))))))))

(defmethod print-object ((conflict conflict) stream)
  (print-unreadable-object (conflict stream :type t)
    (write-string (describe-conflict conflict) stream)))

;;; The state of a resolution

(defstruct (decision (:constructor make-decision (level package candidates mark)))
  "The choice of a release for PACKAGE, the LEVELth decision. CANDIDATES
are the releases not tried yet; MARK is the length of the trail before
the decision. CONFLICT-LEVELS are the earlier decisions that its
releases so far conflicted with."
  (level 0 :type (integer 1))
  (package "" :type string)
  (candidates '() :type list)
  (mark 0 :type (integer 0))
  (tried 0 :type (integer 0))
  (conflict-levels '() :type list))

(defclass resolution ()
  ((registry :initarg :registry :reader resolution-registry)
   (allowed :initform (make-hash-table :test 'equal)
            :documentation "For each package required, the set of the
versions every requirement on it allows. A set is narrowed in place as
requirements are added, and the trail puts back the intervals it had:
a resolution adds requirements by the thousand.")
   (requirements :initform (make-hash-table :test 'equal)
                 :documentation "For each package, the requirements on it,
the newest first.")
   (selected :initform (make-hash-table :test 'equal)
             :documentation "For each package decided, the release chosen
and the level of the decision, as (RELEASE . LEVEL).")
   (order :initform (make-array 32 :adjustable t :fill-pointer 0)
          :documentation "The packages required, in the order they were
first required, which is the order they are decided in.")
   (trail :initform '()
          :documentation "The functions that undo the changes to the
state, the most recent first.")
   (trail-length :initform 0)
   (decisions :initform '()
              :documentation "The decisions made, the most recent first.")
   (conflicts :initform '()
              :documentation "The conflicts met, the most recent first.
Going back does not forget them: they explain a failure.")
   (preferred :initarg :preferred :initform (make-hash-table :test 'equal)
              :documentation "For some packages, the version to try first,
as from a previous lock.")
   (as-of :initarg :as-of :initform nil
          :documentation "When a day, as \"2025-06-30\", releases
published after it are left out.")
   (project-name :initarg :project-name :initform nil)
   (steps :initform 0))
  (:documentation "The state of one call of RESOLVE."))

(defmethod print-object ((resolution resolution) stream)
  (print-unreadable-object (resolution stream :type t :identity t)
    (with-slots (selected order decisions) resolution
      (format stream "~D of ~D package~:P decided, ~D decision~:P deep"
              (hash-table-count selected) (length order) (length decisions)))))

(defun trail (resolution undo)
  "Records the function UNDO, which undoes the change just made to
RESOLUTION."
  (with-slots (trail trail-length) resolution
    (push undo trail)
    (incf trail-length)))

(defun undo-to (resolution mark)
  "Undoes the changes to RESOLUTION until its trail has the length MARK."
  (with-slots (trail trail-length) resolution
    (loop while (> trail-length mark)
          do (funcall (pop trail))
             (decf trail-length))))

(defun requirements-on (resolution package)
  "Returns the requirements on PACKAGE, in the order they were added."
  (reverse (gethash package (slot-value resolution 'requirements))))

(defun requirement-levels (resolution package)
  "Returns the levels of the decisions that added the requirements on
PACKAGE."
  (remove-duplicates (mapcar #'requirement-level (requirements-on resolution package))))

;;; Adding requirements

(defun add-requirement (resolution requirement)
  "Adds REQUIREMENT to RESOLUTION. Returns NIL, or the conflict it makes."
  (with-slots (allowed requirements selected order) resolution
    (let* ((package (requirement-package requirement))
           (constraint (requirement-constraint requirement))
           (earlier (gethash package requirements))
           (set (gethash package allowed)))
      (setf (gethash package requirements) (cons requirement earlier))
      (trail resolution (lambda () (setf (gethash package requirements) earlier)))
      (cond (set
             (let ((intervals (version-set-intervals set)))
               (trail resolution (lambda () (setf (version-set-intervals set) intervals))))
             (narrow-version-set set (requirement-versions requirement)))
            (t
             (setf set (requirement-versions requirement)
                   (gethash package allowed) set)
             (vector-push-extend package order)
             (trail resolution (lambda ()
                                 (remhash package allowed)
                                 (vector-pop order)))))
      (destructuring-bind (&optional chosen . level) (gethash package selected)
        (cond ((version-set-empty-p set)
               (make-conflict :no-release package (requirements-on resolution package)
                              (requirement-levels resolution package)))
              ((and chosen (not (satisfies-p (release-version chosen) constraint)))
               (make-conflict :excludes-selected package
                              (append (remove requirement (requirements-on resolution package))
                                      (list requirement))
                              (list level (requirement-level requirement))
                              chosen)))))))

;;; Choosing releases

(defun release-allowed-p (resolution release)
  "True when RELEASE may be chosen apart from the requirements on its
package: it was not published after the AS-OF day, and it is not
yanked unless it is the preferred version."
  (with-slots (as-of preferred) resolution
    (let ((published (release-published release))
          (preferred (gethash (release-package release) preferred)))
      (and (or (null as-of) (null published) (string<= published as-of))
           (or (not (release-yanked-p release))
               (and preferred (version= preferred (release-version release))))))))

(defun candidates (resolution package)
  "Returns the releases of PACKAGE that RESOLUTION's requirements allow,
in the order to try them: the preferred version first, if it is among
them, then the newest first. A prerelease is a candidate only when
every requirement on PACKAGE allows prereleases."
  (with-slots (registry allowed preferred) resolution
    (let* ((set (gethash package allowed))
           (prereleases (every (lambda (requirement)
                                 (constraint-allows-prereleases-p
                                  (requirement-constraint requirement)))
                               (requirements-on resolution package)))
           (releases (remove-if-not
                      (lambda (release)
                        (let ((version (release-version release)))
                          (and (version-set-contains-p set version)
                               (or prereleases (not (version-prerelease-p version)))
                               (release-allowed-p resolution release))))
                      (package-releases registry package)))
           (first (alexandria:when-let ((version (gethash package preferred)))
                    (find version releases :key #'release-version :test #'version=))))
      (if first
          (cons first (remove first releases))
          releases))))

(defun select (resolution decision release)
  "Chooses RELEASE in DECISION and adds its runtime dependencies as
requirements. Returns NIL, or the first conflict they make."
  (with-slots (selected) resolution
    (let ((package (release-package release)))
      (setf (gethash package selected) (cons release (decision-level decision)))
      (trail resolution (lambda () (remhash package selected)))
      (dolist (dependency (release-dependencies release))
        (when (eq (dependency-kind dependency) :runtime)
          (let ((conflict (add-requirement resolution
                                           (make-requirement (dependency-package dependency)
                                                             (dependency-constraint dependency)
                                                             release
                                                             (decision-level decision)))))
            (when conflict
              (return conflict))))))))

(defun record-conflict (resolution conflict)
  "Remembers CONFLICT for the explanation of a failure, and returns it."
  (push conflict (slot-value resolution 'conflicts))
  conflict)

(defun fail (resolution &optional message)
  "Signals RESOLUTION-FAILED with the conflicts RESOLUTION met."
  (with-slots (conflicts project-name) resolution
    (error 'resolution-failed :project project-name
                              :conflicts (reverse conflicts)
                              :message message)))

(defun backjump (resolution levels)
  "Goes back to the most recent decision among LEVELS, which a conflict
depends on, and leaves the other LEVELS with it, to go back to when it
has no releases left. When none of LEVELS is a decision, nothing can be
changed to avoid the conflict, and the resolution fails."
  (let ((target (reduce #'max levels :initial-value 0)))
    (when (zerop target)
      (fail resolution))
    (with-slots (decisions) resolution
      (loop while (> (decision-level (first decisions)) target)
            do (pop decisions))
      (let ((decision (first decisions)))
        (setf (decision-conflict-levels decision)
              (union (remove target levels) (decision-conflict-levels decision)))))))

(defun decide (resolution)
  "Chooses a release for the package of the most recent decision, going
back to earlier decisions as conflicts require, until a release is
chosen without a conflict. Returns that release."
  (with-slots (decisions steps) resolution
    (loop
      (let ((decision (first decisions)))
        (undo-to resolution (decision-mark decision))
        (let ((release (pop (decision-candidates decision)))
              (package (decision-package decision)))
          (cond ((and (null release) (zerop (decision-tried decision)))
                 ;; Nothing to try at all.
                 (backjump resolution
                           (conflict-levels
                            (record-conflict
                             resolution
                             (make-conflict (if (package-known-p (resolution-registry resolution)
                                                                 package)
                                                :no-release
                                                :unknown-package)
                                            package
                                            (requirements-on resolution package)
                                            (requirement-levels resolution package))))))
                ((null release)
                 (backjump resolution (union (decision-conflict-levels decision)
                                             (requirement-levels resolution package))))
                (t
                 (when (> (incf steps) *step-limit*)
                   (fail resolution (format nil "it gave up after trying ~D releases."
                                            *step-limit*)))
                 (incf (decision-tried decision))
                 (let ((conflict (select resolution decision release)))
                   (if conflict
                       (backjump resolution
                                 (conflict-levels (record-conflict resolution conflict)))
                       (return release))))))))))

(defun next-package (resolution)
  "Returns the first package in the order required that is not decided
yet, or NIL."
  (with-slots (order selected) resolution
    (find-if-not (lambda (package) (nth-value 1 (gethash package selected)))
                 order)))

(defun resolve (registry requirements &key preferred as-of project-name)
  "Returns a release from REGISTRY for each package that REQUIREMENTS
need, directly or through the dependencies of the releases chosen, as a
list sorted by package name. PREFERRED is an alist from package name to
the version to try first, as a previous lock has. With AS-OF, a day as
\"2025-06-30\", releases published after it are left out.

A requirement on a package the registry does not have signals
UNKNOWN-PACKAGE, with a SKIP-REQUIREMENT restart. When no choice of
releases satisfies every requirement, RESOLVE signals RESOLUTION-FAILED."
  (let ((resolution (make-instance 'resolution :registry registry
                                               :as-of as-of
                                               :project-name project-name
                                               :preferred (alexandria:alist-hash-table
                                                           (mapcar (lambda (entry)
                                                                     (cons (car entry)
                                                                           (ensure-version (cdr entry))))
                                                                   preferred)
                                                           :test 'equal))))
    (with-slots (decisions selected trail-length) resolution
      (dolist (requirement requirements)
        (when (or (package-known-p registry (requirement-package requirement))
                  (restart-case (error 'unknown-package :name (requirement-package requirement))
                    (skip-requirement ()
                      :report "Resolve without the requirement on the unknown package."
                      nil)))
          (alexandria:when-let ((conflict (add-requirement resolution requirement)))
            (record-conflict resolution conflict)
            (fail resolution))))
      (loop for package = (next-package resolution)
            while package
            do (push (make-decision (1+ (length decisions)) package
                                    (candidates resolution package) trail-length)
                     decisions)
               (decide resolution))
      (sort (mapcar #'car (alexandria:hash-table-values selected))
            #'string< :key #'release-package))))
