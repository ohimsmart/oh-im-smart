"""The welcome page asks job.reboot whether an update needs a restart; an older updater's job only
says it in its message (spec §6.1). Needs node.

  uv run --no-project --with pytest python -m pytest -q kiosk/test_welcome_update.py
"""
import json
import re
import shutil
import subprocess
from pathlib import Path

WELCOME = Path(__file__).with_name('welcome.html')
NODE = shutil.which('node') or 'node'


def run_helpers(expr):
    """Evaluate expr (JSON out) next to the page's needsReboot and updFail."""
    page = WELCOME.read_text(encoding='utf-8')
    lines = [re.search(rf'^const {name} = .*$', page, re.M) for name in ('needsReboot', 'updFail')]
    assert all(lines), 'needsReboot or updFail not found in welcome.html'
    code = '\n'.join(m[0] for m in lines) + f'\nprocess.stdout.write(JSON.stringify({expr}))'
    return json.loads(subprocess.run([NODE, '-e', code], capture_output=True, text=True, check=True).stdout)


def test_needs_reboot_reads_the_flag_first():
    cases = [({'reboot': True}, True),
             ({'reboot': False, 'message': '系统层已更新到 1.0.1，部分改动重启设备后生效'}, False),
             ({'message': '系统层已更新到 1.0.1，部分改动重启设备后生效'}, True),
             ({'message': '已更新到 1.0.1'}, False)]
    jobs = json.dumps([job for job, _ in cases], ensure_ascii=False)
    assert run_helpers(f'{jobs}.map(needsReboot)') == [want for _, want in cases]
    assert WELCOME.read_text(encoding='utf-8').count('/重启设备后生效/.test') == 1    # only inside needsReboot


def test_a_failed_client_after_a_restart_needing_system_layer_still_says_restart():
    jobs = json.dumps([{'state': 'failed', 'message': '连不上更新服务器', 'reboot': True},
                       {'state': 'failed', 'message': '连不上更新服务器', 'reboot': False},
                       # a done job already says it in its own message: not twice
                       {'state': 'done', 'message': '系统层已更新到 1.0.1，部分改动重启设备后生效', 'reboot': True}],
                      ensure_ascii=False)
    assert run_helpers(f'{jobs}.map(updFail)') == ['连不上更新服务器。系统层的部分改动重启设备后生效', '连不上更新服务器',
                                                    '系统层已更新到 1.0.1，部分改动重启设备后生效']


def test_the_page_script_still_parses(tmp_path):
    """The helpers sit between statements, not inside UPD_STAGE: node must parse the whole script."""
    scripts = re.findall(r'<script>(.*?)</script>', WELCOME.read_text(encoding='utf-8'), re.S)
    assert scripts
    for i, js in enumerate(scripts):
        f = tmp_path / f'welcome-{i}.js'
        f.write_text(js, encoding='utf-8')
        r = subprocess.run([NODE, '--check', str(f)], capture_output=True, text=True)
        assert r.returncode == 0, r.stderr
