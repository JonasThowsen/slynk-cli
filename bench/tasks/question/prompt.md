The current directory is a checkout of cl-ppcre, the Perl-compatible regex
library. A colleague asks:

> I'm trying to understand how cl-ppcre avoids trying a regex at every
> position of the target. As far as I can tell, `create-scanner` works out
> a few facts about the regex and passes them to `create-scanner-aux`,
> which picks a way to advance through the target. Take this regex (here
> as a Lisp string):
>
> ```lisp
> "[A-Z]{2}-\\d{4}-(?:ab|cd)-XY\\z"
> ```
>
> For it, what does `create-scanner` pass to `create-scanner-aux` as
>
> 1. `min-len`,
> 2. `start-anchored-p`,
> 3. `starts-with`: the constant string the regex starts with, or NIL,
> 4. the end string: the constant string the regex ends with, which
>    `end-string-test` searches for, or NIL,
> 5. `end-string-offset`,
> 6. `end-anchored-p`,
>
> and 7. which clause of the `cond` in `create-scanner-aux`, counting the
> clauses from 1, builds the scanner?

Write the answer in `ANSWER.md` at the top of the project. Begin it with
these seven lines, each value on its line as Lisp would print it (a string
in double quotes, NIL for none):

```
min-len: ...
start-anchored-p: ...
starts-with: ...
end-string: ...
end-string-offset: ...
end-anchored-p: ...
clause: ...
```

Then explain each value in a sentence or two: where in the code it comes
from and why it has that value for this regex. Don't change the library.
