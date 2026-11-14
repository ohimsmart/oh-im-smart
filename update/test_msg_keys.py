"""Every message the updater gives the pages is a msg() key with its parameters (spec §6.1), and
msg_keys.json lists them all: the client's dictionaries (tests/updater_keys.json there is a copy) and
the welcome page's take their entries from it.

  GIT_CONFIG_GLOBAL=/dev/null uv run --no-project --with pytest python -m pytest -q update
"""
import ast
import json
import re
from pathlib import Path

HERE = Path(__file__).parent
SCRIPT = HERE / 'thinksmart-update'
KEYS = HERE / 'msg_keys.json'
CHINESE = re.compile('[　-〿一-鿿＀-￯]')     # ideographs and fullwidth punctuation
PLACEHOLDER = re.compile(r'\{(\w+)\}')


def collect(src):
    """(keys, problems): every msg()/Fail() key; a problem for each Chinese text that isn't one, each
    key that isn't a plain literal or whose {placeholders} differ from its parameters, and each
    set_job() given text instead of a message."""
    tree = ast.parse(src)
    keys, problems, key_nodes = set(), [], set()
    for n in ast.walk(tree):
        if not isinstance(n, ast.Call) or not isinstance(n.func, ast.Name):
            continue
        if n.func.id in ('msg', 'Fail'):
            a = n.args[0] if n.args else None
            if len(n.args) != 1 or not (isinstance(a, ast.Constant) and isinstance(a.value, str)):
                problems.append(f'line {n.lineno}: {n.func.id}() needs one literal key')
                continue
            key_nodes.add(id(a))
            params = {k.arg for k in n.keywords}
            if params != set(PLACEHOLDER.findall(a.value)):
                problems.append(f'line {n.lineno}: {a.value!r} has params {sorted(map(str, params))}')
            keys.add(a.value)
        elif n.func.id == 'set_job':
            m = n.args[3] if len(n.args) > 3 else next((k.value for k in n.keywords if k.arg == 'message'), None)
            if m is None or isinstance(m, (ast.Constant, ast.JoinedStr, ast.BinOp)):
                problems.append(f'line {n.lineno}: set_job() needs a message, not text')
    for n in ast.walk(tree):
        if isinstance(n, ast.Constant) and isinstance(n.value, str) and CHINESE.search(n.value) and id(n) not in key_nodes:
            problems.append(f'line {n.lineno}: Chinese text outside msg()/Fail(): {n.value!r}')
    return keys, problems


def test_every_message_is_a_literal_key_with_its_parameters():
    keys, problems = collect(SCRIPT.read_text(encoding='utf-8'))
    assert problems == []
    assert keys == set(json.loads(KEYS.read_text(encoding='utf-8')))


def test_the_key_list_is_sorted_and_no_key_ends_a_sentence():
    keys = json.loads(KEYS.read_text(encoding='utf-8'))
    assert keys == sorted(set(keys))
    assert [k for k in keys if k.endswith('。')] == []     # the client page adds 。可以再试一次


def test_the_collector_catches_what_it_must():
    good = '''
SYS = {'kiosk': msg('屏幕界面没有启动起来')}
def f(st, v, e):
    raise Fail('{version} 不比现在的 {current} 新', version=v, current='1')
    set_job(st, 'failed', v, msg('安装出错：{error}', error=str(e)))
    set_job(st, 'failed', v, e.msg)
'''
    bad = '''
def f(st, v, e, k):
    raise Fail(f'{v} 不比现在的新')
    set_job(st, 'failed', v, '安装出错：' + str(e))
    x = msg('已更新到 {version}', ver=v)
    y = msg(k)
    z = v + '，'
'''
    assert collect(good) == ({'屏幕界面没有启动起来', '{version} 不比现在的 {current} 新', '安装出错：{error}'}, [])
    keys, problems = collect(bad)
    assert keys == {'已更新到 {version}'}
    assert sorted(p.split(':')[0] for p in problems) == ['line 3', 'line 3', 'line 4', 'line 4', 'line 5', 'line 6', 'line 7']
