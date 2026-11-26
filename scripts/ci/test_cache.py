"""Fast offline CI checks: python3 -B scripts/ci/test_cache.py."""

import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest


REPO = Path(__file__).resolve().parents[2]
WORKFLOW = Path(".github/workflows/ci.yml")
TOOLCHAIN = Path("scripts/ci/toolchain.sh")


class KeyTests(unittest.TestCase):
    def test_key_tracks_toolchain_inputs_not_source(self):
        with tempfile.TemporaryDirectory() as temp:
            source = Path(temp) / "source"
            inputs = ("cobalt.opam", "dune-project", TOOLCHAIN, WORKFLOW)
            for name in inputs:
                destination = source / name
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(REPO / name, destination)
            env = dict(os.environ, OPAMROOT=str(Path(temp) / "opam"),
                       OPAMSWITCH="5.2.0+ox")
            tools = Path(temp) / "tools"
            tools.mkdir()
            host_query = tools / "dpkg-query"
            host_query.write_text("#!/bin/sh\nprintf '%s\\n' \"$CI_TEST_HOST_PACKAGES\"\n")
            host_query.chmod(0o755)
            env.update(PATH=f"{tools}:{os.defpath}", CI_TEST_HOST_PACKAGES="libgmp 1")

            def key(**changes):
                result = subprocess.run(["bash", str(TOOLCHAIN), "key"], cwd=source,
                                        env=dict(env, **changes), text=True,
                                        capture_output=True, timeout=10)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                return result.stdout.strip()

            baseline = key()
            self.assertRegex(baseline, r"^cobalt-.*[0-9a-f]{64}$")
            (source / "changed.ml").write_text("let changed = true\n")
            self.assertEqual(baseline, key())
            self.assertNotEqual(baseline, key(OPAMROOT=str(Path(temp) / "other-opam")))
            self.assertNotEqual(baseline, key(CI_TEST_HOST_PACKAGES="libgmp 2"))
            self.assertNotEqual(baseline, key(ImageVersion="updated-image"))
            for name in inputs:
                with self.subTest(name=name):
                    path = source / name
                    previous = path.read_bytes()
                    try:
                        path.write_bytes(previous + b"\n# changed\n")
                        self.assertNotEqual(baseline, key())
                    finally:
                        path.write_bytes(previous)


class WorkflowTests(unittest.TestCase):
    def test_automatic_and_manual_triggers(self):
        workflow = (REPO / WORKFLOW).read_text()
        triggers = re.search(r"(?m)^on:\n((?: +[^\n]*\n)+)", workflow).group(1)
        self.assertEqual(re.findall(r"(?m)^  (\w+):", triggers),
                         ["pull_request", "push", "workflow_dispatch"])
        self.assertRegex(triggers, r"(?m)^  pull_request:\s*\n  push:")
        self.assertRegex(triggers, r"(?m)^  push:\n    branches:\n      - oxcaml\n"
                         r"    tags:\n      - 'v\*'\n  workflow_dispatch:")
        self.assertRegex(triggers, r"(?m)^      cold:\n"
                         r"(?:        [^\n]*\n)*?        type: boolean\n"
                         r"        default: false$")
        concurrency = re.search(r"(?m)^concurrency:\n((?: +[^\n]*\n)+)", workflow).group(1)
        self.assertIn("group: ${{ github.event_name == 'pull_request' && "
                      "format('cobalt-native-pr-{0}', github.event.pull_request.number) || "
                      "format('cobalt-native-run-{0}-{1}', github.run_id, github.run_attempt) }}",
                      concurrency)
        self.assertIn("cancel-in-progress: ${{ github.event_name == 'pull_request' }}",
                      concurrency)

    def test_exact_cache_policy_and_unconditional_source_tests(self):
        workflow = (REPO / WORKFLOW).read_text()
        steps = re.split(r"(?m)^      - name: ", workflow)[1:]
        stages = ("toolchain.sh key", "uses: actions/cache/restore@", "toolchain.sh provision",
                  "toolchain.sh verify", "uses: actions/cache/save@", "scripts/ci/check.sh")
        indices = [next(i for i, step in enumerate(steps) if stage in step) for stage in stages]
        self.assertEqual(indices, sorted(set(indices)))
        setup, restore, provision, verify, save, build = [steps[i] for i in indices]

        def field(step, name):
            return re.findall(rf"(?m)^ +{name}: (.+)$", step)

        self.assertEqual(field(setup, "id"), ["setup"])
        self.assertEqual(field(restore, "id"), ["restore"])
        self.assertEqual(field(build, "if"), [])
        self.assertEqual(sum("uses: actions/cache" in step for step in steps), 2)
        for step in (restore, save):
            self.assertEqual(field(step, "key"), ["${{ steps.setup.outputs.key }}"])
            self.assertEqual(field(step, "path"), ["${{ env.OPAMROOT }}"])
            self.assertNotIn("restore-keys:", step)
        self.assertIn("OPAMROOT: /home/runner/.cobalt-ci-opam", workflow)
        self.assertIn("OPAMSWITCH: 5.2.0+ox", workflow)
        self.assertIn("DUNE_CACHE: disabled", workflow)
        self.assertEqual(field(restore, "if"),
                         ["${{ !(github.event_name == 'workflow_dispatch' && inputs.cold) }}"])
        self.assertEqual(field(provision, "if"), ["${{ steps.restore.outputs.cache-hit != 'true' }}"])
        self.assertEqual(field(verify, "if"), ["${{ steps.restore.outputs.cache-hit == 'true' }}"])
        self.assertEqual(field(save, "if"),
                         ["${{ github.event_name != 'pull_request' && "
                          "github.ref == 'refs/heads/oxcaml' && "
                          "!(github.event_name == 'workflow_dispatch' && inputs.cold) && "
                          "steps.restore.outputs.cache-hit != 'true' }}"])


if __name__ == "__main__":
    unittest.main()
