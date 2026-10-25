;;;; Loads the timesheet system in CHECK_DIR, then runs the hidden tests
;;;; from their copy in CHECK_WORK. Exits 0 when all of them pass.

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

(quietly-load-system :timesheet)
(unless (uiop:subpathp (asdf:system-source-directory :timesheet)
                       (uiop:parse-native-namestring *dir*))
  (fail "timesheet was loaded from ~A, not from the project"
        (asdf:system-source-directory :timesheet)))
(quietly-load-system :fiveam)

;;; The hidden tests, loaded from source in their order.
(handler-case
    (let ((*standard-output* (make-broadcast-stream))
          (*error-output* (make-broadcast-stream)))
      (dolist (file '("package" "dates" "entries" "payroll" "holidays" "report"))
        (load (concatenate 'string *work* "tests/" file ".lisp"))))
  (error (e) (fail "the hidden tests do not load: ~A" e)))

(let* ((results (let ((*standard-output* (make-broadcast-stream)))
                  (fiveam:run (find-symbol "TIMESHEET" :timesheet-check))))
       (failures (remove-if-not (lambda (result)
                                  (typep result 'fiveam::test-failure))
                                results)))
  (when failures
    (fail "~D of ~D checks fail:~{~%  ~A~}"
          (length failures) (length results)
          (mapcar (lambda (failure)
                    (format nil "~A: ~A"
                            (fiveam::name (fiveam::test-case failure))
                            (let ((reason (remove #\Newline (fiveam::reason failure))))
                              (subseq reason 0 (min 160 (length reason))))))
                  (subseq failures 0 (min 12 (length failures))))))
  (format t "~&PASS: all ~D checks of the hidden tests pass~%" (length results)))
(uiop:quit 0)
