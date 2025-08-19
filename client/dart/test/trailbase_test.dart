import 'dart:io';
import 'dart:convert';

import 'package:trailbase/trailbase.dart';
import 'package:test/test.dart';
import 'package:dio/dio.dart';

const port = 4006;
const address = '127.0.0.1:${port}';

class SimpleStrict {
  final String id;

  final String? textNull;
  final String textDefault;
  final String textNotNull;

  SimpleStrict({
    required this.id,
    this.textNull,
    this.textDefault = '',
    required this.textNotNull,
  });

  SimpleStrict.fromJson(Map<String, dynamic> json)
      : id = json['id'],
        textNull = json['text_null'],
        textDefault = json['text_default'],
        textNotNull = json['text_not_null'];

  @override
  bool operator ==(Object other) {
    return other is SimpleStrict &&
        id == other.id &&
        textNull == other.textNull &&
        textDefault == other.textDefault &&
        textNotNull == other.textNotNull;
  }

  @override
  int get hashCode {
    return Object.hash(id, textNull, textDefault, textNotNull);
  }

  @override
  String toString() =>
      'SimpleStrict(id: ${id}, textNull: ${textNull}, textDefault: ${textDefault}, textNotNull: ${textNotNull})';
}

class Author {
  final String id;
  final String user;
  final String name;

  Author.fromJson(Map<String, dynamic> json)
      : id = json['id'],
        user = json['user'],
        name = json['name'];

  @override
  bool operator ==(Object rhs) {
    return rhs is Author &&
        rhs.id == id &&
        rhs.user == user &&
        rhs.name == name;
  }

  @override
  int get hashCode {
    return Object.hash(id, user, name);
  }

  @override
  String toString() {
    return 'Author(${id}, ${user}, ${name})';
  }
}

class Post {
  final String id;
  final String author;
  final String title;
  final String body;

  Post.fromJson(Map<String, dynamic> json)
      : id = json['id'],
        author = json['author'],
        title = json['title'],
        body = json['body'];

  @override
  bool operator ==(Object rhs) {
    return rhs is Post &&
        rhs.id == id &&
        rhs.author == author &&
        rhs.title == title &&
        rhs.body == body;
  }

  @override
  int get hashCode {
    return Object.hash(id, author, title, body);
  }
}

class Comment {
  final int id;
  final String body;
  final (String, Post?) post;
  final (String, Author?) author;

  Comment({
    required this.id,
    required this.body,
    required String postId,
    Map<String, dynamic>? post,
    required String authorId,
    Map<String, dynamic>? authorProfile,
  })  : post = (postId, post != null ? Post.fromJson(post) : null),
        author = (
          authorId,
          authorProfile != null ? Author.fromJson(authorProfile) : null
        );

  Comment.fromJson(Map<String, dynamic> json)
      : this(
          id: json['id'],
          body: json['body'],
          postId: json['post']['id'],
          post: json['post']['data'],
          authorId: json['author']['id'],
          authorProfile: json['author']['data'],
        );

  @override
  bool operator ==(Object rhs) {
    return rhs is Comment &&
        rhs.id == id &&
        rhs.body == body &&
        rhs.post == post &&
        rhs.author == author;
  }

  @override
  int get hashCode {
    return Object.hash(id, body, post, author);
  }

  @override
  String toString() => 'Comment(${id}, ${body}, ${post}, ${author})';
}

Future<Client> connect() async {
  final client = Client('http://${address}');
  await client.login('admin@localhost', 'secret');
  return client;
}

Future<Process> initTrailBase() async {
  final result = await Process.run('cargo', ['build'],
      stdoutEncoding: utf8, stderrEncoding: utf8);
  if (result.exitCode > 0) {
    throw Exception(
        'Cargo build failed.\n\nstdout: ${result.stdout}\n\nstderr: ${result.stderr}\n');
  }

  // Relative to CWD.
  const depotPath = '../testfixture';

  final process = await Process.start('cargo', [
    'run',
    '--',
    '--data-dir=${depotPath}',
    'run',
    '--address=${address}',
    // We want at least some parallelism to experience isolate-local state.
    '--js-runtime-threads=2',
  ]);

  final dio = Dio();
  for (int i = 0; i < 100; ++i) {
    try {
      final response = await dio
          .fetch(RequestOptions(path: 'http://${address}/api/healthcheck'));
      if (response.statusCode == 200) {
        return process;
      }
    } catch (err) {
      print('Trying to connect to TrailBase');
    }

    if (await process.exitCode
            .timeout(Duration(milliseconds: 500), onTimeout: () => -1) >=
        0) {
      break;
    }
  }

  process.kill(ProcessSignal.sigkill);
  final exitCode = await process.exitCode;

  await process.stderr.forEach(stdout.add);
  await process.stdout.forEach(stdout.add);

  throw Exception('Cargo run failed: ${exitCode}.');
}

