"""Exercise the command boundary with runuser mocked, without requiring root."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]

class ControlTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        base = Path(self.tmp.name)
        self.record = base / 'record.json'
        runner = base / 'runuser'
        runner.write_text('#!/usr/bin/python3\nimport json,sys\nfrom pathlib import Path\n'
                          f'Path({str(self.record)!r}).write_text(json.dumps({{"args":sys.argv[1:],"stdin":sys.stdin.read()}}))\n')
        runner.chmod(0o755)
        fake_id = base / 'id'
        fake_id.write_text('#!/bin/sh\necho 12345\n')
        fake_id.chmod(0o755)
        code = (ROOT / 'scripts/github-lab-control.sh').read_text()
        code = code.replace('[[ $EUID != 0 ]]', '[[ 0 != 0 ]]')
        code = code.replace('/usr/bin/id', str(fake_id)).replace('/usr/sbin/runuser', str(runner))
        self.helper = base / 'helper'
        self.helper.write_text(code)

    def call(self, *args, stdin=''):
        return subprocess.run(['/bin/bash', str(self.helper), *args], input=stdin,
                              text=True, capture_output=True)

    def test_reject_unknown_and_extra_arguments(self):
        for args in [('status; id',), ('exec', 'id'), ()]:
            self.assertEqual(self.call(*args).returncode, 2)
        self.assertFalse(self.record.exists())

    def test_exec_passes_script_as_stdin_after_user_switch(self):
        payload = 'echo "$(id)"; printf "hello\\n"\n'
        self.assertEqual(self.call('exec', stdin=payload).returncode, 0)
        record = json.loads(self.record.read_text())
        self.assertEqual(record['stdin'], payload)
        args = record['args']
        self.assertEqual(args[:5], ['-u', 'pc-lab', '--', '/usr/bin/env', '-i'])
        self.assertIn('DOCKER_HOST=unix:///run/user/12345/docker.sock', args)
        self.assertNotIn(payload, args)
        self.assertIn('HOME=/home/pc-lab', args)

    def test_predefined_actions_use_fixed_commands(self):
        for action in ['status', 'up', 'stop', 'down', 'logs']:
            self.assertEqual(self.call(action).returncode, 0)
            record = json.loads(self.record.read_text())
            self.assertEqual(record['args'][:3], ['-u', 'pc-lab', '--'])
            self.assertIn('docker compose', record['args'][-1])

if __name__ == '__main__':
    unittest.main()
