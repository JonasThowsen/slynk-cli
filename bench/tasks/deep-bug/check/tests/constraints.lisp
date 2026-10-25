(in-package #:depot/tests)

(in-suite :depot)

(defun set-of (text)
  "Returns the version set of the constraint TEXT, as a text."
  (version-set-string (constraint-version-set (parse-constraint text))))

(test constraint-ranges
  (is (string= ">=1.2.3 <2.0.0-0" (set-of "^1.2.3")))
  (is (string= ">=0.2.3 <0.3.0-0" (set-of "^0.2.3")))
  (is (string= ">=0.0.3 <0.0.4-0" (set-of "^0.0.3")))
  (is (string= ">=1.2.0 <2.0.0-0" (set-of "^1.2")))
  (is (string= ">=0.0.0 <0.1.0-0" (set-of "^0.0")))
  (is (string= ">=1.2.3 <1.3.0-0" (set-of "~1.2.3")))
  (is (string= ">=1.0.0 <2.0.0-0" (set-of "~1")))
  (is (string= ">=1.2.0 <1.3.0-0" (set-of "1.2")))
  (is (string= ">=1.2.0 <1.3.0-0" (set-of "1.2.x")))
  (is (string= ">=1.0.0 <2.0.0-0" (set-of "1.x")))
  (is (string= "=1.2.3" (set-of "1.2.3")))
  (is (string= "=1.2.3" (set-of "=1.2.3")))
  (is (string= "*" (set-of "*")))
  (is (string= "*" (set-of "")))
  (is (string= ">=1.2.0 <3.0.0" (set-of ">=1.2 <3.0.0")))
  (is (string= ">1.2.3" (set-of ">1.2.3")))
  (is (string= "<=1.2.3" (set-of "<=1.2.3")))
  (is (string= ">=1.2.3 <2.4.0-0" (set-of "1.2.3 - 2.3")))
  (is (string= ">=1.2.3 <=2.3.4" (set-of "1.2.3 - 2.3.4"))))

(test constraint-alternatives
  (is (string= ">=1.0.0 <2.0.0-0 || >=3.0.0 <4.0.0-0" (set-of "^1.0.0 || ^3.0.0")))
  (is (string= ">=1.0.0 <2.0.0" (set-of ">=1.0.0 <1.5.0 || >=1.4.0 <2.0.0")))
  (is (string= ">=1.0.0 <3.0.0" (set-of ">=1.0.0 <2.0.0 || >=2.0.0 <3.0.0")))
  (is (satisfies-p "3.4.0" "^1.0.0 || ^3.0.0"))
  (is (not (satisfies-p "2.4.0" "^1.0.0 || ^3.0.0"))))

(test constraint-syntax
  (dolist (text '("^1.x.3" ">=*" "1.2.3.4" "^" ">= 1.2.3" "1.2 -" "abc" "1.2-beta"))
    (signals constraint-syntax-error (parse-constraint text))))

(test satisfies
  (is (satisfies-p "1.9.9" "^1.2.3"))
  (is (not (satisfies-p "2.0.0" "^1.2.3")))
  (is (not (satisfies-p "1.2.2" "^1.2.3")))
  (is (satisfies-p "0.2.9" "^0.2.3"))
  (is (not (satisfies-p "0.3.0" "^0.2.3")))
  (is (satisfies-p "1.2.9" "~1.2.3"))
  (is (not (satisfies-p "1.3.0" "~1.2.3")))
  (is (satisfies-p "1.4.0" ">1.3.9"))
  (is (satisfies-p "2.3.4" "1.2.3 - 2.3.4"))
  (is (not (satisfies-p "2.3.5" "1.2.3 - 2.3.4"))))

(test satisfies-prereleases
  (is (satisfies-p "2.0.0-rc.2" "^2.0.0-rc.1"))
  (is (not (satisfies-p "2.0.0-rc.1" "^2.0.0-rc.2")))
  (is (not (satisfies-p "2.0.0-rc.2" "^1.0.0")))
  (is (not (satisfies-p "1.5.0-beta" "^1.0.0")) "a prerelease needs a constraint that names one")
  (is (not (satisfies-p "2.0.0-beta" "^1.0.0-alpha")) "^ stops before the next major's prereleases")
  (is (not (satisfies-p "1.0.0-alpha" "<1.0.0"))))

(test version-set-operations
  (let ((a (constraint-version-set (parse-constraint "^1.2.0")))
        (b (constraint-version-set (parse-constraint ">=1.5.0 <3.0.0")))
        (c (constraint-version-set (parse-constraint "^2.0.0"))))
    (is (string= ">=1.5.0 <2.0.0-0" (version-set-string (version-set-intersection a b))))
    (is (version-set-empty-p (version-set-intersection a c)))
    (is (string= ">=1.2.0 <3.0.0" (version-set-string (version-set-union a b))))
    (is (version-set-contains-p (version-set-union a c) "2.5.0"))
    (is (version-set-equal a (constraint-version-set (parse-constraint "^1.2"))))
    (is (not (version-set-equal a b)))
    (is (string= ">=1.2.0 <2.0.0-0" (version-set-string a)) "the operations leave A as it was")
    (is (string= ">=1.5.0 <3.0.0" (version-set-string b)) "and B")))

(test narrow-version-set
  (let* ((set (copy-version-set (constraint-version-set (parse-constraint "^1.0.0"))))
         (narrowed (narrow-version-set set (constraint-version-set (parse-constraint ">=1.3.0")))))
    (is (eq set narrowed))
    (is (string= ">=1.3.0 <2.0.0-0" (version-set-string set)))
    (narrow-version-set set (constraint-version-set (parse-constraint "<1.0.0")))
    (is (version-set-empty-p set))))
