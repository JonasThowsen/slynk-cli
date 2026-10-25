(in-package #:depot.semver)

;;; Every error depot signals on purpose is a DEPOT-ERROR. The errors of
;;; the registry, the resolver and the lock are defined with them; these
;;; are the ones for texts that do not parse.

(define-condition depot-error (error)
  ()
  (:documentation "An error in depot's input or in resolving it."))

(define-condition syntax-error (depot-error parse-error)
  ((text :initarg :text :reader syntax-error-text)
   (reason :initarg :reason :reader syntax-error-reason))
  (:report (lambda (condition stream)
             (format stream "~S is not a valid ~A: ~A"
                     (syntax-error-text condition)
                     (syntax-error-what condition)
                     (syntax-error-reason condition))))
  (:documentation "A text that does not parse: the TEXT and the REASON."))

(defgeneric syntax-error-what (condition)
  (:documentation "What the text of CONDITION should have been, for its
report."))

(define-condition version-syntax-error (syntax-error) ()
  (:documentation "A text that is not a semantic version."))

(defmethod syntax-error-what ((condition version-syntax-error))
  "version")

(define-condition constraint-syntax-error (syntax-error) ()
  (:documentation "A text that is not a version constraint."))

(defmethod syntax-error-what ((condition constraint-syntax-error))
  "version constraint")
