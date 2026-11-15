"""bootstrap/prepare.sh and prepare-image.sh against the real upstream bootstrap image (spec §7.4).

The image (about 1 GB) is downloaded once into ~/.cache/ohimsmart and checked against the sha256
the README gives. prepare-image.sh runs natively here (UM has e2fsprogs 1.47, sfdisk and openssl);
prepare.sh runs it in Docker, which this user must be able to use: those tests fail without it.
OHIMSMART_PREPARED_IMAGE=<image> also checks an image prepare.sh made elsewhere (macOS, §7.4)
from a copy with planted host keys and the answers in ANSWERS.
"""
import hashlib
import json
import os
import pty
import re
import select
import shutil
import signal
import subprocess
import time
from pathlib import Path

import pytest

HERE = Path(__file__).parent
INNER = HERE / 'prepare-image.sh'
WRAPPER = HERE / 'prepare.sh'
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
    for img in tmp_path.rglob('*.img'):
        if img.is_file():
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
def docker():
    """prepare.sh needs Docker usable by this user. Its tests fail, not skip, without it (§7.4)."""
    r = subprocess.run(['docker', 'info'], capture_output=True, text=True)
    assert r.returncode == 0, 'Docker is not usable by this user: ' + r.stderr.strip()[-300:]


def wrap(src, out, answers, trace=None):
    return run(['bash', WRAPPER, src, out], answers, trace)


def containers():
    """prepare.sh's containers, running or not: every run must remove its own."""
    out = subprocess.run(['docker', 'ps', '-a', '--filter', 'name=ohimsmart-prepare-', '--format', '{{.Names}}'],
                         capture_output=True, text=True, check=True).stdout
    return out.split()


def planted(upstream, tmp):
    """A copy holding SSH host keys, so their removal is tested: the upstream image ships none."""
    img = copy(upstream, tmp, 'source.img')
    for name in ('ssh_host_ed25519_key', 'ssh_host_ed25519_key.pub'):
        plant(img, f'/etc/ssh/{name}', 'not a real key\n', tmp)
    assert 'ssh_host_ed25519_key' in dfs(img, 'ls /etc/ssh')
    return img


@pytest.fixture(scope='module')
def wrapped(docker, upstream, tmp_path_factory):
    """prepare.sh end to end. The trace sees the host side, docker run included; the container
    runs prepare-image.sh, which the native run of `prepared` traces."""
    tmp = tmp_path_factory.mktemp('wrapped')
    out = tmp / 'out' / 'prepared.img'
    out.parent.mkdir()
    try:
        r = wrap(planted(upstream, tmp), out, ANSWERS, trace=tmp / 'trace')
        assert r.returncode == 0, r.stderr
        yield out, r, (tmp / 'trace').read_text()
    finally:
        (tmp / 'source.img').unlink(missing_ok=True)
        out.unlink(missing_ok=True)


GIVEN = os.environ.get('OHIMSMART_PREPARED_IMAGE')


@pytest.fixture(scope='module', params=['prepare-image.sh', 'prepare.sh'] + (['given'] if GIVEN else []))
def prepared(request, upstream, tmp_path_factory):
    if request.param == 'prepare.sh':
        yield request.getfixturevalue('wrapped')
        return
    if request.param == 'given':
        yield Path(GIVEN), None, None
        return
    tmp = tmp_path_factory.mktemp('prepared')
    try:
        img = planted(upstream, tmp)
        r = prepare(img, *ANSWERS, trace=tmp / 'trace')
        assert r.returncode == 0, r.stderr
        yield img, r, (tmp / 'trace').read_text()
    finally:
        (tmp / 'source.img').unlink(missing_ok=True)


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
    if trace is None:
        pytest.skip('an image prepared elsewhere comes without a trace: see the macOS steps in the plan')
    # The trace saw the programs: debugfs for prepare-image.sh, docker run for prepare.sh.
    assert re.search(r'execve\("[^"]*/(debugfs|docker)", \[[^]]*"(-w|run)"', trace)
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


