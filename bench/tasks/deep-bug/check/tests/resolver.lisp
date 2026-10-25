(in-package #:depot/tests)

(in-suite :depot)

(test resolve-newest
  (let ((registry (test-registry '("app" "1.0.0" ("log" "^1.0.0"))
                                 '("log" "1.0.0") '("log" "1.3.0") '("log" "2.0.0"))))
    (is (equal '("app 1.0.0" "log 1.3.0") (resolved registry '("app" "*"))))
    (is (equal '("app 1.0.0" "log 1.0.0") (resolved registry '("app" "*") '("log" "~1.0.0"))))))

(test resolve-backtracks
  ;; a 2.0.0 wants c 2, which b's only release does not allow: a 1.0.0.
  (let ((registry (test-registry '("a" "1.0.0" ("c" "^1.0.0")) '("a" "2.0.0" ("c" "^2.0.0"))
                                 '("b" "1.0.0" ("c" "^1.0.0"))
                                 '("c" "1.0.0") '("c" "1.5.0") '("c" "2.0.0"))))
    (is (equal '("a 1.0.0" "b 1.0.0" "c 1.5.0") (resolved registry '("a" "*") '("b" "*"))))))

(test resolve-backjumps
  ;; x has no release that z 1's requirement allows; the decisions on the
  ;; unrelated packages between them are not worth trying again, and the
  ;; resolver does not: it tries z's next release straight away.
  (let ((registry (apply #'test-registry
                         '("z" "2.0.0" ("x" "^2.0.0")) '("z" "1.0.0" ("x" "^1.0.0"))
                         '("x" "1.0.0")
                         (loop for i from 1 to 12
                               append (loop for minor from 0 to 9
                                            collect (list (format nil "p~D" i)
                                                          (format nil "1.~D.0" minor)))))))
    (let ((*step-limit* 200))
      (is (member "z 1.0.0"
                  (apply #'resolved registry '("z" "*")
                         (loop for i from 1 to 12
                               collect (list (format nil "p~D" i) "^1.0.0")))
                  :test #'string=)))))

(test resolve-yanked-and-prereleases
  (let ((registry (test-registry '("a" "1.0.0") '("a" "1.1.0" :yanked) '("a" "1.2.0-beta.1"))))
    (is (equal '("a 1.0.0") (resolved registry '("a" "^1.0.0"))))
    (is (equal '("a 1.2.0-beta.1") (resolved registry '("a" "^1.2.0-beta.1"))))
    (is (equal '("a 1.1.0")
               (mapcar #'release-name
                       (resolve registry (requirements '("a" "^1.0.0"))
                                :preferred '(("a" . "1.1.0")))))
        "a yanked release stays when it was locked before")))

(test resolve-as-of
  (let ((registry (make-registry)))
    (add-release registry "a" "1.0.0" :published "2024-01-10")
    (add-release registry "a" "1.1.0" :published "2024-06-01")
    (is (equal '("a 1.0.0")
               (mapcar #'release-name
                       (resolve registry (requirements '("a" "^1.0.0")) :as-of "2024-03-01"))))))

(test resolve-development-dependencies
  (let ((registry (test-registry '("a" "1.0.0" ("b" "^1.0.0") ("t" "^1.0.0" :kind :development))
                                 '("b" "1.0.0") '("t" "1.0.0"))))
    (is (equal '("a 1.0.0" "b 1.0.0") (resolved registry '("a" "*"))))))

(test resolve-failures
  (let ((registry (test-registry '("a" "1.0.0" ("c" "^1.0.0")) '("b" "1.0.0" ("c" "^2.0.0"))
                                 '("c" "1.0.0") '("c" "2.0.0")
                                 '("d" "1.0.0" ("gone" "^1.0.0")))))
    (let ((failure (handler-case (resolve registry (requirements '("a" "*") '("b" "*")))
                     (resolution-failed (condition) condition))))
      (is (typep failure 'resolution-failed))
      (let ((conflict (first (resolution-failed-conflicts failure))))
        (is (string= "c" (conflict-package conflict)))
        (is (string= "No release of c satisfies ^1.0.0 (a 1.0.0), ^2.0.0 (b 1.0.0)."
                     (describe-conflict conflict)))))
    (signals resolution-failed (resolve registry (requirements '("d" "*"))))
    (signals unknown-package (resolve registry (requirements '("nothing" "^1.0.0"))))
    (is (equal '("a 1.0.0" "c 1.0.0")
               (handler-bind ((unknown-package #'skip-requirement))
                 (resolved registry '("a" "*") '("nothing" "^1.0.0")))))))

(test resolve-excludes-selected
  ;; c is decided before b requires a version of it c 1.5.0 is not.
  (let ((registry (test-registry '("a" "1.0.0" ("c" "^1.0.0") ("b" "^1.0.0"))
                                 '("b" "1.0.0" ("c" "~1.2.0"))
                                 '("c" "1.2.4") '("c" "1.5.0"))))
    (is (equal '("a 1.0.0" "b 1.0.0" "c 1.2.4") (resolved registry '("a" "*"))))))

(test lock-the-blog
  (let ((lock (lock-project (project-file "examples/blog.sexp")
                            (load-registry (project-file "registry/")))))
    (is (string= "blog" (lock-project-name lock)))
    (is (= 38 (length (lock-entries lock))))
    (is (string= "1.5.1" (lock-version lock "markdown")))
    (is (string= "2.1.0" (lock-version lock "feeds")))
    (is (string= "2.0.0" (lock-version lock "sqlite")))
    (is (string= "2.2.1" (lock-version lock "test-harness")))
    (is (string= "1.3.0" (lock-version lock "text-utils")))
    (is (null (lock-version lock "html-escape")))))
