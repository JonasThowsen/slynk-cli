(in-package #:trove/tests)

(in-suite :trove)

(test tokenize
  (is (equal '("the" "harbour" "new" "crane" "a" "follow" "up" "don't" "stop" "2024")
             (mapcar #'token-text
                     (tokenize "The harbour's new crane, a follow-up: don't stop! 2024"))))
  (let ((tokens (tokenize "  Two  words")))
    (is (equal '(2 7) (mapcar #'token-start tokens)))
    (is (equal '(5 12) (mapcar #'token-end tokens)))
    (is (equal '(0 1) (mapcar #'token-position tokens))))
  (is (null (tokenize "")))
  (is (null (tokenize " -- ... !"))))

(test porter-stemmer
  ;; The examples of Porter's paper.
  (loop for (word stem) on '("caresses" "caress" "ponies" "poni" "ties" "ti" "caress" "caress"
                             "cats" "cat" "feed" "feed" "agreed" "agre" "plastered" "plaster"
                             "bled" "bled" "motoring" "motor" "sing" "sing" "conflated" "conflat"
                             "troubled" "troubl" "sized" "size" "hopping" "hop" "tanned" "tan"
                             "falling" "fall" "hissing" "hiss" "fizzed" "fizz" "failing" "fail"
                             "filing" "file" "happy" "happi" "sky" "sky" "relational" "relat"
                             "conditional" "condit" "rational" "ration" "valenci" "valenc"
                             "digitizer" "digit" "conformabli" "conform" "radicalli" "radic"
                             "differentli" "differ" "vileli" "vile" "analogousli" "analog"
                             "vietnamization" "vietnam" "predication" "predic" "operator" "oper"
                             "feudalism" "feudal" "decisiveness" "decis" "hopefulness" "hope"
                             "callousness" "callous" "formaliti" "formal" "sensitiviti" "sensit"
                             "sensibiliti" "sensibl" "triplicate" "triplic" "formative" "form"
                             "formalize" "formal" "electriciti" "electr" "electrical" "electr"
                             "hopeful" "hope" "goodness" "good" "revival" "reviv"
                             "allowance" "allow" "inference" "infer" "airliner" "airlin"
                             "gyroscopic" "gyroscop" "adjustable" "adjust" "defensible" "defens"
                             "irritant" "irrit" "replacement" "replac" "adjustment" "adjust"
                             "dependent" "depend" "adoption" "adopt" "homologou" "homolog"
                             "communism" "commun" "activate" "activ" "angulariti" "angular"
                             "homologous" "homolog" "effective" "effect" "bowdlerize" "bowdler"
                             "probate" "probat" "rate" "rate" "cease" "ceas" "controll" "control"
                             "roll" "roll" "generalizations" "gener" "oscillators" "oscil")
        by #'cddr
        do (is (string= stem (stem word)) "~A should stem to ~A, not ~A" word stem (stem word)))
  (is (string= "at" (stem "at")) "short words are their own stems"))

(test analyze
  (let ((analyzer (make-analyzer)))
    (is (equal '(("harbour" . 1) ("crane" . 2) ("idl" . 3) ("after" . 4) ("storm" . 6))
               (analyze analyzer "The harbour cranes idle after the storm")))
    (is (null (analyze analyzer "the and of")))
    (is (equal '(("harbours" . 0)) (analyze (make-analyzer :stemming nil) "Harbours")))))
