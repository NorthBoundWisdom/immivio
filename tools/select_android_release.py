#!/usr/bin/env python3
"""Bind a release tag to its successful Android workflow run before downloading assets."""
import argparse
import json
import os
from pathlib import Path
import subprocess
from urllib.parse import quote

BUILD_JOBS = {'Release / Windows', 'Release / macOS'}
LEGACY_BUILD_JOBS = {'Release / windows-2025', 'Release / macos-15'}


def validate(repository, tag, run, commit, jobs, current_run_id=''):
    if not tag or tag.startswith('-') or any(c in tag for c in '\r\n'):
        raise ValueError('Invalid release tag')
    if run.get('head_repository', {}).get('full_name') != repository:
        raise ValueError('Release build belongs to a different repository')
    if (run.get('event') != 'push' or run.get('head_branch') != tag
            or run.get('head_sha') != commit or run.get('path') != '.github/workflows/android-release.yml'):
        raise ValueError('Release build is not the tag-matched Android workflow')
    # The automatic caller is still in progress while its release job runs.
    same_run = str(run.get('id')) == str(current_run_id)
    if run.get('conclusion') != 'success' and not (same_run and run.get('status') == 'in_progress'):
        raise ValueError('Source Android workflow did not succeed')
    results = {job['name']: job.get('conclusion') for job in jobs}
    if not any(all(results.get(name) == 'success' for name in group)
               for group in (BUILD_JOBS, LEGACY_BUILD_JOBS)):
        raise ValueError('Both Windows/macOS Release builds must succeed')
    return commit


def api(endpoint):
    return json.loads(subprocess.check_output(['gh', 'api', endpoint], text=True))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repository', required=True)
    parser.add_argument('--tag', required=True)
    parser.add_argument('--run-id', required=True, type=int)
    args = parser.parse_args()
    base = f'repos/{args.repository}'
    run = api(f'{base}/actions/runs/{args.run_id}')
    ref = api(f'{base}/git/ref/tags/{quote(args.tag, safe="")}')['object']
    for _ in range(10):
        if ref['type'] == 'commit': break
        if ref['type'] != 'tag': raise ValueError('Tag does not reference a commit')
        ref = api(f'{base}/git/tags/{ref["sha"]}')['object']
    else:
        raise ValueError('Tag reference chain is too deep')
    jobs = api(f'{base}/actions/runs/{args.run_id}/jobs?per_page=100&filter=latest')['jobs']
    commit = validate(args.repository, args.tag, run, ref['sha'], jobs, os.environ.get('GITHUB_RUN_ID', ''))
    if os.environ.get('GITHUB_OUTPUT'):
        with Path(os.environ['GITHUB_OUTPUT']).open('a', encoding='utf-8') as output:
            output.write(f'commit={commit}\n')
    print(f'Verified {args.tag} at {commit[:7]} against Android run {args.run_id}')


if __name__ == '__main__':
    main()
