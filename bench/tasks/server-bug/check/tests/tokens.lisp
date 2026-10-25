(in-package #:spool/tests)
(in-suite :spool)

(test split-tokens
  (is (equal '() (spool:split-tokens "")))
  (is (equal '("STATUS" "12") (spool:split-tokens "STATUS 12")))
  (is (equal '("a" "b") (spool:split-tokens "  a   b  ")))
  (is (equal '("echo" "hello world" "") (spool:split-tokens "echo \"hello world\" \"\"")))
  (is (equal '("say \"hi\"" "back\\slash")
             (spool:split-tokens "\"say \\\"hi\\\"\" \"back\\\\slash\"")))
  (signals spool-error (spool:split-tokens "echo \"open")))

(test quote-token
  (is (string= "plain" (spool:quote-token "plain")))
  (is (string= "\"two words\"" (spool:quote-token "two words")))
  (is (string= "\"\"" (spool:quote-token "")))
  (is (string= "OK 3 done" (spool:join-tokens '("OK" 3 :done))))
  (let ((tokens '("SUBMIT" "q" "echo" "a \"quoted\" word" "back\\slash" "" "æøå")))
    (is (equal tokens (spool:split-tokens (spool:join-tokens tokens))))))