Future<void> main() async {
  if (!Directory.current.path.endsWith('dart')) {
    throw Exception('Unexpected working directory');
  }

  final process = await initTrailBase();

  tearDownAll(() async {
    process.kill(ProcessSignal.sigkill);
    final _ = await process.exitCode;

    // await process.stderr.forEach(stdout.add);
    // await process.stdout.forEach(stdout.add);
  });

  group('client tests', () {
    test('auth', () async {
      final client = await connect();

      final oldTokens = client.tokens();
      expect(oldTokens, isNotNull);
      expect(oldTokens!.valid, isTrue);

      final user = client.user()!;
      expect(user.id, isNot(equals('')));
      expect(user.email, equals('admin@localhost'));

      await client.logout();
      expect(client.tokens(), isNull);

      // We need to wait a little to push the expiry time in seconds to avoid just getting the same token minted again.
      await Future.delayed(Duration(milliseconds: 1500));

      final newTokens = await client.login('admin@localhost', 'secret');
      expect(newTokens, isNotNull);
      expect(newTokens.valid, isTrue);

      expect(newTokens, isNot(equals(oldTokens)));

      await client.refreshAuthToken();
      expect(newTokens, equals(client.tokens()));
    });

    test('records', () async {
      final client = await connect();
      final api = client.records('simple_strict_table');

      final int now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final messages = [
        'dart client test 0: =?&${now}',
        'dart client test 1: =?&${now}',
      ];
      final ids = [];
      for (final msg in messages) {
        ids.add(await api.create({'text_not_null': msg}));
      }

      {
        // Bulk
        final ids = await api.createBulk([
          {'text_not_null': 'dart 1st bulk'},
          {'text_not_null': 'dart 2nd bulk'},
        ]);
        expect(ids.length, 2);
      }

      {
        final response = await api.list(
          filters: [Filter(column: 'text_not_null', value: messages[0])],
        );
        expect(response.records.length, 1);
        expect(response.records[0]['text_not_null'], messages[0]);
      }

      {
        final recordsAsc = (await api.list(
          order: ['+text_not_null'],
          filters: [
            Filter(
                column: 'text_not_null',
                op: CompareOp.like,
                value: '% =?&${now}')
          ],
        ))
            .records;
        expect(recordsAsc.map((el) => el['text_not_null']),
            orderedEquals(messages));

        final recordsDesc = (await api.list(
          order: ['-text_not_null'],
          filters: [
            Filter(
                column: 'text_not_null', op: CompareOp.like, value: '%${now}')
          ],
        ))
            .records;
        expect(recordsDesc.map((el) => el['text_not_null']).toList().reversed,
            orderedEquals(messages));
      }

      {
        final response = (await api.list(
          pagination: Pagination(limit: 1),
          order: ['-text_not_null'],
          filters: [
            Filter(
                column: 'text_not_null', op: CompareOp.like, value: '%${now}')
          ],
          count: true,
        ));

        expect(response.totalCount ?? -1, 2);
        // Ensure there's no extra field, i.e the count doesn't get serialized.
        expect(response.records[0].keys.length, 13);
      }

      final record = SimpleStrict.fromJson(await api.read(ids[0]));

      expect(ids[0] == record.id, isTrue);
      // Note: the .id() is needed otherwise we call String's operator==. It's not ideal
      // but we didn't come up with a better option.
      expect(record.id.id() == ids[0], isTrue);
      expect(RecordId.uuid(record.id) == ids[0], isTrue);

      expect(record.textNotNull, messages[0]);

      final updatedMessage = 'dart client updated test 0: ${now}';
      await api.update(ids[0], {'text_not_null': updatedMessage});
      final updatedRecord = SimpleStrict.fromJson(await api.read(ids[0]));
      expect(updatedRecord.textNotNull, updatedMessage);

      await api.delete(ids[0]);
      expect(() async => await api.read(ids[0]), throwsException);
    });

    test('expand foreign records', () async {
      final client = await connect();
      final api = client.records('comment');

      {
        final comment = Comment.fromJson(await api.read(RecordId.integer(1)));

        expect(comment.id, equals(1));
        expect(comment.body, equals('first comment'));
        expect(comment.author.$2, isNull);
        expect(comment.post.$2?.title, isNull);
      }

      {
        final comment = Comment.fromJson(await api.read(
          RecordId.integer(1),
          expand: ['post'],
        ));

        expect(comment.id, equals(1));
        expect(comment.body, equals('first comment'));
        expect(comment.author.$2, isNull);
        expect(comment.post.$2?.title, equals('first post'));
      }

      {
        final response = await api.list(
          expand: ['author', 'post'],
          order: ['-id'],
          pagination: Pagination(limit: 2),
        );

        expect(response.records.length, equals(2));
        final first = Comment.fromJson(response.records[0]);
        expect(first.id, equals(2));
        expect(first.body, equals('second comment'));
        expect(first.author.$2?.name, equals('SecondUser'));
        expect(first.post.$2?.title, equals('first post'));

        final second = Comment.fromJson(response.records[1]);

        final offsetResponse = await api.list(
          expand: ['author', 'post'],
          order: ['-id'],
          pagination: Pagination(limit: 1, offset: 1),
        );

        expect(offsetResponse.records.length, equals(1));
        expect(Comment.fromJson(offsetResponse.records[0]), equals(second));
      }
    });

    test('realtime', () async {
      final client = await connect();
      final api = client.records('simple_strict_table');

      final tableEvents = await api.subscribeAll();

      final int now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final createMessage = 'dart client realtime test 0: =?&${now}';
      final id = await api.create({'text_not_null': createMessage});

      final events = await api.subscribe(id);

      final updatedMessage = 'dart client updated realtime test 0: ${now}';
      await api.update(id, {'text_not_null': updatedMessage});
      await api.delete(id);

      final eventList =
          await events.timeout(Duration(seconds: 10), onTimeout: (sink) {
        print('Stream timeout');
        sink.close();
      }).toList();

      expect(eventList.length, equals(2));
      expect(eventList[0].runtimeType, equals(UpdateEvent));
      expect(
          SimpleStrict.fromJson(eventList[0].value()!),
          SimpleStrict(
            id: id.toString(),
            textNotNull: updatedMessage,
          ));

      expect(eventList[1].runtimeType, equals(DeleteEvent));
      expect(
          SimpleStrict.fromJson(eventList[1].value()!),
          SimpleStrict(
            id: id.toString(),
            textNotNull: updatedMessage,
          ));

      final tableEventList =
          await tableEvents.timeout(Duration(seconds: 10), onTimeout: (sink) {
        print('Stream timeout');
        sink.close();
      }).toList();
      expect(tableEventList.length, equals(3));

      expect(tableEventList[0].runtimeType, equals(InsertEvent));
      expect(
          SimpleStrict.fromJson(tableEventList[0].value()!),
          SimpleStrict(
            id: id.toString(),
            textNotNull: createMessage,
          ));
    });

    test('transaction create operation', () async {
      final client = await connect();
      final batch = client.transaction();
      final api = client.records('simple_strict_table');

      final int now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final record = {'text_not_null': 'dart transaction test create: ${now}'};
      batch.api('simple_strict_table').create(record);

      final operation = batch._operations[0];
      final json = operation.toJson();

      expect(json.containsKey('Create'), isTrue);
      expect(json['Create']['apiName'], equals('simple_strict_table'));
      expect(json['Create']['value'], equals(record));

      // Test actual creation
      final ids = await batch.send();
      expect(ids.length, equals(1));

      final createdRecord = await api.read(ids[0]);
      expect(createdRecord['text_not_null'], equals(record['text_not_null']));
    });

    test('transaction update operation', () async {
      final client = await connect();
      final batch = client.transaction();
      final api = client.records('simple_strict_table');

      // First create a record to update
      final int now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final createRecord = {'text_not_null': 'dart transaction test update original: ${now}'};
      final id = await api.create(createRecord);

      // Prepare update operation
      final updateRecord = {'text_not_null': 'dart transaction test update modified: ${now}'};
      batch.api('simple_strict_table').update(id, updateRecord);

      final operation = batch._operations[0];
      final json = operation.toJson();

      expect(json.containsKey('Update'), isTrue);
      expect(json['Update']['apiName'], equals('simple_strict_table'));
      expect(json['Update']['id'], equals(id));
      expect(json['Update']['value'], equals(updateRecord));

      // Test actual update
      await batch.send();
      final updatedRecord = await api.read(id);
      expect(updatedRecord['text_not_null'], equals(updateRecord['text_not_null']));
    });

    test('transaction delete operation', () async {
      final client = await connect();
      final batch = client.transaction();
      final api = client.records('simple_strict_table');

      // First create a record to delete
      final int now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final createRecord = {'text_not_null': 'dart transaction test delete: ${now}'};
      final id = await api.create(createRecord);

      batch.api('simple_strict_table').delete(id);

      final operation = batch._operations[0];
      final json = operation.toJson();

      expect(json.containsKey('Delete'), isTrue);
      expect(json['Delete']['apiName'], equals('simple_strict_table'));
      expect(json['Delete']['id'], equals(id));

      // Test actual deletion
      await batch.send();
      expect(() async => await api.read(id), throwsException);
    });

    test('transaction multiple operations', () async {
      final client = await connect();
      final batch = client.transaction();
      final api = client.records('simple_strict_table');

      final int now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      
      // Create operation
      final createRecord = {'text_not_null': 'dart transaction test multi create: ${now}'};
      batch.api('simple_strict_table').create(createRecord);
      
      // Update operation (will be executed after create)
      batch.api('simple_strict_table').update('record1', {'text_not_null': 'dart transaction test multi update: ${now}'});
      
      // Delete operation
      batch.api('simple_strict_table').delete('record2');

      // Verify operation order
      expect(batch._operations.length, equals(3));
      expect(batch._operations[0].toJson().containsKey('Create'), isTrue);
      expect(batch._operations[1].toJson().containsKey('Update'), isTrue);
      expect(batch._operations[2].toJson().containsKey('Delete'), isTrue);

      // Test execution order with real operations
      final ids = await batch.send();
      expect(ids.length, equals(1)); // Only create operation returns an ID

      // Verify the record was created
      final createdRecord = await api.read(ids[0]);
      expect(createdRecord['text_not_null'], equals(createRecord['text_not_null']));
    });
  });
}
