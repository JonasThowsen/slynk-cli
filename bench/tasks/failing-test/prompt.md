The current directory is our billing system (see `README.md`). Since a
recent change, the test `discounted-invoice-total` fails: the total of a
wholesale customer's invoice comes out one øre too high. The other tests
pass.

Please find out why and fix the code, not the test. Done means the whole
test suite (`(asdf:test-system "billing")`) passes, with the tests as they
are now.