def converse(cmd, steps):
    """Run cmd on a terminal (a pty); for each (prompt, keys) wait for the prompt, then type the keys.
    Returns (exit status, everything the terminal showed)."""
    master, slave = pty.openpty()
    p = subprocess.Popen([str(c) for c in cmd], stdin=slave, stdout=slave, stderr=slave)
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
        for prompt, keys in steps:
            deadline = time.time() + 60
            while prompt not in seen:
                assert time.time() < deadline and read_more(), seen
            os.write(master, keys)
        deadline = time.time() + 60
        while read_more(1) and p.poll() is None:
            assert time.time() < deadline, seen
        status = p.wait(timeout=60)
        # What the child printed just before it ended may still be waiting in the pty.
        while select.select([master], [], [], 0.5)[0]:
            try:
                chunk = os.read(master, 4096)
            except OSError:
                break
            if not chunk:
                break
            seen += chunk
        return status, seen
    finally:
        if p.poll() is None:
            p.kill()
            p.wait()
        os.close(master)


@pytest.mark.parametrize('script', ['prepare-image.sh', 'prepare.sh'])
def test_hidden_answers_are_not_echoed_on_a_terminal(upstream, tmp_path, script, request):
    if script == 'prepare-image.sh':
        cmd = ['bash', INNER, copy(upstream, tmp_path)]
    else:
        request.getfixturevalue('docker')
        cmd = ['bash', WRAPPER, upstream, tmp_path / 'prepared.img']      # docker run -t
    status, seen = converse(cmd, [(b'WiFi name', b'home\n'), (b'WiFi password', b'wifi-Secret-9\n'),
                                  (b'password for pmos', PASSWORD.encode() + b'\n'),
                                  (b'same password again', PASSWORD.encode() + b'\n')])
    assert status == 0, seen
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


# prepare.sh's own work: the image checks above already ran on its output through `prepared`.

def test_prepare_sh_leaves_one_private_file(wrapped):
    out, _, _ = wrapped
    assert (out.stat().st_mode & 0o777) == 0o600
    assert os.listdir(out.parent) == ['prepared.img']
    assert containers() == []


def test_prepare_sh_refuses_to_overwrite(upstream, tmp_path):
    out = tmp_path / 'prepared.img'
    out.write_text('mine')
    r = wrap(upstream, out, ())
    assert r.returncode != 0 and 'already exists' in r.stderr
    assert out.read_text() == 'mine'


@pytest.mark.parametrize('answers, why', [
    (('', '', ''), 'needs 8 or more characters'),
    (('', 'thinksmart', 'thinksmart'), 'published default'),
    ((), 'no answer'),
])
def test_prepare_sh_refuses_bad_answers_and_leaves_nothing(docker, upstream, tmp_path, answers, why):
    r = wrap(upstream, tmp_path / 'prepared.img', answers)
    assert r.returncode != 0
    assert why in r.stderr
    assert list(tmp_path.iterdir()) == [] and containers() == []
    assert sha256(upstream) == SHA256, 'prepare.sh changed its source image'


def test_prepare_sh_works_from_a_private_checkout_on_a_read_only_source(docker, upstream, tmp_path):
    # A checkout made under umask 077 leaves prepare-image.sh 0700; a downloaded image may be 0444.
    here = tmp_path / 'bootstrap'
    here.mkdir()
    for name in ('prepare.sh', 'prepare-image.sh', 'Dockerfile', '.dockerignore'):
        shutil.copyfile(HERE / name, here / name)
        (here / name).chmod(0o700 if name.endswith('.sh') else 0o600)
    src = copy(upstream, tmp_path, 'source.img')
    src.chmod(0o444)
    out = tmp_path / 'prepared.img'
    r = run(['bash', here / 'prepare.sh', src, out], ('', PASSWORD, PASSWORD))
    assert r.returncode == 0, r.stderr
    assert (out.stat().st_mode & 0o777) == 0o600
    assert re.fullmatch(r'[0-9a-f]{32}\n', dfs(out, 'cat /etc/machine-id'))
    assert sha256(src) == SHA256


