import typing
from typing import List, Dict, Any, Protocol

from . import Client, JSON_OBJECT

class CreateOperation(typing.TypedDict):
    ApiName: str
    Record: JSON_OBJECT

class UpdateOperation(typing.TypedDict):
    ApiName: str
    Id: str
    Record: JSON_OBJECT

class DeleteOperation(typing.TypedDict):
    ApiName: str
    RecordId: str

class Operation(typing.TypedDict, total=False):
    Create: CreateOperation
    Update: UpdateOperation
    Delete: DeleteOperation

class TransactionRequest(typing.TypedDict):
    Operations: List[Operation]

class TransactionResponse(typing.TypedDict):
    Ids: List[str]


class ITransactionBatch(Protocol):
    def api(self, api_name: str) -> "IApiBatch":
        ...

    def send(self) -> List[str]:
        ...


class IApiBatch(Protocol):
    def create(self, record: JSON_OBJECT) -> ITransactionBatch:
        ...

    def update(self, record_id: str, record: JSON_OBJECT) -> ITransactionBatch:
        ...

    def delete(self, record_id: str) -> ITransactionBatch:
        ...


class TransactionBatch:
    _client: Client
    _operations: List[Operation]

    def __init__(self, client: Client) -> None:
        self._client = client
        self._operations = []

    def api(self, api_name: str) -> "ApiBatch":
        return ApiBatch(self, api_name)

    def send(self) -> List[str]:
        request: TransactionRequest = {"Operations": self._operations}
        response = self._client.fetch(
            "/api/transactions/v1/execute",
            method="POST",
            data=request,
        )
        if response.status_code != 200:
             raise Exception(f"Transaction failed with status code {response.status_code}: {response.text}")

        result: TransactionResponse = response.json()
        return result.get("Ids", [])


    def _add_operation(self, operation: Operation) -> None:
        self._operations.append(operation)


class ApiBatch:
    _batch: TransactionBatch
    _api_name: str

    def __init__(self, batch: TransactionBatch, api_name: str) -> None:
        self._batch = batch
        self._api_name = api_name

    def create(self, record: JSON_OBJECT) -> ITransactionBatch:
        operation: Operation = {"Create": {"ApiName": self._api_name, "Record": record}}
        self._batch._add_operation(operation)
        return self._batch

    def update(self, record_id: str, record: JSON_OBJECT) -> ITransactionBatch:
        operation: Operation = {"Update": {"ApiName": self._api_name, "Id": record_id, "Record": record}}
        self._batch._add_operation(operation)
        return self._batch

    def delete(self, record_id: str) -> ITransactionBatch:
        operation: Operation = {"Delete": {"ApiName": self._api_name, "RecordId": record_id}}
        self._batch._add_operation(operation)
        return self._batch