(in-package #:trove/tests)

(in-suite :trove)

(test search-terms-and-phrases
  (let ((index (small-index)))
    (is (equal '("a4" "a1" "a5") (ids index "cranes")))
    (is (equal '("a1" "a5") (ids index "harbour cranes")) "every word must match")
    (is (equal '("a1") (ids index "\"harbour cranes\"")))
    (is (equal '("a1") (ids index "\"cranes at the harbour\"")) "stop words keep their places")
    (is (null (ids index "\"harbour the cranes\"")))
    (is (equal '("a4" "a1") (ids index "title:crane")) "crane and cranes")
    (is (equal '("a1") (ids index "title:\"harbour cranes\"")))
    (is (equal '("a5" "a1") (ids index "body:\"harbour budget\" OR body:idle")))))

(test search-boolean
  (let ((index (small-index)))
    (is (equal '("a2" "a3") (sort (ids index "storm -cranes") #'string<)))
    (is (equal '("a1" "a2" "a3") (sort (ids index "storm") #'string<)))
    (is (equal '("a1" "a2" "a3" "a6") (sort (ids index "storm OR skiing") #'string<)))
    (is (equal '("a3" "a6") (sort (ids index "(ferry OR snow) -gale") #'string<)))
    (is (equal '("a1" "a2") (sort (ids index "storm AND +port") #'string<)))
    (is (null (ids index "-storm")) "exclusions alone match nothing")
    (is (= 6 (count-matches index "the")) "a query of stop words matches every document")
    (is (= 3 (count-matches index "storms")))))

(test search-syntax
  (let ((index (small-index)))
    (dolist (query '("\"harbour cranes" "(storm OR ferry" "storm)" "" "OR" "title:"))
      (signals query-syntax-error (search-index index query)))))

(test ranking
  (let ((index (small-index)))
    ;; A word in the title counts more than in the body.
    (is (string= "a2" (first (ids index "warning OR ferries"))))
    (let ((hits (search-index index "harbour" :limit 2)))
      (is (= 2 (length hits)))
      (is (>= (hit-score (first hits)) (hit-score (second hits)))))))

(test snippets
  (let ((index (small-index)))
    (is (string= "... by the [storm] and a low [tide] ..."
                 (snippet index (get-document index "a3") "storm tide" :width 7)))
    (is (string= "Heavy snow let ..."
                 (snippet index (get-document index "a6") "nothing" :width 3)))))