def start(src, out):
    """prepare.sh in its own process group, and the name of its container once that is running."""
    p = subprocess.Popen(['bash', WRAPPER, src, out], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                         stderr=subprocess.PIPE, text=True, start_new_session=True)
    name = f'ohimsmart-prepare-{p.pid}'
    deadline = time.time() + 120
    try:
        while subprocess.run(['docker', 'inspect', '-f', '{{.State.Running}}', name],
                             capture_output=True, text=True, timeout=30).stdout.strip() != 'true':
            if p.poll() is not None:
                pytest.fail(f'prepare.sh ended early ({p.returncode}): {p.communicate()[1]}')
            if time.time() > deadline:
                pytest.fail('the container never started')
            time.sleep(0.5)
    except BaseException:
        stop(p, name)          # the caller's cleanup has not started yet
        raise
    return p, name


def stop(p, name):
    if p.poll() is None:
        os.killpg(p.pid, signal.SIGKILL)
        p.communicate()
    subprocess.run(['docker', 'rm', '-f', name], capture_output=True)


@pytest.mark.parametrize('how', ['SIGINT', 'SIGINT twice', 'kill', 'hangup'])
def test_an_interrupted_prepare_sh_leaves_nothing(docker, upstream, tmp_path, how):
    p, name = start(upstream, tmp_path / 'prepared.img')
    try:
        # SIGINT and SIGHUP (the terminal closed) go to the whole process group; kill is SIGTERM
        # to prepare.sh alone. A second Ctrl-C lands while the cleanup waits for the docker client.
        if how == 'kill':
            p.terminate()
        else:
            os.killpg(p.pid, signal.SIGHUP if how == 'hangup' else signal.SIGINT)
        if how == 'SIGINT twice':
            time.sleep(0.3)
            os.killpg(p.pid, signal.SIGINT)
        p.communicate(timeout=60)
        assert p.returncode != 0
        assert list(tmp_path.iterdir()) == [] and containers() == []
    finally:
        stop(p, name)


@pytest.mark.parametrize('keys, why', [
    pytest.param(b'\x10\x11', b'detached from the container', id='detach'),  # docker run ends with 0
    pytest.param(b'\x03', b'stopped', id='ctrl-c'),        # typed into the container's terminal
])
def test_keys_that_end_the_run_on_a_terminal_leave_nothing(docker, upstream, tmp_path, keys, why):
    status, seen = converse(['bash', WRAPPER, upstream, tmp_path / 'prepared.img'],
                            [(b'WiFi name', b'home\n'), (b'WiFi password', keys)])
    assert status != 0 and why in seen, seen
    assert list(tmp_path.iterdir()) == [] and containers() == []


def test_an_output_that_appears_meanwhile_is_left_alone(docker, upstream, tmp_path):
    out = tmp_path / 'prepared'                  # not *.img: the cleanup fixture would take it for a copy
    p, name = start(upstream, out)
    try:
        out.mkdir()                              # a directory would take the link inside it
        _, err = p.communicate(''.join(a + '\n' for a in ('', PASSWORD, PASSWORD)), timeout=120)
        assert p.returncode != 0 and 'appeared while this ran' in err, err
        assert list(out.iterdir()) == []
        assert list(tmp_path.iterdir()) == [out] and containers() == []
    finally:
        stop(p, name)


def test_prepare_sh_runs_its_container_without_network_privileges_or_secrets(wrapped):
    _, _, trace = wrapped
    runs = re.findall(r'execve\("[^"]*/docker", \["docker", "run", (.*?)\], \[', trace)
    assert len(runs) == 1, runs
    args = re.findall(r'"((?:[^"\\]|\\.)*)"', runs[0])
    for flag in (['--network', 'none'], ['--read-only'], ['--log-driver', 'none'], ['--init'],
                 ['--user', f'{os.getuid()}:{os.getgid()}']):
        assert any(args[i:i + len(flag)] == flag for i in range(len(args))), flag
    for flag in ('--privileged', '--cap-add', '--device', '-e', '--env', '--env-file', '-v', '--volume'):
        assert flag not in args, flag


