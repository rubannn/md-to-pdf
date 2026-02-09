import markdown
import pdfkit
import re


def count_words(md_text: str) -> int:
    """
    Подсчёт количества слов в Markdown-тексте.
    Убирает Markdown-разметку и считает только реальные слова.
    """
    # убрать markdown-символы
    clean = re.sub(r"[#>*`~\[\]\(\)\-_]", " ", md_text)

    # убрать множественные пробелы
    clean = re.sub(r"\s+", " ", clean)

    # удалить пробелы по краям
    clean = clean.strip()

    if not clean:
        return 0

    return len(clean.split(" "))


def clean_md_title(raw_title: str) -> str:
    """
    Очистка первой строки Markdown от форматирования и спецсимволов.
    Например: "# Заголовок **тест**" → "Заголовок тест"
    """
    # Удаляем MD-разметку
    text = re.sub(r"[#>*`~\[\]\(\)«»]", " ", raw_title)

    # Убираем двойные пробелы
    text = re.sub(r"\s+", " ", text).strip()
    text = text.replace("Рев’ю на статтю", "Рев’ю")

    return text


def safe_filename(title: str, max_len: int) -> str:
    """
    Создание безопасного имени файла из заголовка.
    Удаляет запрещённые символы и обрезает до максимальной длины.
    """
    ext = ".pdf"

    # удаляем запрещённые символы
    safe_title = re.sub(r'[<>:"/\\|?*]', "", title)

    max_title_len = max_len - len(ext)
    safe_title = safe_title[:max_title_len]

    return f"{safe_title}{ext}"


MAX_LEN = 100
prefix = "Рубан. "

# читаем markdown
with open("./in/input.md", "r", encoding="utf-8") as f:
    md_text = f.read()

first_line = md_text.splitlines()[0] if md_text else "document"
clean_title = clean_md_title(first_line)
output_name = f"{prefix}{safe_filename(clean_title, MAX_LEN)}"


word_count = count_words(md_text)
print("\nword count:", word_count)

html = markdown.markdown(md_text)
html = f"""
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
</head>
<body>
{html}
</body>
</html>
"""
with open("./out/output.html", "w", encoding="utf-8") as f:
    f.write(html)

# путь к wkhtmltopdf
path_wkhtmltopdf = r"C:\Program Files\wkhtmltopdf\bin\wkhtmltopdf.exe"
config = pdfkit.configuration(wkhtmltopdf=path_wkhtmltopdf)
pdfkit.from_string(
    html, f"./out/{output_name}", configuration=config, css="./style/style.css"
)


print("PDF created!")
