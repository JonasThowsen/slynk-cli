(in-package #:depot/tests)

(in-suite :depot)

(test parse-version
  (let ((version (parse-version "1.4.2")))
    (is (= 1 (version-major version)))
    (is (= 4 (version-minor version)))
    (is (= 2 (version-patch version)))
    (is (null (version-prerelease version))))
  (is (equal '("rc" 1) (version-prerelease (parse-version "2.0.0-rc.1"))))
  (is (equal "build.5" (version-build (parse-version "1.0.0+build.5"))))
  (is (equal '("alpha-2") (version-prerelease (parse-version "1.0.0-alpha-2+x"))))
  (dolist (text '("2.0.0-rc.1" "1.0.0+build.5" "0.0.1" "10.20.30-alpha.beta.1+sha.5114f85"))
    (is (string= text (version-string (parse-version text)))))
  (dolist (text '("1.2" "1.2.3.4" "01.2.3" "1.02.3" "1.2.3-" "1.2.3-01" "1.2.3-a..b" "a.b.c" "" "1.2.3+"))
    (signals version-syntax-error (parse-version text))))

(test version-precedence
  ;; The example of the semver specification, in order.
  (let ((versions (mapcar #'parse-version
                          '("1.0.0-alpha" "1.0.0-alpha.1" "1.0.0-alpha.beta" "1.0.0-beta"
                            "1.0.0-beta.2" "1.0.0-beta.11" "1.0.0-rc.1" "1.0.0"))))
    (loop for (a b) on versions
          while b
          do (is (version< a b) "~A should come before ~A" a b)
             (is (not (version< b a)))))
  (is (version< "1.9.0" "1.10.0"))
  (is (version< "1.10.0" "2.0.0"))
  (is (version= "1.0.0+build.1" "1.0.0+build.2"))
  (is (version<= "1.0.0" "1.0.0"))
  (is (version> "2.0.0-rc.1" "1.99.99"))
  (is (= 0 (compare-versions "3.1.4" "3.1.4"))))