def test_an_old_container_with_the_same_name_is_not_taken_for_this_run(docker, upstream, tmp_path):
    # The container is named after the process id, which an earlier run's leftover could share.
    out = tmp_path / 'prepared.img'
    p = subprocess.Popen(['bash', '-c', 'read -r _ && exec bash "$0" "$1" "$2"', WRAPPER, upstream, out],
                         stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    name = f'ohimsmart-prepare-{p.pid}'
    try:
        image = subprocess.run(['docker', 'build', '-q', HERE], capture_output=True, text=True,
                               check=True).stdout.strip()
        subprocess.run(['docker', 'run', '--name', name, '--entrypoint', 'true', image],
                       capture_output=True, check=True)          # exited 0, like a finished run
        _, err = p.communicate('go\n' + ''.join(a + '\n' for a in ('', PASSWORD, PASSWORD)), timeout=120)
        assert p.returncode != 0 and 'did not run' in err, err
        assert list(tmp_path.iterdir()) == []
        assert subprocess.run(['docker', 'inspect', name], capture_output=True).returncode == 0, \
            "prepare.sh removed a container that was not its own"
    finally:
        stop(p, name)


def test_an_output_name_starting_with_a_dash_is_a_file_name(docker, upstream, tmp_path):
    r = subprocess.run(['bash', WRAPPER, upstream, '-f.img'], input='\n' + PASSWORD + '\n' + PASSWORD + '\n',
                       capture_output=True, text=True, cwd=tmp_path)
    assert r.returncode == 0, r.stderr
    assert [x.name for x in tmp_path.iterdir()] == ['-f.img']
    assert ((tmp_path / '-f.img').stat().st_mode & 0o777) == 0o600


@pytest.mark.parametrize('verb, answers', [
    ('rm', ('', '', '')),                    # refused, so prepare.sh goes straight to its cleanup
    ('inspect', ('', PASSWORD, PASSWORD)),   # asking the finished container how it ended
])
def test_a_hung_docker_daemon_leaves_no_copy_behind(docker, upstream, tmp_path, verb, answers):
    # A hung daemon never ends this docker command. A hung rm leaves only kill -9; a hung inspect must
    # still let a plain kill (SIGTERM) through. Either way the copy, which may hold the WiFi
    # password, must be gone by then.
    bin_ = tmp_path / 'bin'
    bin_.mkdir()
    real = shutil.which('docker')
    (bin_ / 'docker').write_text(f'#!/bin/sh\n[ "$1" = {verb} ] && exec sleep 300\nexec {real} "$@"\n')
    (bin_ / 'docker').chmod(0o755)
    out_dir = tmp_path / 'out'
    out_dir.mkdir()
    p = subprocess.Popen(['bash', WRAPPER, upstream, out_dir / 'prepared.img'], stdin=subprocess.PIPE,
                         stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, start_new_session=True,
                         env=dict(os.environ, PATH=f'{bin_}:{os.environ["PATH"]}'))
    try:
        p.stdin.write(''.join(a + '\n' for a in answers))
        p.stdin.close()
        deadline = time.time() + 120
        while p.poll() is None and time.time() < deadline:
            if subprocess.run(['pgrep', '-s', str(p.pid), '-f', 'sleep 300'], capture_output=True).returncode == 0:
                break                    # prepare.sh is waiting for the hung command
            time.sleep(0.2)
        assert p.poll() is None, f'prepare.sh ended without calling docker {verb}'
        if verb == 'rm':
            os.killpg(p.pid, signal.SIGKILL)
            p.wait()
        else:
            p.terminate()
            p.wait(timeout=30)
            assert p.returncode != 0
        assert list(out_dir.iterdir()) == []
    finally:
        if p.poll() is None:
            os.killpg(p.pid, signal.SIGKILL)
            p.wait()
        try:
            os.killpg(p.pid, signal.SIGKILL)    # a sleep the stand-in docker may have left
        except ProcessLookupError:
            pass
        stop(p, f'ohimsmart-prepare-{p.pid}')
