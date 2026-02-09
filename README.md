# Markdown → Typst → PDF

A Python command-line tool that converts Markdown documents into PDF using Typst.

The project was created as an alternative to the `markdown + wkhtmltopdf` workflow and is focused on:
- academic texts (reviews, reports, term papers)
- proper typography
- reproducible, clean PDF output without HTML rendering

---

## ✨ Features

- Markdown → Typst (`.typ`)
- Typst → PDF
- Word count
- Automatic PDF filename based on document title
- Safe filenames
- Supported Markdown formatting:
  - headings `#`, `##`, `###`
  - bold `**text**`
  - italic `*text*`
  - nested italic inside bold
  - unordered lists `- item`
- Typography:
  - justified paragraphs
  - first-line paragraph indent
  - language-aware hyphenation (configurable)

---

## 📂 Project Structure

```
md-to-typst/
├── in/
│   └── input.md          # input Markdown file
├── out-typst/
│   └── output.typ        # generated Typst file
├── out/
│   └── output.pdf        # final PDF
├── main-typst.py         # main script
└── README.md
```

---

## 🛠 Requirements

### 1. Python

- Python 3.9+

### 2. Typst

Install Typst and make sure it is available in your `PATH`:

https://typst.app/docs/reference/cli/

Check installation:
```bash
typst --version
```

---

## 🚀 Usage

1. Put your Markdown file into the `in/` directory and name it `input.md`

2. Run the script:
```bash
python main.py
```

3. The results will appear in the `out/` directory:
- `.typ` — intermediate Typst file
- `.pdf` — final PDF document

The word count is printed to the console.

---

## 🧾 Typography (Typst)

The following Typst settings are used in the document preamble:

```typst
#set page(margin: 2cm)
#set text(size: 11pt, lang: "uk")
#set par(
  justify: true,
  first-line-indent: 1.25cm
)
#set heading(
  following-par-indent: 0pt
)
```

This provides:
- justified text
- first-line paragraph indent
- no indent after headings
- proper hyphenation

---

## 🧠 Markdown Scope

This project is intentionally not a full Markdown parser.

Supported:
- `#`, `##`, `###`
- `**bold**`
- `*italic*`
- nested formatting: `**bold *italic***`
- unordered lists

Not supported:
- `***bold+italic***`
- inline code `` `code` ``
- links `[text](url)`
- tables

This design keeps the conversion simple and predictable.

---

## 🔧 Extending the Project

The project can be extended with:
- link support
- inline code support
- tables
- Typst templates (title page, headers/footers)
- or replacing the parser with `pandoc → typst`

---

## 📄 License

Free to use for educational and personal projects.
