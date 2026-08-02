"""Tests for centurion.license state machine, store, enforcement, and attestations."""

from __future__ import annotations

import os
import time
from pathlib import Path
from unittest.mock import patch

import pytest

from centurion.license.activate import activate_trial, redeem_outright_token
from centurion.license.balance import (
    apply_paid_off_attestation,
    apply_server_balance,
    is_paid_off,
    remaining_gbp,
)
from centurion.license.enforcement import (
    EnforcementMode,
    enforcement_enabled,
    evaluate,
)
from centurion.license.fingerprint import compute_fingerprint
from centurion.license.phone_home import apply_checkin_result, is_phone_home_due
from centurion.license.states import (
    InvalidTransition,
    LicenseState,
    can_transition,
    is_permanently_owned,
    parse_state,
    requires_phone_home,
    transition,
)
from centurion.license.store import (
    Entitlement,
    load_entitlement,
    save_entitlement,
    seed_entitlement,
)
from tests.fixtures.license_server import (
    generate_test_ca,
    make_outright_attestation,
    make_paid_off_attestation,
)
from centurion.license.phone_home import CheckinResult


@pytest.fixture
def license_home(tmp_path, monkeypatch):
    home = tmp_path / ".centurion"
    home.mkdir()
    monkeypatch.setenv("CENTURION_HOME", str(home))
    monkeypatch.setattr(Path, "home", lambda: tmp_path)
    return home


class TestStateMachine:
    def test_allowed_activate_paths(self):
        assert can_transition(LicenseState.UNACTIVATED, LicenseState.TRIAL)
        assert can_transition(LicenseState.UNACTIVATED, LicenseState.SUBSCRIPTION_ACTIVE)
        assert can_transition(LicenseState.UNACTIVATED, LicenseState.OUTRIGHT_OWNED)

    def test_paid_off_is_terminal(self):
        assert is_permanently_owned(LicenseState.RENT_TO_OWN_PAID_OFF)
        assert is_permanently_owned(LicenseState.OUTRIGHT_OWNED)
        assert not requires_phone_home(LicenseState.OUTRIGHT_OWNED)
        with pytest.raises(InvalidTransition):
            transition(LicenseState.OUTRIGHT_OWNED, LicenseState.LOCKED)

    def test_locked_can_reactivate(self):
        assert can_transition(LicenseState.LOCKED, LicenseState.SUBSCRIPTION_ACTIVE)

    def test_website_state_aliases(self):
        assert parse_state("owned") == LicenseState.OUTRIGHT_OWNED
        assert parse_state("grace") == LicenseState.GRACE
        assert parse_state("expired") == LicenseState.SUBSCRIPTION_EXPIRED
        assert parse_state("rent_to_own_active") == LicenseState.RENT_TO_OWN_ACTIVE
        assert requires_phone_home(LicenseState.GRACE)


class TestStore:
    def test_roundtrip_encrypted(self, license_home):
        ent = Entitlement(
            state=LicenseState.SUBSCRIPTION_ACTIVE.value,
            tier="subscription",
            license_id="lic_test",
            machine_fingerprint="abc123",
            last_verified_at=time.time(),
        )
        save_entitlement(ent)
        loaded = load_entitlement()
        assert loaded.state == "subscription_active"
        assert loaded.license_id == "lic_test"
        assert (license_home / "license" / "entitlement.json.enc").exists()
        assert (license_home / "license" / "device.key").exists()

    def test_seed_entitlement(self, license_home):
        ent = seed_entitlement(
            {
                "state": "outright_owned",
                "tier": "outright",
                "license_id": "lic_own",
                "customer_name": "Ada",
                "shipment_id": "ship_1",
            }
        )
        assert ent.customer_name == "Ada"
        assert load_entitlement().shipment_id == "ship_1"


class TestFingerprint:
    def test_stable_with_fixed_parts(self, license_home):
        parts = {
            "install_id": "fixed-id",
            "os_machine_id": "machine-1",
            "platform": "darwin",
        }
        a = compute_fingerprint(parts=parts)
        b = compute_fingerprint(parts=parts)
        assert a == b
        assert len(a) == 64


