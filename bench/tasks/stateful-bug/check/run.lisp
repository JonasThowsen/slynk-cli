;;;; Loads the trove in CHECK_DIR, then the project's tests and the tests
;;;; of the reported case from their copies in CHECK_WORK, and runs them.
;;;; Exits 0 when all pass.

(require :asdf)

(defvar *dir* (uiop:getenv "CHECK_DIR"))
(defvar *work* (uiop:getenv "CHECK_WORK"))

(setf *print-right-margin* 200)

(defun fail (control &rest arguments)
  (format t "~&FAIL: ~?~%" control arguments)
  (finish-output)
  (uiop:quit 1))

(asdf:initialize-source-registry
 `(:source-registry (:tree ,*dir*) :inherit-configuration))
(asdf:initialize-output-translations
 `(:output-translations (,*dir* ,(concatenate 'string *work* "fasl/"))
                        :inherit-configuration))

(defun quietly-load-system (name)
  (handler-case
      (let ((*standard-output* (make-broadcast-stream))
            (*error-output* (make-broadcast-stream)))
        (asdf:load-system name))
    (error (e) (fail "~A does not load: ~A" name e))))

(quietly-load-system :trove)
(unless (uiop:subpathp (asdf:system-source-directory :trove)
                       (uiop:parse-native-namestring *dir*))
  (fail "trove was loaded from ~A, not from the project"
        (asdf:system-source-directory :trove)))
(quietly-load-system :fiveam)

(handler-case
    (let ((*standard-output* (make-broadcast-stream))
          (*error-output* (make-broadcast-stream)))
      (dolist (file '("package" "text" "index" "search" "sample"
                      "reported" "model"))
        (load (concatenate 'string *work* "tests/" file ".lisp"))))
  (error (e) (fail "the tests do not load: ~A" e)))

(defun one-line (string)
  "STRING with each run of whitespace in it made one space."
  (format nil "~{~A~^ ~}"
          (remove "" (uiop:split-string string :separator '(#\Space #\Tab #\Newline))
                  :test #'string=)))

(let* ((results (let ((*standard-output* (make-broadcast-stream))
                      (fiveam:*on-error* nil)
                      (fiveam:*on-failure* nil))
                  (fiveam:run :trove)))
       (failed (remove-if (lambda (result) (typep result 'fiveam::test-passed))
                          results)))
  (when (or (null results) failed)
    (fail "~D of ~D checks fail:~{~%  ~A~}"
          (length failed) (length results)
          (let ((names (remove-duplicates
                        (mapcar (lambda (result)
                                  (let ((reason (one-line (princ-to-string
                                                           (fiveam::reason result)))))
                                    (format nil "~(~A~): ~A"
                                            (fiveam::name (fiveam::test-case result))
                                            (subseq reason 0 (min 300 (length reason))))))
                                failed)
                        :test #'string=)))
            (subseq names 0 (min 10 (length names))))))
  (format t "~&PASS: the reported case, the related ones and the project's tests pass (~D checks)~%"
          (length results)))
(uiop:quit 0)
