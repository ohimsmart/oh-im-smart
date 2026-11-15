"""tools/check-readmes.sh: the three tutorials give the same commands and addresses (spec §7.1)."""
import subprocess
from pathlib import Path

import pytest

HERE = Path(__file__).parent
CHECK = HERE / 'check-readmes.sh'
LINKS = {'README.md': '[繁體中文](README.zh-Hant.md) | [English](README.en.md)',
         'README.zh-Hant.md': '[简体中文](README.md) | [English](README.en.md)',
         'README.en.md': '[简体中文](README.md) | [繁體中文](README.zh-Hant.md)'}
PROSE = {'README.md': ('打开 http://<设备IP>:16688/admin 看看。', '<设备IP>', '# 先清掉旧记录'),
         'README.zh-Hant.md': ('打開 http://<裝置IP>:16688/admin 看看。', '<裝置IP>', '# 先清掉舊紀錄'),
         'README.en.md': ('Open http://<DEVICE_IP>:16688/admin.', '<DEVICE_IP>', '# clear the old entry first')}


def readme(name, command='ssh-keygen -R {ip}', url='https://github.com/ohimsmart/oh-im-smart/releases'):
    prose, ip, comment = PROSE[name]
    return f"""# Title

{LINKS[name]}

{prose} Releases: [{url}]({url}).

```bash
{comment}
{command.format(ip=ip)}    {comment}

ping -c 3 172.16.42.1
curl -s http://{ip}:16688/admin | grep -o '<title>[^<]*'
```

```
expected output differs: {prose}
```

   ```powershell
   Get-FileHash .\\x.img -Algorithm SHA256
   ```
"""


def run(tmp_path, **override):
    for name in LINKS:
        (tmp_path / name).write_text(override.get(name, readme(name)), encoding='utf-8')
    return subprocess.run(['bash', CHECK, tmp_path], capture_output=True, text=True, encoding='utf-8')


def test_tutorials_that_agree_pass(tmp_path):
    r = run(tmp_path)
    assert r.returncode == 0, r.stderr
    assert 'agree' in r.stdout


@pytest.mark.parametrize('name', ['README.zh-Hant.md', 'README.en.md'])
def test_a_different_command_fails_and_is_shown(tmp_path, name):
    r = run(tmp_path, **{name: readme(name, command='ssh-keygen -R {ip} -f ~/.ssh/other')})
    assert r.returncode == 1
    assert f'the commands of {name} differ' in r.stderr and '-f ~/.ssh/other' in r.stderr


def test_a_different_address_fails(tmp_path):
    r = run(tmp_path, **{'README.en.md': readme('README.en.md', url='https://github.com/justhalfbit/x/releases')})
    assert r.returncode == 1
    assert 'the urls of README.en.md differ' in r.stderr and 'justhalfbit' in r.stderr


def test_a_tag_in_a_command_is_not_a_placeholder(tmp_path):
    text = readme('README.en.md').replace("'<title>", "'<head>")
    r = run(tmp_path, **{'README.en.md': text})
    assert r.returncode == 1 and '<head>' in r.stderr and '<title>' in r.stderr


@pytest.mark.parametrize('command', ['cat < {} > b.img', 'cat <{} >b.img', 'cat <{}>b.img'])
def test_redirections_are_not_placeholders(tmp_path, command):
    files = {name: readme(name, command=command.format('a.img')) for name in LINKS}
    files['README.en.md'] = readme('README.en.md', command=command.format('c.img'))
    r = run(tmp_path, **files)
    assert r.returncode == 1 and 'c.img' in r.stderr


def test_an_indented_block_is_compared_too(tmp_path):
    text = readme('README.en.md').replace('-Algorithm SHA256', '-Algorithm SHA1')
    r = run(tmp_path, **{'README.en.md': text})
    assert r.returncode == 1 and 'SHA1' in r.stderr


def test_a_missing_language_link_fails(tmp_path):
    text = readme('README.zh-Hant.md').replace('[English](README.en.md)', 'English')
    r = run(tmp_path, **{'README.zh-Hant.md': text})
    assert r.returncode == 1 and 'README.zh-Hant.md does not link to README.en.md' in r.stderr


def test_a_missing_tutorial_fails(tmp_path):
    run(tmp_path)
    (tmp_path / 'README.zh-Hant.md').unlink()
    r = subprocess.run(['bash', CHECK, tmp_path], capture_output=True, text=True, encoding='utf-8')
    assert r.returncode == 1 and 'README.zh-Hant.md is missing' in r.stderr


def test_the_repository_tutorials_agree():
    r = subprocess.run(['bash', CHECK], capture_output=True, text=True, encoding='utf-8')
    assert r.returncode == 0, r.stderr
