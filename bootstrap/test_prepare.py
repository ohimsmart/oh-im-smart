"""bootstrap/prepare-image.sh against the real upstream bootstrap image (spec §7.4).

The image (about 1 GB) is downloaded once into ~/.cache/ohimsmart and checked against the sha256
the README gives. prepare-image.sh runs natively here (UM has e2fsprogs 1.47, sfdisk and openssl).
"""
import hashlib
import json
import os
import pty
import re
import select
import shutil
import subprocess
import time
from pathlib import Path

import pytest

HERE = Path(__file__).parent
INNER = HERE / 'prepare-image.sh'
NAME = 'bootstrap-pmos-ssh-generic-qcom-msm8953.img'
URL = f'https://github.com/rickx/ubuntu-thinksmart/releases/download/bootstrap-2026-05-22/{NAME}'
SHA256 = '7d79db19b0911647bf6ab0a9a2924ef5cf83b4674798a54acdcbd41cdf07921b'
CACHE = Path(os.environ.get('OHIMSMART_CACHE', Path.home() / '.cache' / 'ohimsmart'))

SSID = 'a b\\c;d 家'          # a space, a backslash, a semicolon and a non-ASCII character
PSK = ' p\\a;s s '            # leading and trailing spaces too
PASSWORD = 'Sekret-pw 1'
ANSWERS = (SSID, PSK, PASSWORD, PASSWORD)
KEYFILE = '/etc/NetworkManager/system-connections/bootstrap-wifi.nmconnection'


