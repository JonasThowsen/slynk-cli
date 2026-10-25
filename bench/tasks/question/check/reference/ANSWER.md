```
min-len: 13
start-anchored-p: NIL
starts-with: NIL
end-string: "-XY"
end-string-offset: 10
end-anchored-p: 0
clause: 7
```

1. `min-len` is `(regex-min-length regex)`: 2 for `[A-Z]{2}`, 1 for `-`,
   4 for `\d{4}`, 1 for `-`, 2 for `(?:ab|cd)` (the shorter choice) and 3
   for `-XY`, so 13.
2. `start-anchored-p` is `(start-anchored-p regex)`, NIL: the sequence
   starts with a repetition of a character class, not with `^` or `\A`;
   and `starts-with` is not an EVERYTHING in single-line mode.
3. `starts-with` comes from `convert`: the regex starts with a character
   class, not a constant string, so it is NIL and there is no
   `start-string-test`.
4. `end-string` walks the sequence from the end: `\z` is zero-length, then
   the string `-XY` is collected; the alternation stops the collection,
   so the end string is `"-XY"` (and `end-string-test` is a BMH matcher
   for it, since it is longer than one character).
5. `end-string-offset` is the `offset` of that STR, set by
   `compute-offsets`: everything before it has a fixed length,
   2 + 1 + 4 + 1 + 2 = 10.
6. `\z` is a "real" end anchor that admits no final newline, seen before
   anything was collected, so `end-string-aux` sets `end-anchored-p` to 0
   (1 would allow a trailing #\Newline); it is passed on because there is
   an end-string test.
7. There is no `start-string-test` and `starts-with` is not an EVERYTHING,
   so the first six clauses do not apply, and the seventh,
   `(end-string-test ...)`, builds the scanner.
