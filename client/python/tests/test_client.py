from trailbase import Client, CompareOp, Filter, RecordId, JSON, JSON_OBJECT

import httpx
import logging
import os
import pytest
import subprocess

from time import time, sleep
from typing import List

logging.basicConfig(level=logging.DEBUG)

port = 4007
address = f"127.0.0.1:{port}"
site = f"http://{address}"


class TrailBaseFixture:
    process: None | subprocess.Popen[bytes]

    def __init__(self) -> None:
        cwd = os.getcwd()
        traildepot = "../testfixture" if cwd.endswith("python") else "client/testfixture"

        logger.info("Building TrailBase")
        build = subprocess.run(["cargo", "build"])
        assert build.returncode == 0

        logger.info("Starting TrailBase")
        self.process = subprocess.Popen(
            [
                "cargo",
                "run",
                "--",
                "--data-dir",
                traildepot,
                "run",
                "-a",
                address,
                "--js-runtime-threads",
                "1",
            ]
        )

        client = httpx.Client()
        for _ in range(100):
            try:
                response = client.get(f"http://{address}/api/healthcheck")
                if response.status_code == 200:
                    return
            except:
                pass

            sleep(0.5)

        logger.error("Failed ot start TrailBase")

    def isUp(self) -> bool:
        p = self.process
        return p != None and p.returncode == None

    def shutdown(self) -> None:
        p = self.process
        if p != None:
            p.send_signal(9)
            p.wait()
            assert isinstance(p.returncode, int)


@pytest.fixture(scope="session")
def trailbase():
    fixture = TrailBaseFixture()
    yield fixture
    fixture.shutdown()


def connect() -> Client:
    client = Client(site, tokens=None)
    client.login("admin@localhost", "secret")
    return client


def test_client_login(trailbase: TrailBaseFixture):
    assert trailbase.isUp()

    client = connect()
    assert client.site() == site

    tokens = client.tokens()
    assert tokens != None and tokens.valid()

    user = client.user()
    assert user != None and user.id != ""
    assert user != None and user.email == "admin@localhost"

    client.logout()
    assert client.tokens() == None


def test_records(trailbase: TrailBaseFixture):
    assert trailbase.isUp()

    client = connect()
    api = client.records("simple_strict_table")

    now = int(time())
    messages = [
        f"python client test 0: =?&{now}",
        f"python client test 1: =?&{now}",
    ]
    ids: List[RecordId] = []
    for msg in messages:
        ids.append(api.create({"text_not_null": msg}))

    if True:
        bulk_ids = api.create_bulk(
            [
                {"text_not_null": "python bulk test 0"},
                {"text_not_null": "python bulk test 1"},
            ]
        )
        assert len(bulk_ids) == 2

    if True:
        response = api.list(
            filters=[Filter("text_not_null", messages[0])],
        )
        records = response.records
        assert len(records) == 1
        assert records[0]["text_not_null"] == messages[0]

    if True:
        recordsAsc = api.list(
            order=["+text_not_null"],
            filters=[Filter(column="text_not_null", value=f"% =?&{now}", op=CompareOp.LIKE)],
            count=True,
        )

        assert recordsAsc.total_count == 2
        assert [el["text_not_null"] for el in recordsAsc.records] == messages

        recordsDesc = api.list(
            order=["-text_not_null"],
            filters=[Filter(column="text_not_null", value=f"%{now}", op=CompareOp.LIKE)],
        )

        assert [el["text_not_null"] for el in recordsDesc.records] == list(reversed(messages))

    if True:
        record = api.read(ids[0])
        assert record["text_not_null"] == messages[0]

        record = api.read(ids[1])
        assert record["text_not_null"] == messages[1]

    if True:
        updatedMessage = f"python client updated test 0: {now}"
        api.update(ids[0], {"text_not_null": updatedMessage})
        record = api.read(ids[0])
        assert record["text_not_null"] == updatedMessage

    if True:
        api.delete(ids[0])

        with pytest.raises(Exception):
            api.read(ids[0])


