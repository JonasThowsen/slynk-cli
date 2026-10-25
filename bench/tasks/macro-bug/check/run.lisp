;;;; Loads the stockfile in CHECK_DIR, then the project's tests and the
;;;; tests of the reported case from their copies in CHECK_WORK, and runs
;;;; them. Exits 0 when all pass.

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

(quietly-load-system :stockfile)
(unless (uiop:subpathp (asdf:system-source-directory :stockfile)
                        (uiop:parse-native-namestring *dir*))
  (fail "stockfile was loaded from ~A, not from the project"
        (asdf:system-source-directory :stockfile)))
(quietly-load-system :fiveam)

(handler-case
    (let ((*standard-output* (make-broadcast-stream))
          (*error-output* (make-broadcast-stream)))
      (dolist (file '("tests" "reported"))
        (load (concatenate 'string *work* "tests/" file ".lisp"))))
  (error (e) (fail "the tests do not load: ~A" e)))

(defun one-line (string)
  "STRING with each run of whitespace in it made one space."
  (format nil "~{~A~^ ~}"
          (remove "" (uiop:split-string string :separator '(#\Space #\Tab #\Newline))
                  :test #'string=)))

(let* ((log (make-string-output-stream))
       (results (let ((*standard-output* log)
                      (fiveam:*on-error* nil)
                      (fiveam:*on-failure* nil))
                  (fiveam:run :stockfile)))
       (failed (remove-if (lambda (result) (typep result 'fiveam::test-passed))
                          results)))
  (when (or (null results) failed)
    (fail "~D of ~D checks fail:~{~%  ~A~}"
          (length failed) (length results)
          (let ((names (remove-duplicates
                        (mapcar (lambda (result)
                                  (format nil "~(~A~): ~A"
                                          (fiveam::name (fiveam::test-case result))
                                          (one-line (princ-to-string
                                                     (fiveam::reason result)))))
                                failed)
                        :test #'string=)))
            (subseq names 0 (min 10 (length names)))))))

(format t "~&PASS: the project's tests and the reported case pass~%")
(uiop:quit 0)
