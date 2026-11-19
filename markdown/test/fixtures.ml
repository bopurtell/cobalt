let features = {markdown|# First
## Second
### Third
#### Fourth
##### Fifth
###### Sixth

Setext one
==========

Setext two
----------

*emphasis* and **strong**, `code|span`, [label](https://example.test/a?b=c).

> quoted *across
> continuation* text

- [x] done
- [ ] todo
1. ordered
2) parenthesized
   - nested **item**

```ocaml
*not emphasis* [not a link](https://example.test)
```
|markdown}

let unicode = {markdown|# Héllo 世界

**é😀** and *λ* with [标签](https://例子.test/路径) and `é|界`.
|markdown}

let tables = {markdown|| *head* | second |
| :--- | ---: |
| **bold** | a\|b |
| `a\|b` | [label](https://example.test) |
|markdown}

let malformed =
  [ ""
  ; "*"
  ; "**unclosed"
  ; "[missing] [x](unfinished"
  ; "```unclosed\n*still code*\n"
  ; "> quote\n>\n> *unfinished"
  ; "- [x\n  nested\n"
  ; "| a | b |\n| --- | --- |\n| `a|b` | x |\n"
  ; "<script>alert('raw only')</script>\n"
  ; "[unresolved][ref]\n\n[ref]: https://example.test\n"
  ]
;;