def test_expand_foreign_records(trailbase: TrailBaseFixture):
    assert trailbase.isUp()

    client = connect()
    api = client.records("comment")

    def get_nested(obj: JSON_OBJECT, k0: str, k1: str) -> JSON | None:
        x = obj[k0]
        assert type(x) is dict
        return x.get(k1)

    if True:
        comment = api.read(1)

        assert comment.get("id") == 1
        assert comment.get("body") == "first comment"
        assert get_nested(comment, "author", "id") != ""
        assert get_nested(comment, "author", "data") == None
        assert get_nested(comment, "post", "id") != ""

    if True:
        comment = api.read(1, expand=["post"])

        assert comment.get("id") == 1
        assert comment.get("body") == "first comment"
        assert get_nested(comment, "author", "data") == None

        x = get_nested(comment, "post", "data")
        assert type(x) is dict
        assert x.get("title") == "first post"

    if True:
        comments = api.list(
            expand=["author", "post"],
            order=["-id"],
            limit=1,
            count=True,
        )

        assert comments.total_count == 2
        assert len(comments.records) == 1

        comment = comments.records[0]

        assert comment.get("id") == 2
        assert comment.get("body") == "second comment"

        x = get_nested(comment, "post", "data")
        assert type(x) is dict
        assert x.get("title") == "first post"

        y = get_nested(comment, "author", "data")
        assert type(y) is dict
        assert y.get("name") == "SecondUser"

    if True:
        comments = api.list(
            expand=["author", "post"],
            order=["-id"],
            limit=2,
        )

        assert len(comments.records) == 2

        first = comments.records[0]
        assert first.get("id") == 2
        second = comments.records[1]
        assert second.get("id") == 1

        offset_comments = api.list(
            expand=["author", "post"],
            order=["-id"],
            limit=1,
            offset=1,
        )

        assert len(offset_comments.records) == 1
        assert second == offset_comments.records[0]


def test_subscriptions(trailbase: TrailBaseFixture):
    assert trailbase.isUp()

    client = connect()
    api = client.records("simple_strict_table")

    table_subscription = api.subscribe("*")

    now = int(time())
    create_message = f"python client test 0: =?&{now}"
    api.create({"text_not_null": create_message})

    events: List[dict[str, JSON]] = []
    for ev in table_subscription:
        events.append(ev)
        break

    table_subscription.close()

    assert "Insert" in events[0]


def test_transaction_create_operation(trailbase: TrailBaseFixture):
    assert trailbase.isUp()
    
    client = connect()
    batch = client.transaction()
    
    now = int(time())
    record = {"text_not_null": f"transaction test create: {now}"}
    batch.api("simple_strict_table").create(record)
    
    operation = batch._operations[0]
    serialized = operation.to_json()
    
    assert "Create" in serialized
    assert serialized["Create"]["apiName"] == "simple_strict_table"
    assert serialized["Create"]["value"] == record


def test_transaction_update_operation(trailbase: TrailBaseFixture):
    assert trailbase.isUp()
    
    client = connect()
    batch = client.transaction()
    
    now = int(time())
    record = {"text_not_null": f"transaction test update: {now}"}
    batch.api("simple_strict_table").update("record1", record)
    
    operation = batch._operations[0]
    serialized = operation.to_json()
    
    assert "Update" in serialized
    assert serialized["Update"]["apiName"] == "simple_strict_table"
    assert serialized["Update"]["id"] == "record1"
    assert serialized["Update"]["value"] == record


def test_transaction_delete_operation(trailbase: TrailBaseFixture):
    assert trailbase.isUp()
    
    client = connect()
    batch = client.transaction()
    
    batch.api("simple_strict_table").delete("record1")
    
    operation = batch._operations[0]
    serialized = operation.to_json()
    
    assert "Delete" in serialized
    assert serialized["Delete"]["apiName"] == "simple_strict_table"
    assert serialized["Delete"]["id"] == "record1"


def test_transaction_multiple_operations(trailbase: TrailBaseFixture):
    assert trailbase.isUp()
    
    client = connect()
    batch = client.transaction()
    
    now = int(time())
    batch.api("simple_strict_table").create({"text_not_null": f"transaction test first: {now}"})
    batch.api("simple_strict_table").update("record1", {"text_not_null": f"transaction test second: {now}"})
    batch.api("simple_strict_table").delete("record2")
    
    # Verify operation order is preserved
    assert len(batch._operations) == 3
    assert "Create" in batch._operations[0].to_json()
    assert "Update" in batch._operations[1].to_json()
    assert "Delete" in batch._operations[2].to_json()


def test_transaction_execute(trailbase: TrailBaseFixture):
    assert trailbase.isUp()
    
    client = connect()
    batch = client.transaction()
    api = client.records("simple_strict_table")
    
    # Create a record through transaction
    now = int(time())
    record = {"text_not_null": f"transaction test execute: {now}"}
    batch.api("simple_strict_table").create(record)
    
    # Execute the transaction and get the IDs
    ids = batch.send()
    assert len(ids) == 1
    
    # Verify the record was created
    created_record = api.read(ids[0])
    assert created_record["text_not_null"] == record["text_not_null"]
    
    # Update and delete in the same transaction
    batch = client.transaction()
    update_record = {"text_not_null": f"transaction test updated: {now}"}
    batch.api("simple_strict_table").update(ids[0], update_record)
    batch.api("simple_strict_table").delete(ids[0])
    
    # Execute the transaction
    batch.send()
    
    # Verify the record was deleted
    with pytest.raises(Exception):
        api.read(ids[0])


logger = logging.getLogger(__name__)
