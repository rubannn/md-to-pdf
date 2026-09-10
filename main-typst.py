import re
import subprocess
from collections import Counter
from pathlib import Path
import shutil
import sys
import os

STOP_WORDS = {
    # english
    "the",
    "and",
    "that",
    "this",
    "with",
    "from",
    "for",
    "are",
    "was",
    "were",
    "have",
    "has",
    "had",
    "not",
    "but",
    "its",
    "their",
    "them",
    "which",
    "while",
    "into",
    "than",
    "then",
    "also",
    "such",
    "each",
    "these",
    "those",
    "other",
    "more",
    "most",
    "some",
    "only",
    "over",
    "when",
    "where",
    "what",
    "who",
    "how",
    "can",
    "could",
    "would",
    "should",
    "will",
    "may",
    "might",
    "about",
    "between",
    "across",
    "through",
    "within",
    "without",
    "under",
    "after",
    "before",
    "both",
    "does",
    "did",
    "being",
    "been",
    "there",
    "here",
    "any",
    "all",
    "one",
    # ukrainian / russian
    "для",
    "que",
    "або",
    "цей",
    "яка",
    "яке",
    "які",
    "його",
    "її",
    "їх",
    "цих",
    "цієї",
    "також",
    "лише",
    "тому",
    "щодо",
    "коли",
    "де",
    "як",
    "що",
    "не",
    "на",
    "за",
    "із",
    "від",
    "до",
    "про",
    "при",
    "чи",
    "статті",
    "стаття",
    "автор",
}


def extract_keywords(md_text: str, top_n: int = 10) -> list[str]:
    """
    Извлекает набор ключевых слов из текста на основе частоты встречаемости
    значимых слов (без markdown-разметки и стоп-слов).
    """
    clean = re.sub(r"[#>*`~\[\]\(\)\-_]", " ", md_text)
    words = re.findall(r"[a-zA-Zа-яА-ЯіїєґІЇЄҐ']+", clean.lower())
    significant = (w for w in words if len(w) > 3 and w not in STOP_WORDS)
    counts = Counter(significant)
    return [word for word, _ in counts.most_common(top_n)]


def find_typst() -> str:
    path = shutil.which("typst")
    if path:
        return path

    scoop_typst = Path.home() / "scoop" / "apps" / "typst" / "current" / "typst.exe"
    if scoop_typst.exists():
        return str(scoop_typst)

    print("❌ Typst not found.")
    print("Install Typst via Scoop or add typst.exe to PATH.")
    sys.exit(1)


def count_words(md_text: str) -> int:
    """
    Подсчёт количества слов в Markdown-тексте.
    """
    clean = re.sub(r"[#>*`~\[\]\(\)\-_]", " ", md_text)
    clean = re.sub(r"\s+", " ", clean).strip()
    return len(clean.split(" ")) if clean else 0


def clean_md_title(raw_title: str) -> str:
    """
    Очистка первой строки Markdown от форматирования.
    """
    text = re.sub(r"[#>*`~\[\]\(\)«»]", " ", raw_title)
    text = re.sub(r"\s+", " ", text).strip()
    text = text.replace("Рев’ю на статтю", "Рев’ю")
    return text


def safe_filename(title: str, max_len: int, ext: str) -> str:
    """
    Безопасное имя файла.
    """
    safe = re.sub(r'[<>:"/\\|?*]', "", title)
    return f"{safe[:max_len - len(ext)]}{ext}"


def md_inline_to_typst(text: str) -> str:
    result = []
    i = 0
    bold = False
    italic = False

    while i < len(text):
        # Markdown жирный курсив ***
        if text[i : i + 3] == "***":
            if bold and italic:
                result.append("_*")  # закрытие: сначала курсив, потом жирный
            else:
                result.append("*_")  # открытие: сначала жирный, потом курсив
            bold = not bold
            italic = not italic
            i += 3
            continue

        # Markdown жирный **
        if text[i : i + 2] == "**":
            result.append("*")  # Typst жирный
            bold = not bold
            i += 2
            continue

        # Markdown курсив *
        if text[i] == "*":
            result.append("_")  # Typst курсив
            italic = not italic
            i += 1
            continue

        result.append(text[i])
        i += 1

    return "".join(result)


def escape_typst_text(text: str) -> str:
    """
    Экранирует символы, которые в Typst имеют особое значение внутри content-блока [...].
    """
    text = text.replace("\\", "\\\\")
    text = text.replace("#", "\\#")
    text = text.replace("[", "\\[")
    text = text.replace("]", "\\]")
    return text


def is_table_separator(line: str) -> bool:
    """
    Проверяет, является ли строка разделителем заголовка таблицы Markdown, напр. |---|:---:|---|
    """
    stripped = line.strip()
    if "-" not in stripped:
        return False
    return bool(re.fullmatch(r"\|?[\s:\-|]+\|?", stripped))


