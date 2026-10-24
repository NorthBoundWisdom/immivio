"""Physical-headset checks for the selected upstream ports.

Requires the exact installed Debug APK and synthetic files staged in
/storage/emulated/0/Movies/ImmivioAcceptance20261024. Uses software-generated
ray events through production menus, not physical controller actuation.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shlex
import subprocess
import time
import uuid

PACKAGE = 'com.northboundwisdom.immivio'

class Device:
    def __init__(self, adb, port, serial, out):
        self.base = [adb, '-P', str(port), '-s', serial]
        self.out = Path(out)
        self.out.mkdir(parents=True, exist_ok=True)
        self.shell('input', 'keyevent', 'KEYCODE_WAKEUP')

    def adb(self, *args, timeout=30):
        result = subprocess.run(self.base + list(args), capture_output=True, timeout=timeout)
        if result.returncode:
            raise RuntimeError(result.stderr.decode(errors='replace'))
        return result.stdout

    def shell(self, *args):
        return self.adb('shell', shlex.join(list(args)))

    def read(self, path):
        try:
            return json.loads(self.adb('exec-out', 'run-as', PACKAGE, 'cat', 'files/diagnostics/' + path))
        except (ValueError, RuntimeError):
            return {}

    def command(self, operation, extras=None, wait=None, timeout=35):
        key = 'accept_' + uuid.uuid4().hex[:16]
        args = ['am', 'broadcast', '-n', PACKAGE + '/org.vrpassthroughplayer.plugin.DebugDiagnosticsReceiver',
                '-a', PACKAGE + '.DEBUG_PLAYER_MPV', '--es', 'request', key, '--es', 'operation', operation]
        for kind, name, value in extras or []:
            args += [kind, name, str(value)]
        self.shell(*args)
        start = time.monotonic()
        receipt = {}
        report = {}
        observations = []
        while time.monotonic() - start < timeout:
            receipt = self.read('debug_request_' + key + '.json')
            if receipt and receipt.get('state') != 'accepted':
                raise RuntimeError(str(receipt))
            if receipt:
                report = self.read('mpv_player_' + str(receipt['id']) + '.json')
                if report:
                    observations.append({'elapsed': round(time.monotonic()-start, 3), 'state': report.get('media',{}).get('state'), 'feedback': report.get('loading_feedback',{}), 'read_bytes_per_second': report.get('native_status',{}).get('details',{}).get('read_bytes_per_second') if report.get('native_status',{}).get('session_id') == report.get('media',{}).get('session_id') else None})
                    observations = observations[-120:]
                if any(c.get('request_key') == key for c in report.get('commands', [])) and (wait is None or wait(report, key)):
                    report["device_observations"] = observations
                    self.save(key, receipt, report)
                    return report, key
            time.sleep(0.2)
        self.save(key, receipt, report)
        raise TimeoutError(operation + ': no matching completion: ' + key)

    def save(self, key, receipt, report):
        (self.out / (key + '.json')).write_text(json.dumps({'receipt': receipt, 'report': report}, indent=2) + '\n')

    def step(self, step):
        report, key = self.command('selected_features_ui', [('--es', 'step', step)],
            wait=lambda r,k: r.get('selected_features_ui', {}).get('request_key') == k, timeout=45)
        result = report['selected_features_ui']
        for item in result['checks']:
            print(('PASS' if item['passed'] else 'FAIL') + ': ' + item['title'] + ' ' + str(item.get('details')), flush=True)
        (self.out / (step + '.json')).write_text(json.dumps(result, indent=2) + '\n')
        for local, command in [(step + '-ui.png', ['exec-out','run-as',PACKAGE,'cat','files/diagnostics/acceptance_' + key + '.png']),
                               (step + '-headset.png', ['exec-out','screencap','-p'])]:
            data = self.adb(*command)
            if data.startswith(b'\x89PNG'):
                (self.out / local).write_bytes(data)
        if step == 'library':
            data = self.adb('exec-out','run-as',PACKAGE,'cat','files/diagnostics/acceptance_' + key + '_compact.png')
            if data.startswith(b'\x89PNG'):
                (self.out / 'library-compact-ui.png').write_bytes(data)
        return result

def main():
    global PACKAGE
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--package', default=PACKAGE)
    parser.add_argument('--adb', default='adb')
    parser.add_argument('--port', type=int, default=5037)
    parser.add_argument('--serial', required=True)
    parser.add_argument('--apk', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--step', choices=['setup','browse','restore','controls','cinema','library','snapshot','error'])
    parser.add_argument('--open-local')
    parser.add_argument('--open-uri')
    parser.add_argument('--expect-error')
    args = parser.parse_args()
    PACKAGE = args.package
    d = Device(args.adb, args.port, args.serial, args.out)
    if d.shell('getprop', 'ro.kernel.qemu').strip() == b'1':
        raise RuntimeError('A physical headset is required')
    installed = d.shell('pm','path',PACKAGE).decode().strip().removeprefix('package:')
    actual = d.shell('sha256sum',installed).decode().split()[0]
    expected = hashlib.sha256(args.apk.read_bytes()).hexdigest()
    if actual != expected:
        raise RuntimeError('Installed APK hash differs from --apk')
    if args.step:
        result = d.step(args.step)
        raise SystemExit(0 if result['passed'] else 1)
    if args.open_local or args.open_uri:
        extra = [('--es','local_path',args.open_local)] if args.open_local else [('--es','uri',args.open_uri)]
        extra += [('--ez','stereo','false'),('--ez','benchmark','true'),('--ei','projection','0')]
        def ready(report, key):
            media = report.get('media',{})
            if media.get('state') == 'failed': return True
            native = report.get('native_status',{})
            return media.get('frame_counter',0) >= 5 and native.get('session_id') == media.get('session_id') and native.get('generation') == media.get('generation') and native.get('post_draw_frames',0) > 0
        report,key = d.command('open', extra, wait=ready, timeout=50)
        media = report['media']
        result = {'request':key,'apk_sha256':actual,'state':media['state'],'error':media.get('error'),
                  'frames':media['frame_counter'],'native_post_draw_frames':report.get('native_status',{}).get('post_draw_frames'),
                  'diagnostic_2d':report.get('diagnostic_2d'),'format':media.get('format')}
        (args.out/'last-open.json').write_text(json.dumps(result,indent=2)+'\n')
        print(json.dumps(result,indent=2),flush=True)
        if args.expect_error:
            raise SystemExit(0 if media.get('error') == args.expect_error else 1)
        raise SystemExit(0 if media.get('state') != 'failed' and not report.get('diagnostic_2d') else 1)
    parser.error('Choose --step, --open-local or --open-uri')

if __name__ == '__main__':
    main()
