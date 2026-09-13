# Git

This kit does not create remotes or `git push`. You own publication.

Do not commit:

- `jobs/`, `work/`, `models/`
- `.venv/`, `.venv-mlx/`
- `cookies.txt`
- personal or regional `lexicons/*.txt` (keep `lexicons/example.txt` only)
- `.env` and other paths listed in `.gitignore`

After the first public push, do not force-push; treat history as shared.

First publish (operator only):

```bash
git remote add origin git@github.com:PixelGhostIO/ghost-media-ingest-stack.git
git push -u origin main
```

Use the HTTPS remote if you prefer. Do not `--force`.
