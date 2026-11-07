"""Download and install the latest stable TMX release on Linux or macOS."""
import fcntl
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import platform
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
from urllib.request import Request, urlopen


REPO = 'devoralabsapp/tmux-style'
LATEST = f'https://api.github.com/repos/{REPO}/releases/latest'
VERSION = re.compile(r'[0-9]{1,6}(?:\.[0-9]{1,6}){2}')
THEME = re.compile(r"^set -g @tmux_style_theme '([a-z]+)'$", re.M)


def version_key(value):
    if not VERSION.fullmatch(value):
        raise ValueError(f'Invalid TMX release version: {value}')
    return tuple(map(int, value.split('.')))


def download(url):
    return urlopen(Request(url, headers={'User-Agent': 'TMX-Updater'}), timeout=30)


def unpack(archive, target, prefix):
    with tarfile.open(archive, 'r:gz') as package:
        for member in package:
            path = PurePosixPath(member.name)
            if not member.isfile() or path.parts[:1] != (prefix,) or '..' in path.parts:
                raise ValueError('Unexpected path or file type in the release archive.')
            output = target.joinpath(*path.parts)
            output.parent.mkdir(parents=True, exist_ok=True)
            with package.extractfile(member) as source, output.open('xb') as destination:
                shutil.copyfileobj(source, destination)


def update(root, system):
    platform_name = {'Linux': 'linux', 'Darwin': 'macos'}[system]
    lock_path = root.with_name(root.name + '.update.lock')
    with os.fdopen(os.open(lock_path, os.O_WRONLY | os.O_CREAT | os.O_NOFOLLOW, 0o600), 'w') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise ValueError('Another TMX update is running.') from error
        current = (root / 'VERSION').read_text().strip()
        with download(LATEST) as response:
            release = json.load(response)
        tag = release['tag_name']
        if not tag.startswith('v') or release.get('draft') or release.get('prerelease'):
            raise ValueError('GitHub did not return a stable TMX release.')
        latest = tag[1:]
        if version_key(latest) <= version_key(current):
            print(f'TMX {current} is up to date.')
            return

        prefix = f'tmx-{platform_name}-{latest}'
        filename = prefix + '.tar.gz'
        url = f'https://github.com/{REPO}/releases/download/{tag}/{filename}'
        print(f'Updating TMX {current} to {latest}...', flush=True)
        with tempfile.TemporaryDirectory(prefix='tmx-update-') as directory:
            stage = Path(directory)
            archive = stage / filename
            with download(url + '.sha256') as response:
                checksum = response.read(4096).decode('ascii').split()
            if (len(checksum) != 2 or checksum[1] != filename
                    or not re.fullmatch(r'[0-9a-fA-F]{64}', checksum[0])):
                raise ValueError('Invalid TMX release checksum file.')
            digest = hashlib.sha256()
            with download(url) as response, archive.open('wb') as output:
                for chunk in iter(lambda: response.read(65536), b''):
                    digest.update(chunk)
                    output.write(chunk)
            if digest.hexdigest() != checksum[0].lower():
                raise ValueError('TMX download checksum mismatch. Installation files were not changed.')
            unpack(archive, stage, prefix)
            if (stage / prefix / 'VERSION').read_text().strip() != latest:
                raise ValueError('The downloaded package has a different version.')
            theme = THEME.search((root / 'theme.conf').read_text())
            if not theme or (root / 'VERSION').read_text().strip() != current:
                raise ValueError('The current installation changed or its default theme could not be read.')
            # Reuse the installer so upgrades have the same backups and rollback.
            subprocess.run(['bash', str(stage / prefix / 'unix/install.sh'), '--theme', theme[1]],
                           env=dict(os.environ, XDG_DATA_HOME=str(root.parent)), check=True)


if __name__ == '__main__':
    try:
        update(Path(sys.argv[1]), platform.system())
    except (OSError, ValueError, KeyError, tarfile.TarError, subprocess.CalledProcessError) as error:
        sys.exit(f'TMX update failed: {error}')
