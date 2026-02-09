#let apply-style(body) = {
  // page style
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

  // style for paragraphs
  set par(
    justify: true,
    first-line-indent: (
      amount: 1.5em,
      all: true,
    ),
  )

  // style for heading 1
  show heading.where(level: 1): it => {
    align(center)[#block(it.body)]
    block(
      width: 100%,
      stroke: (bottom: 1pt + black),
      inset: (bottom: 5pt),
      above: 1mm,
      below: 1mm,
    )
  }

  body
}
