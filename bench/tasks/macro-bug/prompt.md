The current directory is stockfile, our library for reading the files the
warehouse exports. Last week I added a record format for the webshop's
order exports to `src/formats.lisp`:

```lisp
(define-record-format order-line ()
  "One line of an order exported from the webshop."
  (order-id "Order" :type :integer)
  (line "Line" :type :integer)
  (sku "SKU")
  (quantity "Qty" :type :integer :check (plusp quantity)))
```

Reading the orders works, but the errors point at the wrong line. With
this `orders.csv`:

```
Order,Line,SKU,Qty
1001,1,A-100,2
1001,2,B-200,1
1002,1,A-100,0
```

`(stockfile:import-file "orders.csv" 'stockfile:order-line)` signals

```
Line 1, column "Qty": (PLUSP STOCKFILE::QUANTITY) does not hold
```

and `record-error-line` of the condition is 1, but the zero quantity is on
line 4 of the file. With `:on-error :collect` the collected error says
line 1 too. Errors in stock counts and price lists point at the right
lines.

Please fix this in the library. The format is right as it is: we name the
fields after the columns of the files we get, so don't rename the field.
Done means: errors from `order-line` files carry the line number in the
file, and the project's tests (the `stockfile/tests` system) still pass.
