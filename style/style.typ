#let apply-style(body) = {
  set page(
    margin: (
      left: 2cm,
      right: 1.5cm,
      top: 1cm,
      bottom: 1cm,
    ),
  )

  set text(
    font: "Times New Roman",
    size: 12pt,
  )

  set par(
    justify: true,
    first-line-indent: (
      amount: 1.5em,
      all: true,
    ),
  )

  body
}