def parse_table_row(line: str) -> list[str]:
    """
    Разбивает строку таблицы Markdown на список ячеек.
    """
    stripped = line.strip().removeprefix("|").removesuffix("|")
    return [cell.strip() for cell in stripped.split("|")]


def md_to_typst(md_text: str) -> str:
    """
    Простейшее преобразование Markdown → Typst.
    Поддерживает заголовки, списки, таблицы и абзацы.
    """
    lines = md_text.splitlines()
    out = []
    i = 0
    n = len(lines)

    while i < n:
        raw_line = lines[i]

        # Таблица Markdown: строка с "|", за которой следует строка-разделитель
        if (
            raw_line.strip().startswith("|")
            and i + 1 < n
            and is_table_separator(lines[i + 1])
        ):
            header_cells = parse_table_row(raw_line)
            col_count = len(header_cells)
            i += 2

            rows = []
            while i < n and lines[i].strip().startswith("|"):
                rows.append(parse_table_row(lines[i]))
                i += 1

            def cell_to_typst(cell: str) -> str:
                return f"[{escape_typst_text(md_inline_to_typst(cell))}]"

            out.append("#table(")
            out.append(f"  columns: {col_count},")
            out.append("  table.header(")
            out.append("    " + ", ".join(cell_to_typst(c) for c in header_cells) + ",")
            out.append("  ),")
            for row in rows:
                cells = list(row) + [""] * (col_count - len(row))
                out.append("  " + ", ".join(cell_to_typst(c) for c in cells[:col_count]) + ",")
            out.append(")")
            out.append("")
            continue

        # Блочная цитата Markdown: одна или несколько последовательных строк "> ..."
        if raw_line.strip().startswith(">"):
            quote_parts = []
            while i < n and lines[i].strip().startswith(">"):
                content = lines[i].strip()[1:].strip()
                if content:
                    quote_parts.append(md_inline_to_typst(content))
                i += 1

            quote_text = escape_typst_text(" ".join(quote_parts))
            out.append(f"#quote(block: true)[{quote_text}]")
            out.append("")
            continue

        line = md_inline_to_typst(raw_line)

        if line.startswith("# "):
            out.append(f"= {line[2:].strip()}")
        elif line.startswith("## "):
            out.append(f"== {line[3:].strip().capitalize()}")
        elif line.startswith("### "):
            out.append(f"=== {line[4:].strip()}")
        elif line.startswith("#### "):
            out.append(f"==== {line[5:].strip()}")
        elif line.startswith("- "):
            out.append(f"- {line[2:].strip()}")
        elif line.strip() == "":
            out.append("")
        else:
            out.append(line)

        i += 1

    return "\n".join(out)


def get_typst(md_to_typst, AUTHOR, md_text, clean_title, typ_path, keywords):
    """
    Оборачивает Markdown (через md_to_typst) в Typst-документ с метаданными
    (title, author, description, keywords) и сохраняет его в typ_path.
    """
    typst_body = md_to_typst(md_text)

    typst_doc = f"""
        #import "../style/style.typ": apply-style
        #show: apply-style
        #set document(
        title: "{clean_title}",
        author: "{AUTHOR}",
        description: "{clean_title}",
        keywords: ({", ".join(f'"{kw}"' for kw in keywords)}),
        )
        {typst_body}
        """.strip()

    typ_path.write_text(typst_doc, encoding="utf-8")



# -----------------------------
# Константы
# -----------------------------

MAX_LEN = int(os.getenv("MAX_LEN", 20))
PREFIX = os.getenv("PREFIX", "Noname. ")
AUTHOR = os.getenv("AUTHOR", "Unknown Author")

INPUT_MD = Path("./in/input.md")
OUT_DIR = Path("./out")
OUT_DIR_TYPST = Path("./out-typst")
OUT_DIR.mkdir(exist_ok=True)

TYPST = find_typst()


# -----------------------------
# Чтение markdown
# -----------------------------
md_text = INPUT_MD.read_text(encoding="utf-8")

first_line = md_text.splitlines()[0] if md_text else "document"
clean_title = clean_md_title(first_line)

base_name = PREFIX + clean_title
pdf_name = safe_filename(base_name, MAX_LEN, ".pdf")

typ_path = OUT_DIR_TYPST / "input.typ"
pdf_path = OUT_DIR / pdf_name

# -----------------------------
# Подсчёт слов и ключевых слов
# -----------------------------
word_count = count_words(md_text)
print("word count:", word_count)

keywords = ("typst", "pdf", "review", *extract_keywords(md_text))
print("keywords:", ", ".join(keywords))


# -----------------------------
# Markdown → Typst
# -----------------------------
get_typst(md_to_typst, AUTHOR, md_text, clean_title, typ_path, keywords)


# -----------------------------
# Typst → PDF
# -----------------------------
subprocess.run(
    [TYPST, "compile", "--root", ".", str(typ_path), str(pdf_path)], check=True
)
print("PDF created:", pdf_path)
