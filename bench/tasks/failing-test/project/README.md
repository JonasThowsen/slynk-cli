# billing

Invoices for a small wholesale business: a product catalog, customers in
groups with discounts, Norwegian VAT categories with their rate history,
invoices and credit notes, and a plain-text rendering of an invoice.

Amounts are integers in øre (1/100 krone) everywhere; `parse-amount` and
`format-amount` convert from and to `"1234.50"`. Dates are day numbers;
`parse-date` and `format-date` convert from and to `"2026-03-01"`.

Run the tests with

```lisp
(asdf:test-system "billing")
```
