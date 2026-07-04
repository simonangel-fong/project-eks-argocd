from datetime import datetime, timedelta, timezone


def _create_poll(client, title="cats or dogs", options=("cats", "dogs"), closes_at=None):
    body = {"title": title, "options": list(options)}
    if closes_at is not None:
        body["closes_at"] = closes_at
    r = client.post("/polls", json=body)
    assert r.status_code == 201, r.text
    return r.json()


def test_healthz(client):
    r = client.get("/healthz")
    assert r.status_code == 200
    assert r.json() == {"status": "ok"}


def test_readyz(client):
    r = client.get("/readyz")
    assert r.status_code == 200
    assert r.json() == {"status": "ready"}


def test_create_poll_201(client):
    poll = _create_poll(client)
    assert poll["id"] > 0
    assert poll["title"] == "cats or dogs"
    assert [o["label"] for o in poll["options"]] == ["cats", "dogs"]
    assert poll["created_at"]
    assert poll["closes_at"] is None


def test_create_poll_empty_title_422(client):
    r = client.post("/polls", json={"title": "  ", "options": ["a", "b"]})
    assert r.status_code == 422


def test_create_poll_too_few_options_422(client):
    r = client.post("/polls", json={"title": "x", "options": ["only"]})
    assert r.status_code == 422


def test_create_poll_duplicate_labels_422(client):
    r = client.post("/polls", json={"title": "x", "options": ["a", "a"]})
    assert r.status_code == 422


def test_create_poll_past_closes_at_422(client):
    past = (datetime.now(timezone.utc) - timedelta(days=1)).isoformat()
    r = client.post("/polls", json={"title": "x", "options": ["a", "b"], "closes_at": past})
    assert r.status_code == 422


def test_list_polls(client):
    _create_poll(client, title="p1")
    _create_poll(client, title="p2")
    r = client.get("/polls")
    assert r.status_code == 200
    titles = [p["title"] for p in r.json()]
    assert titles == ["p1", "p2"]


def test_get_poll_200(client):
    poll = _create_poll(client)
    r = client.get(f"/polls/{poll['id']}")
    assert r.status_code == 200
    assert r.json()["id"] == poll["id"]
    assert len(r.json()["options"]) == 2


def test_get_poll_404(client):
    r = client.get("/polls/999999")
    assert r.status_code == 404


def test_vote_201(client):
    poll = _create_poll(client)
    opt = poll["options"][0]["id"]
    r = client.post(
        f"/polls/{poll['id']}/vote",
        json={"option_id": opt},
        headers={"X-User-Id": "alice"},
    )
    assert r.status_code == 201, r.text
    body = r.json()
    assert body["poll_id"] == poll["id"]
    assert body["option_id"] == opt
    assert body["voter_id"] == "alice"


def test_vote_missing_user_id_400(client):
    poll = _create_poll(client)
    r = client.post(
        f"/polls/{poll['id']}/vote",
        json={"option_id": poll["options"][0]["id"]},
    )
    assert r.status_code == 400


def test_vote_poll_not_found_404(client):
    r = client.post(
        "/polls/999999/vote",
        json={"option_id": 1},
        headers={"X-User-Id": "alice"},
    )
    assert r.status_code == 404


def test_vote_option_not_found_404(client):
    poll = _create_poll(client)
    r = client.post(
        f"/polls/{poll['id']}/vote",
        json={"option_id": 999999},
        headers={"X-User-Id": "alice"},
    )
    assert r.status_code == 404


def test_vote_duplicate_409(client):
    poll = _create_poll(client)
    opt = poll["options"][0]["id"]
    headers = {"X-User-Id": "alice"}
    r1 = client.post(f"/polls/{poll['id']}/vote", json={"option_id": opt}, headers=headers)
    assert r1.status_code == 201
    r2 = client.post(f"/polls/{poll['id']}/vote", json={"option_id": opt}, headers=headers)
    assert r2.status_code == 409


def test_results(client):
    poll = _create_poll(client)
    opt_a, opt_b = poll["options"][0]["id"], poll["options"][1]["id"]
    for user, opt in [("alice", opt_a), ("bob", opt_a), ("carol", opt_b)]:
        client.post(
            f"/polls/{poll['id']}/vote",
            json={"option_id": opt},
            headers={"X-User-Id": user},
        )
    r = client.get(f"/polls/{poll['id']}/results")
    assert r.status_code == 200
    body = r.json()
    assert body["poll_id"] == poll["id"]
    assert body["total_votes"] == 3
    tallies = {t["option_id"]: t["votes"] for t in body["tallies"]}
    assert tallies == {opt_a: 2, opt_b: 1}


def test_results_404(client):
    r = client.get("/polls/999999/results")
    assert r.status_code == 404


def test_two_voters_one_each_and_duplicate_rejected(client):
    """Matches the 'Done when' criterion in docs/02-app.md."""
    poll = _create_poll(client)
    opt = poll["options"][0]["id"]

    r1 = client.post(
        f"/polls/{poll['id']}/vote",
        json={"option_id": opt},
        headers={"X-User-Id": "user-1"},
    )
    r2 = client.post(
        f"/polls/{poll['id']}/vote",
        json={"option_id": opt},
        headers={"X-User-Id": "user-2"},
    )
    assert r1.status_code == 201
    assert r2.status_code == 201

    dup = client.post(
        f"/polls/{poll['id']}/vote",
        json={"option_id": opt},
        headers={"X-User-Id": "user-1"},
    )
    assert dup.status_code == 409

    resp = client.get(f"/polls/{poll['id']}/results")
    assert resp.status_code == 200, resp.text
    results = resp.json()
    assert results["total_votes"] == 2
