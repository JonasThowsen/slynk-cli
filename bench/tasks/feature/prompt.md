The current directory is `timesheet`, our payroll system (see its
README). We need it to pay public holidays properly before the Easter
payroll run.

Hourly employees who work on a public holiday get a holiday rate for those
hours, double pay by default. Please add this:

- **Holiday calendar.** `(make-holiday-calendar)` returns an empty calendar.
  `(add-holiday calendar date name)` makes DATE (a `date`, as from
  `parse-date`) the holiday NAME (a string) and returns CALENDAR; adding a
  date that is already there replaces its name. `(holiday-name calendar
  date)` returns the name of the holiday on DATE, or NIL if it isn't one.
- **Rules.** `make-pay-rules` takes two more keywords: `:holidays`, a holiday
  calendar or NIL (the default, no holidays), and `:holiday-multiplier`, the
  holiday pay as a multiple of the hourly rate, default 2. The rules get the
  readers `holidays` and `holiday-multiplier`.
- **Pay.** For an hourly employee, all hours on a date that is a holiday in
  the rules' calendar are holiday hours: they are paid at hourly rate ×
  holiday multiplier, they are neither regular nor overtime hours, and they
  do not count towards the daily or the weekly overtime threshold. Gross pay
  is regular × rate + overtime × rate × overtime multiplier + holiday × rate
  × holiday multiplier, rounded to whole cents once, as now. Contractors
  and salaried employees are paid exactly as now, also on holidays.
- **Pay lines.** A pay line has the holiday hours as
  `pay-line-holiday-hours`, which is 0 when there are none (and always for
  contractors and salaried employees).
- **Totals.** `payroll-totals` returns
  `(:regular-hours R :overtime-hours O :holiday-hours H :gross G)`, in that
  order.
- **Report.** `write-payroll-report` gets a `Holiday` column between
  `Overtime` and `Gross`, formatted like the `Overtime` column, on every
  line including the totals. With Maundy Thursday (2026-04-02) and Good
  Friday (2026-04-03) as holidays, Alice (20.00 an hour) working 8 hours on
  1 April and 8 on 2 April, and Bob (30.00 an hour) 4 hours on 3 April, the
  April report is:

  ```
  Id       Name                   Regular  Overtime   Holiday       Gross
  alice    Alice Berg                8.00      0.00      8.00      480.00
  bob      Bob Moe                   0.00      0.00      4.00      240.00
           Total                     8.00      0.00     12.00      720.00
  ```

The new functions and readers are exported from the `timesheet` package.
Without holidays in the rules, pay is computed exactly as it is today. Add
tests for the holiday pay to the test suite, and keep the existing tests
passing; only the tests of the totals and of the report need to change for
the new key and column.
