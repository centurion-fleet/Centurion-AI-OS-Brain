"""Family Beneficiary GHL sync (iPhone Settings → Brain → GoHighLevel)."""

from __future__ import annotations

from unittest.mock import patch

from centurion_cli import beneficiary_state as bs


def test_submit_referral_pushes_ghl(tmp_path, monkeypatch):
    monkeypatch.setenv("CENTURION_HOME", str(tmp_path / ".centurion"))
    pushed = {}

    def fake_push(referral):
        pushed.update(referral)

    with patch("centurion_cli.beneficiary_cloud.push_colleague_referral", fake_push):
        bs.set_family_beneficiary("Alex")
        snap = bs.submit_colleague_referral(
            name="Jamie Colleague",
            email="jamie@example.com",
            phone="+15551212",
            non_family_attested=True,
        )
    assert snap["ok"] is True
    assert pushed.get("email") == "jamie@example.com"
    assert pushed.get("phone") == "+15551212"
    assert len(snap["current_cycle"]["colleague_referrals"]) == 1


def test_snapshot_credits_when_ghl_marks_purchased(tmp_path, monkeypatch):
    monkeypatch.setenv("CENTURION_HOME", str(tmp_path / ".centurion"))
    with patch("centurion_cli.beneficiary_cloud.push_colleague_referral"):
        bs.set_family_beneficiary("Alex")
        snap = bs.submit_colleague_referral(
            name="Jamie Colleague",
            email="jamie@example.com",
            phone="",
            non_family_attested=True,
        )
    rid = snap["current_cycle"]["colleague_referrals"][0]["id"]

    with patch(
        "centurion_cli.beneficiary_cloud.fetch_successful_referral_ids",
        return_value=[rid],
    ):
        out = bs.get_beneficiary_snapshot()

    refs = out["current_cycle"]["colleague_referrals"]
    assert refs[0]["status"] == "successful"
    assert refs[0].get("credited_from") == "ghl"
    assert out["current_cycle"]["successful_colleague_count"] == 1


def test_push_builds_ghl_payload(monkeypatch):
    monkeypatch.setenv("GHL_API_KEY", "test-key")
    monkeypatch.setenv("GHL_LOCATION_ID", "loc-1")
    captured = {}

    def fake_request(method, path, body=None, timeout=12.0):
        captured["method"] = method
        captured["path"] = path
        captured["body"] = body
        return {"contact": {"id": "c1"}}

    with patch("centurion_cli.beneficiary_cloud._request", fake_request), patch(
        "centurion_cli.beneficiary_cloud._install_id", return_value="brain_abc"
    ):
        from centurion_cli.beneficiary_cloud import push_colleague_referral

        push_colleague_referral(
            {
                "id": "ref-1",
                "name": "Jamie Colleague",
                "email": "jamie@example.com",
                "phone": "555",
            }
        )
    assert captured["method"] == "POST"
    assert captured["path"] == "/contacts/upsert"
    assert captured["body"]["email"] == "jamie@example.com"
    assert "centurion-referral-pending" in captured["body"]["tags"]
