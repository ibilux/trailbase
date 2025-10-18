// To parse this JSON data, do
//
//     final article = articleFromJson(jsonString);

import 'dart:convert';

Article articleFromJson(String str) => Article.fromJson(json.decode(str));

String articleToJson(Article data) => json.encode(data.toJson());

class Article {
  String author;
  String body;
  int created;
  String id;
  FileUpload? image;
  String intro;
  String tag;
  String title;
  String username;

  Article({
    required this.author,
    required this.body,
    required this.created,
    required this.id,
    this.image,
    required this.intro,
    required this.tag,
    required this.title,
    required this.username,
  });

  factory Article.fromJson(Map<String, dynamic> json) => Article(
        author: json["author"],
        body: json["body"],
        created: json["created"],
        id: json["id"],
        image:
            json["image"] == null ? null : FileUpload.fromJson(json["image"]),
        intro: json["intro"],
        tag: json["tag"],
        title: json["title"],
        username: json["username"],
      );

  Map<String, dynamic> toJson() => {
        "author": author,
        "body": body,
        "created": created,
        "id": id,
        "image": image?.toJson(),
        "intro": intro,
        "tag": tag,
        "title": title,
        "username": username,
      };
}

class FileUpload {
  ///The file's user-provided content type.
  String? contentType;

  ///A unique filename derived from original. Helps to address content caching issues with
  ///proxies, CDNs, ... .
  String filename;

  ///The file's text-encoded UUID from which the objectstore path is derived.
  String? id;

  ///The file's inferred mime type. Not user provided.
  String? mimeType;

  ///The file's original file name.
  String? originalFilename;

  FileUpload({
    this.contentType,
    required this.filename,
    this.id,
    this.mimeType,
    this.originalFilename,
  });

  factory FileUpload.fromJson(Map<String, dynamic> json) => FileUpload(
        contentType: json["content_type"],
        filename: json["filename"],
        id: json["id"],
        mimeType: json["mime_type"],
        originalFilename: json["original_filename"],
      );

  Map<String, dynamic> toJson() => {
        "content_type": contentType,
        "filename": filename,
        "id": id,
        "mime_type": mimeType,
        "original_filename": originalFilename,
      };
}
