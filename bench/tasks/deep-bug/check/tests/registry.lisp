(in-package #:depot/tests)

(in-suite :depot)

(test add-release
  (let ((registry (test-registry '("a" "1.0.0") '("a" "1.2.0" ("b" "^1.0.0"))
                                 '("a" "1.1.0" :yanked) '("b" "1.0.0"))))
    (is (equal '("a" "b") (registry-package-names registry)))
    (is (equal '("a 1.2.0" "a 1.1.0" "a 1.0.0")
               (mapcar #'release-name (package-releases registry "a")))
        "the releases are kept newest first")
    (is (release-yanked-p (find-release registry "a" "1.1.0")))
    (is (null (find-release registry "a" "2.0.0")))
    (is (null (package-releases registry "c")))
    (let ((dependency (first (release-dependencies (find-release registry "a" "1.2.0")))))
      (is (string= "b" (dependency-package dependency)))
      (is (string= "^1.0.0" (constraint-text (dependency-constraint dependency))))
      (is (eq :runtime (dependency-kind dependency))))
    (signals registry-error (add-release registry "a" "1.0.0"))
    (signals registry-error (add-release registry "a" "3.0.0" :dependencies '(("b"))))))

(test dependency-texts-are-parsed-once
  (let* ((registry (test-registry '("a" "1.0.0" ("c" "^1.0.0")) '("b" "1.0.0" ("c" "^1.0.0"))
                                  '("c" "1.0.0")))
         (a (first (release-dependencies (find-release registry "a" "1.0.0"))))
         (b (first (release-dependencies (find-release registry "b" "1.0.0")))))
    (is (eq (dependency-constraint a) (dependency-constraint b)))))

(test bad-dependency-text
  (let ((registry (test-registry '("a" "1.0.0" ("b" "^1.x.2")) '("b" "1.0.0"))))
    (signals registry-error (release-dependencies (find-release registry "a" "1.0.0")))))

(test load-registry
  (let ((registry (load-registry (project-file "registry/"))))
    (is (< 100 (length (registry-package-names registry))))
    (is (equal '("2.5.0-beta.1" "2.4.1" "2.4.0" "2.3.0" "2.2.0" "2.1.0" "2.0.0")
               (mapcar (lambda (release) (version-string (release-version release)))
                       (package-releases registry "html-escape"))))
    (is (release-yanked-p (find-release registry "html-escape" "2.4.0")))
    (is (string= "2025-06-05" (depot.registry:release-published
                               (find-release registry "html-escape" "2.4.1"))))
    (is (equal '("unicode")
               (mapcar #'dependency-package
                       (release-dependencies (find-release registry "html-escape" "2.4.1")))))))

(test load-registry-errors
  (let ((directory (merge-pathnames (format nil "depot-test-~36R/"
                                            (random (expt 36 8) (make-random-state t)))
                                    (uiop:temporary-directory))))
    (ensure-directories-exist directory)
    (unwind-protect
         (progn
           (with-open-file (stream (merge-pathnames "good.sexp" directory) :direction :output)
             (write-string "(:package \"good\" :releases ((:version \"1.0.0\")))" stream))
           (with-open-file (stream (merge-pathnames "bad.sexp" directory) :direction :output)
             (write-string "(:package \"bad\" :releases ((:version \"1.0\")))" stream))
           (signals registry-error (load-registry directory))
           (let ((registry (handler-bind ((registry-error #'skip-package))
                             (load-registry directory))))
             (is (equal '("good") (registry-package-names registry)))))
      (uiop:delete-directory-tree directory :validate t))))
