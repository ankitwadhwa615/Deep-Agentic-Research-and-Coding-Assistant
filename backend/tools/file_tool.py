from pathlib import Path

from langchain_core.tools import tool

UPLOADS_DIRECTORY = Path(__file__).resolve().parent.parent / "uploads"
UPLOADS_DIRECTORY.mkdir(exist_ok=True)

@tool(description="Read the contents of an uploaded text, code, CSV, JSON, Markdown, or PDF file using its file_id.")
def read_uploaded_file(file_id: str, start: int = 0, max_characters: int = 12000) -> str:
    file_path = UPLOADS_DIRECTORY / Path(file_id).name

    if not file_path.exists():
        return f"Uploaded file not found: {file_id}"

    if start < 0 or max_characters < 1:
        return "start must be zero or greater and max_characters must be greater than zero."

    if file_path.suffix.lower() == ".pdf":
        try:
            from pypdf import PdfReader

            content = "\n".join(page.extract_text() or "" for page in PdfReader(file_path).pages)
        except Exception as error:
            return f"Unable to read PDF: {error}"
    else:
        try:
            content = file_path.read_text(encoding="utf-8", errors="replace")
        except Exception as error:
            return f"Unable to read file: {error}"

    end = start + min(max_characters, 12000)
    return content[start:end]
