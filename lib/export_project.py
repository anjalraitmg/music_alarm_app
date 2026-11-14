import os
import re

# Files or directories you want to skip (to avoid cluttering your text)
IGNORE_LIST = {
    'venv', '.git', '__pycache__', 'db.sqlite3', '.env',
    '.gitignore', 'export_project.py', '.idea', '.vscode',
    # Common secret/config files that should not end up in an LLM prompt:
    'secrets.json', 'credentials.json', 'config.json',
    'package-lock.json', 'yarn.lock', 'poetry.lock',
    'node_modules', 'dist', 'build', '.next', 'target',
}

# File extensions you want to capture
VALID_EXTENSIONS = ('.py', '.html', '.css', '.js', '.json', '.sh', '.md','.dart')

# Skip individual files larger than this (bytes) to avoid huge output
MAX_FILE_SIZE = 500_000  # ~500 KB

# Map extensions to fence language tags for the output
LANG_MAP = {
    '.py': 'python',
    '.html': 'html',
    '.css': 'css',
    '.js': 'javascript',
    '.json': 'json',
    '.sh': 'bash',
    '.md': 'markdown',
}

# ---------------------------------------------------------------------------
# Secret redaction
# ---------------------------------------------------------------------------

# Trigger redaction on any file whose name looks like a settings/config module
SECRET_FILENAME_HINTS = ('settings', 'config', 'secret')

# SECRET_KEY = "..." or SECRET_KEY = '...' (Strict single-line match)
SECRET_KEY_ASSIGN_RE = re.compile(
    r"(SECRET_KEY\s*=\s*)(['\"])(.*?)\2"
)

# SECRET_KEY = os.environ.get("VAR", "fallback")  /  os.getenv("VAR", "fallback")
SECRET_KEY_ENV_FALLBACK_RE = re.compile(
    r"(SECRET_KEY\s*=\s*os\.(?:environ\.get|getenv)\("
    r"[^,)]*,\s*)(['\"])(.*?)\2",
    re.DOTALL,
)

# Catches API_KEY="secret", api_key: "secret", "apiKey": "secret", 'auth_token': 'secret'
GENERIC_SECRET_RE = re.compile(
    r"(?im)^([ \t]*['\"]?(?:API_KEY|SECRET|TOKEN|PASSWORD|PASSWD|AUTH_KEY|apiKey|authToken|passwd)['\"]?"
    r"\s*[:=]\s*)(['\"])(.*?)\2",
)


def _redact_secrets(text: str, filename: str) -> str:
    """Best-effort redaction of obvious secrets in settings/config files."""
    lowered = filename.lower()
    if not any(hint in lowered for hint in SECRET_FILENAME_HINTS):
        return text

    text = SECRET_KEY_ASSIGN_RE.sub(
        r"\1\2*** STRIPPED_FOR_SAFETY ***\2", text
    )
    text = SECRET_KEY_ENV_FALLBACK_RE.sub(
        r"\1\2*** STRIPPED_FOR_SAFETY ***\2", text
    )
    text = GENERIC_SECRET_RE.sub(
        r"\1\2*** STRIPPED_FOR_SAFETY ***\2", text
    )
    return text


# ---------------------------------------------------------------------------
# Export
# ---------------------------------------------------------------------------

def export_project_to_text(output_filename="project_compiled_code.txt"):
    project_root = os.getcwd()
    output_path = os.path.join(project_root, output_filename)

    # Avoid accidentally including the output file if it lives in the project
    skip_abs = {os.path.abspath(output_path)}
    
    # Using 4 backticks universally ensures nested blocks inside .md files won't break formatting
    FENCE = "````"

    total_files = 0
    skipped_large = 0

    with open(output_path, "w", encoding="utf-8") as outfile:
        outfile.write(
            f"=== FULL CODEBASE EXPORT: {os.path.basename(project_root)} ===\n\n"
        )

        for root, dirs, files in os.walk(project_root):
            # Modify dirs in-place to skip ignored directories
            dirs[:] = [
                d for d in dirs
                if d not in IGNORE_LIST and not d.startswith('.')
            ]

            for file in files:
                if not file.endswith(VALID_EXTENSIONS):
                    continue
                if file in IGNORE_LIST:
                    continue

                file_path = os.path.join(root, file)
                if os.path.abspath(file_path) in skip_abs:
                    continue

                # Size guard
                try:
                    if os.path.getsize(file_path) > MAX_FILE_SIZE:
                        skipped_large += 1
                        continue
                except OSError:
                    continue

                relative_path = os.path.relpath(file_path, project_root)
                ext = os.path.splitext(file)[1].lower()
                lang = LANG_MAP.get(ext, 'text')

                # Write relative path identifier
                outfile.write(f"{relative_path}\n")
                
                # Open 4-backtick code block
                outfile.write(f"{FENCE}{lang}\n")

                try:
                    with open(
                        file_path, "r", encoding="utf-8", errors="replace"
                    ) as infile:
                        code_contents = infile.read()

                    # Redact obvious secrets in settings/config files
                    code_contents = _redact_secrets(code_contents, file)

                    outfile.write(code_contents)
                    total_files += 1
                except Exception as e:
                    outfile.write(f"# Error reading file: {str(e)}")

                # Close 4-backtick code block + add separator
                outfile.write(f"\n{FENCE}\n")
                outfile.write("-" * 80 + "\n\n")

    print(f"✅ Success! {total_files} file(s) exported to: {output_filename}")
    if skipped_large:
        print(
            f"⚠️  Skipped {skipped_large} file(s) larger than "
            f"{MAX_FILE_SIZE:,} bytes."
        )


if __name__ == "__main__":
    export_project_to_text()
