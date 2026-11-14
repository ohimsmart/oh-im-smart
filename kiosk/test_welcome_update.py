"""The welcome page asks job.reboot whether an update needs a restart; an older updater's job only
says it in its message (spec §6.1). Needs node.

  uv run --no-project --with pytest python -m pytest -q kiosk/test_welcome_update.py
"""
import json
import re
import subprocess
from pathlib import Path

from welcome_js import NODE, page_lines, run

WELCOME = Path(__file__).with_name('welcome.html')
HELPERS = page_lines('needsReboot', 'updMsg', 'updFail')


def run_helpers(expr, lang='zh-Hans'):
    """Evaluate expr (JSON out) next to the page's needsReboot, updMsg and updFail."""
    return run(expr, lang, HELPERS)


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


def test_the_english_page_translates_the_updaters_message():
    why = {'msg_key': '屏幕界面没有启动起来', 'msg_params': {}}
    jobs = [{'state': 'failed', 'message': '连不上更新服务器', 'msg_key': '连不上更新服务器', 'msg_params': {},
             'reboot': True},
            {'state': 'failed', 'message': '1.0.2 自检没通过（屏幕界面没有启动起来），已退回 1.0.1',
             'msg_key': '{version} 自检没通过（{why}），已退回 {old}',
             'msg_params': {'version': '1.0.2', 'why': why, 'old': '1.0.1'}, 'reboot': False},
            {'state': 'failed', 'message': '下载太慢'}]      # an older updater: no key, its Chinese as it is
    assert run_helpers(f'{json.dumps(jobs, ensure_ascii=False)}.map(updFail)', 'en') == [
        'Can’t reach the update server. Some system layer changes take effect after a restart',
        '1.0.2 failed its self-test (the screen interface did not start); went back to 1.0.1',
        '下载太慢']
