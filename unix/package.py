"""Build architecture-independent Linux and macOS release archives."""
import gzip
import hashlib
from pathlib import Path
import tarfile

ROOT = Path(__file__).resolve().parents[1]
version = (ROOT / 'VERSION').read_text().strip()
out = ROOT / 'dist'
out.mkdir(exist_ok=True)
for platform in ['linux', 'macos']:
    prefix = f'tmx-{platform}-{version}'
    archive = out / f'{prefix}.tar.gz'
    files = [ROOT / p for p in ['VERSION', 'NOTICE.md', 'unix/README.md', 'windows-terminal/LICENSE']]
    files += [p for p in (ROOT / 'unix').rglob('*') if p.is_file() and p.suffix in ['.sh', '.conf']]
    files += [p for p in (ROOT / 'unix/shell').rglob('*') if p.is_file()]
    files += [p for p in (ROOT / platform).iterdir() if p.is_file()]
    with archive.open('wb') as raw, gzip.GzipFile(filename='', fileobj=raw, mode='wb', mtime=0) as zipped:
        with tarfile.open(fileobj=zipped, mode='w') as tar:
            for path in sorted(set(files)):
                relative = path.relative_to(ROOT)
                info = tar.gettarinfo(str(path), arcname=str(Path(prefix) / relative).replace('\\', '/'))
                info.uid = info.gid = 0
                info.uname = info.gname = ''
                info.mtime = 0
                info.mode = 0o755 if path.suffix in ['.sh', '.command'] else 0o644
                with path.open('rb') as source:
                    tar.addfile(info, source)
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    archive.with_suffix(archive.suffix + '.sha256').write_text(f'{digest}  {archive.name}\n')
    print(archive.name, digest)