class TestEnforcement:
    def test_disabled_by_default(self, license_home):
        assert enforcement_enabled({"license": {"enabled": False}}) is False
        decision = evaluate(config={"license": {"enabled": False, "enforcement": False}})
        assert decision.mode == EnforcementMode.ALLOW

    def test_unactivated_locks_when_enforced(self, license_home):
        config = {"license": {"enabled": True, "enforcement": True}}
        decision = evaluate(config=config)
        assert decision.mode == EnforcementMode.LOCKED

    def test_grace_warn_then_lock(self, license_home):
        now = 1_700_000_000.0
        ent = Entitlement(
            state=LicenseState.SUBSCRIPTION_ACTIVE.value,
            tier="subscription",
            license_id="lic",
            last_verified_at=now - 40 * 86400,
            next_check_by=now - 10 * 86400,
        )
        save_entitlement(ent)
        config = {
            "license": {
                "enabled": True,
                "enforcement": True,
                "grace_warn_days": 7,
                "grace_restrict_days": 14,
                "grace_lock_days": 15,
            }
        }
        # 3 days overdue → warn
        d1 = evaluate(config=config, now=now - 7 * 86400)
        assert d1.mode == EnforcementMode.WARN
        # reload after grace_started written
        d2 = evaluate(config=config, now=now)  # ~10 days overdue from next_check_by
        assert d2.mode in {EnforcementMode.WARN, EnforcementMode.RESTRICTED, EnforcementMode.LOCKED}


class TestBalanceAndAttestation:
    def test_paid_off_requires_attestation(self, license_home):
        priv, pub, _b64 = generate_test_ca()
        fp = "f" * 64
        ent = Entitlement(
            state=LicenseState.RENT_TO_OWN_ACTIVE.value,
            tier="rent_to_own",
            license_id="lic_rto",
            machine_fingerprint=fp,
            balance_paid_gbp=4750,
            balance_target_gbp=5000,
        )
        save_entitlement(ent)
        apply_server_balance(ent, balance_paid_gbp=5000)
        assert remaining_gbp(load_entitlement()) == 0
        # Still not paid_off state until attestation
        assert load_entitlement().state == "rent_to_own_active"

        token = make_paid_off_attestation(priv, license_id="lic_rto", fingerprint=fp)
        apply_paid_off_attestation(ent, token, public_key=pub)
        loaded = load_entitlement()
        assert loaded.state == "rent_to_own_paid_off"
        assert is_paid_off(loaded)
        assert not is_phone_home_due(loaded)

    def test_outright_redeem_offline(self, license_home):
        priv, pub, b64 = generate_test_ca()
        with patch(
            "centurion.license.activate.compute_fingerprint",
            return_value="a" * 64,
        ), patch(
            "centurion.license.fingerprint.compute_fingerprint",
            return_value="a" * 64,
        ):
            token = make_outright_attestation(
                priv, license_id="lic_out", fingerprint="a" * 64
            )
            config = {"license": {"ca_public_key_b64": b64}}
            result = redeem_outright_token(
                "pop_test",
                config=config,
                offline_attestation=token,
            )
            assert result.ok
            assert load_entitlement().state == "outright_owned"


class TestPhoneHomeApply:
    def test_revoke_locks_immediately(self, license_home):
        ent = Entitlement(
            state=LicenseState.SUBSCRIPTION_ACTIVE.value,
            tier="subscription",
            license_id="lic",
            last_verified_at=time.time(),
        )
        result = CheckinResult(
            ok=False,
            state="locked",
            revoke_reason="chargeback",
        )
        apply_checkin_result(ent, result)
        assert load_entitlement().state == "locked"
        assert load_entitlement().revoke_reason == "chargeback"


class TestTrial:
    def test_offline_trial(self, license_home):
        result = activate_trial(days=7, offline=True)
        assert result.ok
        ent = load_entitlement()
        assert ent.state == "trial"
        assert ent.trial_expires_at is not None


class TestImageBuilder:
    def test_build_image_seed(self, license_home):
        from centurion.install.image_builder import ImageBuildSpec, build_image_seed

        with patch("centurion.install.image_builder._enable_license_config"):
            result = build_image_seed(
                ImageBuildSpec(
                    customer_name="Helen",
                    tier="outright",
                    license_id="lic_dify",
                    shipment_id="ship_9",
                )
            )
        assert result["ok"]
        assert Path(result["manifest"]).exists()
        ent = load_entitlement()
        assert ent.state == "outright_owned"
        assert ent.shipment_id == "ship_9"


class TestRemoteBridge:
    def test_license_status_action(self, license_home):
        from centurion_cli.remote_bridge import handle_request

        seed_entitlement(
            {
                "state": "subscription_active",
                "tier": "subscription",
                "license_id": "lic_rb",
            }
        )
        resp = handle_request({"id": "1", "action": "license_status"})
        assert resp["ok"] is True
        assert resp["license"]["license_id"] == "lic_rb"
