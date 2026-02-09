import re
import subprocess
from pathlib import Path
import shutil
import sys
import os


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


def md_to_typst(md_text: str) -> str:
    """
    Простейшее преобразование Markdown → Typst.
    Поддерживает заголовки, списки и абзацы.
    """
    lines = md_text.splitlines()
    out = []

    for line in lines:
        line = md_inline_to_typst(line)

        if line.startswith("# "):
            out.append(f"= {line[2:].strip()}")
        elif line.startswith("## "):
            out.append(f"== {line[3:].strip()}")
        elif line.startswith("### "):
            out.append(f"=== {line[4:].strip()}")
        elif line.startswith("- "):
            out.append(f"- {line[2:].strip()}")
        elif line.strip() == "":
            out.append("")
        else:
            out.append(line)

    return "\n".join(out)


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
# Подсчёт слов
# -----------------------------
word_count = count_words(md_text)
print("word count:", word_count)


# -----------------------------
# Markdown → Typst
# -----------------------------
typst_body = md_to_typst(md_text)

typst_doc = f"""
#import "../style/style.typ": apply-style
#show: apply-style

#set document(
  title: "{clean_title}",
  author: "{AUTHOR}",
  description: "{clean_title}",
  keywords: ("typst", "pdf", "review"),
)


{typst_body}
""".strip()

typ_path.write_text(typst_doc, encoding="utf-8")


# -----------------------------
# Typst → PDF
# -----------------------------
subprocess.run(
    [TYPST, "compile", "--root", ".", str(typ_path), str(pdf_path)], check=True
)
print("PDF created:", pdf_path)
