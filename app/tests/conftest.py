import os

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine, event, text
from sqlalchemy.orm import sessionmaker

TEST_DATABASE_URL = os.environ.get(
    "TEST_DATABASE_URL",
    "postgresql+psycopg://voting:voting@localhost:5432/voting_test",
)


@pytest.fixture(scope="session")
def engine():
    eng = create_engine(TEST_DATABASE_URL, pool_pre_ping=True)
    with eng.connect() as conn:
        conn.execute(text("SELECT 1"))
    yield eng
    eng.dispose()


@pytest.fixture(autouse=True)
def _truncate(engine):
    with engine.begin() as conn:
        conn.execute(text("TRUNCATE votes, options, polls RESTART IDENTITY CASCADE"))
    yield


@pytest.fixture()
def db_session(engine):
    connection = engine.connect()
    trans = connection.begin()
    Session = sessionmaker(bind=connection, autoflush=False, autocommit=False)
    session = Session()

    # begin a SAVEPOINT so endpoint commits/rollbacks operate on the savepoint,
    # not the outer trans. re-open it after each release so subsequent endpoint
    # calls in the same test see a fresh savepoint.
    nested = connection.begin_nested()

    @event.listens_for(session, "after_transaction_end")
    def _restart_savepoint(sess, transaction):
        nonlocal nested
        if transaction.nested and not transaction._parent.nested:
            nested = connection.begin_nested()

    try:
        yield session
    finally:
        session.close()
        if trans.is_active:
            trans.rollback()
        connection.close()


@pytest.fixture()
def client(db_session, monkeypatch):
    import voting.main as main_mod
    from voting.db import get_db
    from voting.main import app

    # lifespan ping targets prod DB via settings; redirect to test engine
    monkeypatch.setattr(main_mod, "ping", lambda: db_session.execute(text("SELECT 1")))

    def _override():
        try:
            yield db_session
        finally:
            pass

    app.dependency_overrides[get_db] = _override
    with TestClient(app) as c:
        yield c
    app.dependency_overrides.clear()
