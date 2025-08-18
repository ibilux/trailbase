import 'dart:convert';

import 'package:dio/dio.dart' as dio;
import 'package:trailbase/src/client.dart';


class Operation {
  CreateOperation? create;
  UpdateOperation? update;
  DeleteOperation? delete;

  Operation({this.create, this.update, this.delete});

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = {};
    if (create != null) {
      data['Create'] = create!.toJson();
    }
    if (update != null) {
      data['Update'] = update!.toJson();
    }
    if (delete != null) {
      data['Delete'] = delete!.toJson();
    }
    return data;
  }
}

class CreateOperation {
  String apiName;
  Map<String, dynamic> record;

  CreateOperation({required this.apiName, required this.record});

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = {};
    data['api_name'] = apiName;
    data['record'] = record;
    return data;
  }
}

class UpdateOperation {
  String apiName;
  String id;
  Map<String, dynamic> record;

  UpdateOperation({required this.apiName, required this.id, required this.record});

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = {};
    data['api_name'] = apiName;
    data['id'] = id;
    data['record'] = record;
    return data;
  }
}

class DeleteOperation {
  String apiName;
  String recordId;

  DeleteOperation({required this.apiName, required this.recordId});

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = {};
    data['api_name'] = apiName;
    data['record_id'] = recordId;
    return data;
  }
}

class TransactionRequest {
  List<Operation> operations;

  TransactionRequest({required this.operations});

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = {};
    data['operations'] = operations.map((e) => e.toJson()).toList();
    return data;
  }
}

class TransactionResponse {
  List<String> ids;

  TransactionResponse({required this.ids});

  factory TransactionResponse.fromJson(Map<String, dynamic> json) {
    return TransactionResponse(
      ids: (json['ids'] as List).cast<String>(),
    );
  }
}

abstract class ITransactionBatch {
  IApiBatch api(String apiName);
  Future<List<String>> send();
}

abstract class IApiBatch {
  ITransactionBatch create(Map<String, dynamic> record);
  ITransactionBatch update(String recordId, Map<String, dynamic> record);
  ITransactionBatch delete(String recordId);
}

class TransactionBatch implements ITransactionBatch {
  final Client _client;
  final List<Operation> _operations = [];

  TransactionBatch(this._client);

  @override
  IApiBatch api(String apiName) {
    return ApiBatch(this, apiName);
  }

  @override
  Future<List<String>> send() async {
    final request = TransactionRequest(operations: _operations);
    final response = await _client.fetch(
      'api/transactions/v1/execute',
      method: 'POST',
      data: request.toJson(),
    );

    if ((response.statusCode ?? 400) > 200) {
      throw Exception('${response.data} ${response.statusMessage}');
    }

    final result = TransactionResponse.fromJson(response.data);
    return result.ids;
  }

  void addOperation(Operation operation) {
    _operations.add(operation);
  }
}

class ApiBatch implements IApiBatch {
  final TransactionBatch _batch;
  final String _apiName;

  ApiBatch(this._batch, this._apiName);

  @override
  ITransactionBatch create(Map<String, dynamic> record) {
    _batch.addOperation(Operation(
      create: CreateOperation(
        apiName: _apiName,
        record: record,
      ),
    ));
    return _batch;
  }

  @override
  ITransactionBatch update(String recordId, Map<String, dynamic> record) {
    _batch.addOperation(Operation(
      update: UpdateOperation(
        apiName: _apiName,
        id: recordId,
        record: record,
      ),
    ));
    return _batch;
  }

  @override
  ITransactionBatch delete(String recordId) {
    _batch.addOperation(Operation(
      delete: DeleteOperation(
        apiName: _apiName,
        recordId: recordId,
      ),
    ));
    return _batch;
  }
}