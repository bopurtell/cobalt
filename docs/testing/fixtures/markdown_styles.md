Cursor anchor: keep the cursor here to inspect the styled examples below.

# Heading level one
## Heading level two
### Heading level three
#### Heading level four
##### Heading level five
###### Heading level six

Setext heading one
==================

Setext heading two
------------------

Plain prose with *emphasis*, **strong text**, and `inline code`.
Unicode stays intact: café, 界, é, and 👍🏽.

[Visible link label](https://example.invalid/path "Visible title")
[Reference link label][example-reference]

[example-reference]: https://example.invalid/reference "Reference title"

> A quotation with **strong text**.
> The next line remains ordinary editable source.

- A list item with *emphasis*.
- [ ] An unchecked task.
- [x] A checked task.
1. An ordered item with `inline code`.

```ocaml
let literal = "*not emphasis* [not a link](https://example.invalid)"
let tab_and_unicode = "界 café"
```

~~~text
This fenced block has no embedded-language highlighting.
**These stars and the fence markers must stay visible.**
~~~

| Column | Value |
| --- | ---: |
| short | 1 |
| a longer source cell | 200 |

The table above deliberately remains source-shaped, without visual alignment.
No URL in this file should be opened or fetched by rendering.