def sha256(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for block in iter(lambda: f.read(1 << 20), b''):
            h.update(block)
    return h.hexdigest()


@pytest.fixture(scope='session')
def upstream():
    path = CACHE / NAME
    if not path.exists():
        CACHE.mkdir(parents=True, exist_ok=True)
        part = path.with_suffix('.part')
        subprocess.run(['curl', '-fsSL', '-o', part, URL], check=True)
        part.rename(path)
    assert sha256(path) == SHA256, f'{path} is not the upstream bootstrap image: delete it to download again'
    return path


def copy(upstream, tmp_path, name='bootstrap.img'):
    out = tmp_path / name
    shutil.copyfile(upstream, out)
    return out


def root(img):
    """debugfs's name for the image's ext4 root partition."""
    table = json.loads(subprocess.run(['sfdisk', '-J', img], capture_output=True, text=True, check=True).stdout)
    part = table['partitiontable']['partitions'][1]
    assert part['type'] == '83'
    return f"{img}?offset={part['start'] * table['partitiontable'].get('sectorsize', 512)}"


def dfs(img, cmd, write=False):
    args = ['debugfs'] + (['-w'] if write else []) + ['-R', cmd, root(img)]
    return subprocess.run(args, capture_output=True, text=True, check=True).stdout


def stat(img, path):
    out = dfs(img, f'stat "{path}"')
    m = re.search(r'Type: (\w+)\s+Mode:\s+(\d+).*?User:\s+(\d+)\s+Group:\s+(\d+)', out, re.S)
    return m.groups() if m else None


def run(cmd, answers, trace=None, env=None):
    # -v: also record each program's environment, not only its command line.
    if trace:
        cmd = ['strace', '-f', '-v', '-qq', '-e', 'trace=execve', '-s', '65536', '-o', str(trace)] + cmd
    return subprocess.run([str(c) for c in cmd], input=''.join(a + '\n' for a in answers),
                          capture_output=True, text=True, env=env)


def prepare(img, *answers, trace=None, env=None):
    return run(['bash', INNER, img], answers, trace, env)


def leaks(secret, text):
    """Whether secret is in text as typed, as strace writes it (\\ for \\), or as the keyfile holds it."""
    spellings = {secret, secret.replace('\\', '\\\\'), secret.replace('\\', '\\\\\\\\')}
    return any(s in text for s in spellings)


@pytest.fixture(autouse=True)
def _drop_images(tmp_path):
    """Each test copies the 1 GB image; delete the copies, or every run leaves tens of GB behind."""
    yield
    for img in tmp_path.glob('*.img'):
        img.unlink()


def shadow(img):
    return {line.split(':')[0]: line.split(':')[1] for line in dfs(img, 'cat /etc/shadow').splitlines()}


def nm(*args, stdin=None):
    """What NetworkManager itself makes of a connection, as its keyfile lines."""
    out = subprocess.run(['nmcli', '--offline', 'connection', *args], input=stdin,
                         capture_output=True, text=True, check=True).stdout
    return {k: v for k, v in (line.split('=', 1) for line in out.splitlines() if '=' in line)
            if k in ('interface-name', 'ssid', 'key-mgmt', 'psk')}


def plant(img, path, text, tmp_path):
    """Replace one file in the image, to build the images the script must refuse or clean."""
    src = tmp_path / 'planted'
    src.write_text(text)
    dfs(img, f'rm {path}', write=True)
    dfs(img, f'write {src} {path}', write=True)


@pytest.fixture(scope='module')
def prepared(upstream, tmp_path_factory):
    tmp = tmp_path_factory.mktemp('prepared')
    img = copy(upstream, tmp)
    try:
        # Host keys planted, so their removal is tested: the upstream image ships none.
        for name in ('ssh_host_ed25519_key', 'ssh_host_ed25519_key.pub'):
            plant(img, f'/etc/ssh/{name}', 'not a real key\n', tmp)
        assert 'ssh_host_ed25519_key' in dfs(img, 'ls /etc/ssh')
        r = prepare(img, *ANSWERS, trace=tmp / 'trace')
        assert r.returncode == 0, r.stderr
        yield img, r, (tmp / 'trace').read_text()
    finally:
        img.unlink()


def test_the_machine_id_is_32_hex_digits(prepared):
    img, _, _ = prepared
    assert re.fullmatch(r'[0-9a-f]{32}\n', dfs(img, 'cat /etc/machine-id'))
    assert stat(img, '/etc/machine-id') == ('regular', '0644', '0', '0')


def test_the_wifi_keyfile_is_roots_and_private(prepared):
    img, _, _ = prepared
    assert stat(img, KEYFILE) == ('regular', '0600', '0', '0')
    assert dfs(img, 'ls /etc/NetworkManager/system-connections').count('.nmconnection') == 1


def test_networkmanager_reads_the_wifi_as_entered(prepared):
    img, _, _ = prepared
    text = dfs(img, f'cat {KEYFILE}')
    assert 'autoconnect=true' in text.splitlines()
    ours = nm('modify', 'connection.id', 'x', stdin=text)
    own = nm('add', 'type', 'wifi', 'con-name', 'x', 'ifname', 'wlan0', 'ssid', SSID,
             'wifi-sec.key-mgmt', 'wpa-psk', 'wifi-sec.psk', PSK)
    assert ours == own
    assert ours['interface-name'] == 'wlan0'


def test_root_is_locked_and_pmos_takes_the_new_password(prepared):
    img, _, _ = prepared
    assert stat(img, '/etc/shadow') == ('regular', '0600', '0', '0')
    users = shadow(img)
    assert users['root'] == '!'
    salt = users['pmos'].split('$')[2]

    def hashed(pw):
        return subprocess.run(['openssl', 'passwd', '-6', '-salt', salt, '-stdin'], input=pw + '\n',
                              capture_output=True, text=True, check=True).stdout.strip()
    assert hashed(PASSWORD) == users['pmos']
    assert hashed('thinksmart') != users['pmos']


def test_the_ssh_host_keys_are_gone(prepared):
    img, _, _ = prepared
    assert 'ssh_host_' not in dfs(img, 'ls /etc/ssh')


def test_nothing_starts_the_automatic_partition_rewrite(prepared):
    img, _, _ = prepared
    for level in ('sysinit', 'boot', 'default', 'shutdown', 'nonetwork'):
        assert 'bootstrap-apply-ubuntu-gpt' not in dfs(img, f'ls /etc/runlevels/{level}')


def test_the_filesystem_checks_clean(prepared):
    img, _, _ = prepared
    r = subprocess.run(['e2fsck', '-fn', root(img)], capture_output=True, text=True)
    assert r.returncode == 0, r.stdout + r.stderr


def test_no_secret_reaches_a_command_line_an_environment_or_the_output(prepared):
    _, r, trace = prepared
    assert re.search(r'execve\("[^"]*/debugfs", \[[^]]*"-w"', trace)     # the trace saw the programs
    assert 'vars */' not in trace      # -v: environments are written out, not summarised as /* N vars */
    for secret in (PASSWORD, PSK.strip()):
        assert not leaks(secret, trace)
        assert not leaks(secret, r.stdout + r.stderr)


@pytest.mark.parametrize('inherited', [
    {'SSID': '', 'PSK': '', 'PASS': '', 'PASS2': ''},     # bash's read keeps an inherited export
    {'SHELLOPTS': 'allexport'},                          # bash would export every variable it sets
])
def test_answers_stay_private_whatever_the_caller_exported(upstream, tmp_path, inherited):
    img = copy(upstream, tmp_path)
    env = dict(os.environ, **inherited)
    r = prepare(img, *ANSWERS, trace=tmp_path / 'trace', env=env)
    assert r.returncode == 0, r.stderr
    trace = (tmp_path / 'trace').read_text()
    assert not leaks(PASSWORD, trace) and not leaks(PSK.strip(), trace)


def test_hidden_answers_are_not_echoed_on_a_terminal(upstream, tmp_path):
    img = copy(upstream, tmp_path)
    master, slave = pty.openpty()
    p = subprocess.Popen(['bash', INNER, img], stdin=slave, stdout=slave, stderr=slave)
    os.close(slave)
    seen = b''

    def read_more(timeout=1):
        nonlocal seen
        if select.select([master], [], [], timeout)[0]:
            try:
                chunk = os.read(master, 4096)
            except OSError:          # the script ended: Linux reports EIO on the master
                return False
            seen += chunk
            return bool(chunk)
        return True

    try:
        # Type each answer only after its question: a terminal echoes type-ahead before read -s runs.
        for prompt, answer in ((b'WiFi name', 'home'), (b'WiFi password', 'wifi-Secret-9'),
                               (b'password for pmos', PASSWORD), (b'same password again', PASSWORD)):
            deadline = time.time() + 30
            while prompt not in seen:
                assert time.time() < deadline and read_more(), seen
            os.write(master, answer.encode() + b'\n')
        deadline = time.time() + 60
        while read_more(1) and p.poll() is None:
            assert time.time() < deadline, seen
        assert p.wait(timeout=60) == 0, seen
    finally:
        if p.poll() is None:
            p.kill()
            p.wait()
        os.close(master)
    assert b'home' in seen                        # the WiFi name is echoed: it is not a secret
    assert b'wifi-Secret-9' not in seen
    assert PASSWORD.encode() not in seen


def test_an_open_network_has_no_password(upstream, tmp_path):
    img = copy(upstream, tmp_path)
    name = 'Cafe-' + 'x' * 27                 # 32 bytes, the longest name WiFi allows
    r = prepare(img, name, '', PASSWORD, PASSWORD)
    assert r.returncode == 0, r.stderr
    text = dfs(img, f'cat {KEYFILE}')
    assert '[wifi-security]' not in text
    assert nm('modify', 'connection.id', 'x', stdin=text) == nm(
        'add', 'type', 'wifi', 'con-name', 'x', 'ifname', 'wlan0', 'ssid', name)


def test_no_wifi_name_means_usb_only(upstream, tmp_path):
    img = copy(upstream, tmp_path)
    r = prepare(img, '', PASSWORD, PASSWORD)
    assert r.returncode == 0, r.stderr
    assert '.nmconnection' not in dfs(img, 'ls /etc/NetworkManager/system-connections')
    assert re.fullmatch(r'[0-9a-f]{32}\n', dfs(img, 'cat /etc/machine-id'))
    assert shadow(img)['root'] == '!'


def test_an_image_prepared_before_is_refused(upstream, tmp_path):
    # A second run would leave the first run's WiFi password in the filesystem's free space.
    img = copy(upstream, tmp_path)
    assert prepare(img, 'home', 'wifi-Secret-9', PASSWORD, PASSWORD).returncode == 0
    before = sha256(img)
    r = prepare(img, '', PASSWORD, PASSWORD)
    assert r.returncode != 0
    assert 'prepared before' in r.stderr
    assert sha256(img) == before


@pytest.mark.parametrize('answers, why', [
    (('', '', ''), 'needs 8 or more characters'),
    (('', 'short', 'short'), 'needs 8 or more characters'),
    (('', '家' * 7, '家' * 7), 'needs 8 or more characters'),     # 21 bytes, but 7 characters
    (('', 'x' * 129, 'x' * 129), 'at most 128 bytes'),     # openssl would cut it at 256 bytes
    (('', 'thinksmart', 'thinksmart'), 'published default'),
    (('', PASSWORD, PASSWORD + 'x'), 'differ'),
    (('home', 'seven77', PASSWORD, PASSWORD), 'WPA password'),
    (('home', 'pässword-1', PASSWORD, PASSWORD), 'WPA password'),
    (('x' * 33, '', PASSWORD, PASSWORD), '32 bytes'),
    (('家' * 11, '', PASSWORD, PASSWORD), '32 bytes'),
    ((), 'no answer'),
])
def test_bad_answers_are_refused_before_anything_is_written(upstream, tmp_path, answers, why):
    img = copy(upstream, tmp_path)
    r = prepare(img, *answers)
    assert r.returncode != 0
    assert why in r.stderr
    assert sha256(img) == SHA256, 'a refused run changed the image'


def test_a_temporary_directory_debugfs_cannot_quote_is_refused_before_writing(upstream, tmp_path):
    img = copy(upstream, tmp_path)
    odd = tmp_path / 'my "tmp'
    odd.mkdir()
    r = prepare(img, '', PASSWORD, PASSWORD, env=dict(os.environ, TMPDIR=str(odd)))
    assert r.returncode != 0
    assert 'set TMPDIR to a plain path' in r.stderr
    assert sha256(img) == SHA256


def tiny(tmp_path, fs, label):
    img = tmp_path / 'tiny.img'
    subprocess.run(['truncate', '-s', '8M', img], check=True)
    subprocess.run(['sfdisk', '-q', img], input='2048,,83\n', text=True, check=True)
    subprocess.run(['mke2fs', '-q', '-t', fs, '-L', label, '-E', 'offset=1048576', img, '7168'],
                   capture_output=True, check=True)
    return img


@pytest.mark.parametrize('fs, label, why', [
    ('ext2', 'pmOS_root', 'not ext4'),
    ('ext4', 'other', 'no ext4 pmOS_root partition'),
])
def test_images_without_an_ext4_pmos_root_are_refused(tmp_path, fs, label, why):
    r = prepare(tiny(tmp_path, fs, label), PASSWORD, PASSWORD)
    assert r.returncode != 0
    assert why in r.stderr


def test_a_file_without_a_partition_table_is_refused(tmp_path):
    img = tmp_path / 'blank.img'
    img.write_bytes(bytes(1 << 20))
    r = prepare(img, PASSWORD, PASSWORD)
    assert r.returncode != 0
    assert 'no partition table' in r.stderr


@pytest.mark.parametrize('setting', ['sshd_disable_keygen="yes"', 'SSHD_DISABLE_KEYGEN="yes"'])
def test_an_image_whose_sshd_makes_no_host_keys_is_refused(upstream, tmp_path, setting):
    # Why prepare-image.sh deletes the host keys but adds no boot script to make them (spec §7.3 item 4).
    img = copy(upstream, tmp_path)
    plant(img, '/etc/conf.d/sshd', setting + '\n', tmp_path)
    r = prepare(img, '', PASSWORD, PASSWORD)
    assert r.returncode != 0
    assert 'would not make its own host keys' in r.stderr


def test_a_missing_runlevel_directory_is_not_taken_for_an_empty_one(upstream, tmp_path):
    # debugfs prints nothing and exits 0 for a directory that is not there.
    img = copy(upstream, tmp_path)
    names = [line.split('/')[5] for line in dfs(img, 'ls -p /etc/runlevels/nonetwork').splitlines() if line]
    assert names == ['.', '..']               # empty, so rmdir works
    dfs(img, 'rmdir /etc/runlevels/nonetwork', write=True)
    r = prepare(img, '', PASSWORD, PASSWORD)
    assert r.returncode != 0
    assert 'cannot read /etc/runlevels/nonetwork' in r.stderr


def test_an_image_that_rewrites_the_partitions_on_boot_is_refused(upstream, tmp_path):
    img = copy(upstream, tmp_path)
    dfs(img, 'symlink /etc/runlevels/default/bootstrap-apply-ubuntu-gpt /etc/init.d/bootstrap-apply-ubuntu-gpt',
        write=True)
    r = prepare(img, '', PASSWORD, PASSWORD)
    assert r.returncode != 0
    assert 'automatic partition rewrite' in r.stderr
