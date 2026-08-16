# KOTONOHA — API Specification v0.1

## 1. 基本方針

スマートフォンアプリとConoHa WING上のAPIをHTTPSで接続する。

APIはPHPで実装し、MySQLをデータストアとして利用する。

位置情報はリアルタイム追跡しない。利用者が「地図更新」「言の葉を置く」「言葉を繋ぐ」等の操作を行った時点で必要な現在地を取得してAPIへ送信する。

距離による制約はクライアントだけで判断せず、API側でも必ず検証する。

## 2. 共通ルール

### 認証・識別

ユーザーアカウントは作成しない。

アプリが保持する匿名 `installation_id` をAPIへ送信する。これは利用者には表示しない。

### 位置情報

緯度・経度を十進数で送信する。

API側で対象地点との距離を計算し、操作可否を判断する。

### 文字数

言葉は50文字以内。

### HTTP

本番環境ではHTTPSのみを使用する。

## 3. 地図更新

### GET `/api/kotonoha/nearby`

現在地周辺の言の葉を取得する。

#### Request

Query parameters:

- `latitude`: 現在地の緯度
- `longitude`: 現在地の経度
- `installation_id`: 匿名識別子

#### Server processing

現在地を基準に半径5km以内の公開状態の言の葉を検索する。

レスポンスには地図上でピン表示するために必要な最小限の情報だけを返す。

内容（写真・コメント）は10m以内の閲覧APIで取得するため、ここでは返さない。

#### Response example

```json
{
  "items": [
    {
      "id": 1001,
      "latitude": 35.000001,
      "longitude": 139.000001,
      "created_at": "2026-08-16T12:30:00+09:00"
    }
  ]
}
```

## 4. 言の葉の閲覧

### GET `/api/kotonoha/{id}`

指定された言の葉の内容を取得する。

#### Query parameters

- `latitude`: 現在地の緯度
- `longitude`: 現在地の経度
- `installation_id`: 匿名識別子

#### Server processing

対象言の葉との距離を計算する。

- 10m以内: 内容を返す
- 10mより遠い: 閲覧不可

#### Response example

```json
{
  "id": 1001,
  "latitude": 35.000001,
  "longitude": 139.000001,
  "captured_at": "2026-08-16T12:30:00+09:00",
  "photo_url": "/media/kotonoha/1001.jpg",
  "comment": "今日はここから見る空がきれいだ。",
  "children": [
    {
      "id": 1002,
      "parent_id": 1001,
      "comment": "夕方もきれいでした。",
      "created_at": "2026-08-16T15:10:00+09:00"
    }
  ],
  "can_comment": true
}
```

## 5. 言の葉の新規作成

### POST `/api/kotonoha`

新しい言の葉を置く。

#### Request

`multipart/form-data` を基本とする。

Fields:

- `latitude`: 撮影時の緯度
- `longitude`: 撮影時の経度
- `captured_at`: 撮影日時
- `installation_id`: 匿名識別子
- `comment`: 50文字以内
- `photo`: アプリ内カメラで撮影した画像

#### 必須サーバー検証

1. `installation_id` がblock_listに登録されていないこと。
2. 前回の新規言の葉作成から5分以上経過していること。
3. 座標が妥当な値であること。
4. コメントが50文字以内であること。
5. 画像が許可された画像形式・サイズであること。
6. 撮影時位置と投稿時に取得した現在地が大きく乖離していないこと。

「言の葉を置く」操作では、アプリ側で直前に現在地を再取得して地図を更新する。API側でも受信値を検証する。

#### Response

```json
{
  "id": 1003,
  "status": "created",
  "captured_at": "2026-08-16T16:00:00+09:00"
}
```

## 6. 言葉を繋ぐ

### POST `/api/kotonoha/{id}/comments`

既存の言の葉に言葉だけを繋ぐ。

写真は送信しない。

#### Request

```json
{
  "latitude": 35.000001,
  "longitude": 139.000001,
  "installation_id": "anonymous-installation-id",
  "comment": "この場所、夜も好きです。"
}
```

#### Server processing

対象言の葉との距離を計算する。

- 5m以内: 登録可能
- 5mより遠い: 登録不可

新規の言の葉と異なり、v0.1では5分間隔の制限を設けない。

登録されたレコードには対象言の葉のIDを `parent_id` として保存する。

#### Response

```json
{
  "id": 1004,
  "parent_id": 1001,
  "status": "created",
  "created_at": "2026-08-16T16:10:00+09:00"
}
```

## 7. 通報

### POST `/api/reports`

表示している言の葉を通報する。

#### Request

```json
{
  "kotonoha_id": 1001,
  "installation_id": "anonymous-installation-id",
  "reason": "inappropriate_image"
}
```

#### Reason

v0.1では以下を想定する。

- `inappropriate_image`
- `inappropriate_text`
- `harassment`
- `other`

通報自体は対象言の葉の閲覧距離とは独立して扱うが、原則として表示中の言の葉から実行する。

#### Response

```json
{
  "status": "received"
}
```

## 8. エラー

共通形式:

```json
{
  "error": {
    "code": "DISTANCE_TOO_FAR",
    "message": "対象の言の葉から5m以内に近づいてください。"
  }
}
```

主なエラーコード:

- `INVALID_REQUEST`
- `INVALID_LOCATION`
- `BLOCKED_INSTALLATION`
- `POST_COOLDOWN`
- `DISTANCE_TOO_FAR`
- `CONTENT_NOT_FOUND`
- `COMMENT_TOO_LONG`
- `INVALID_IMAGE`
- `SERVER_ERROR`

## 9. 管理API

管理APIは一般アプリAPIと分離し、管理者のみ利用可能とする。

### GET `/admin/api/reports`

通報一覧を取得する。

### GET `/admin/api/reports/{id}`

通報内容と対象言の葉を確認する。

### POST `/admin/api/reports/{id}/resolve`

通報を確認済みとして処理する。

対応内容を記録する。

想定対応:

- `no_action`: 対応不要
- `hide`: 言の葉を非表示
- `delete`: 言の葉を削除状態にする
- `block`: 対象installation_idをブロック
- `delete_and_block`: 言の葉を削除し、installation_idもブロック

### POST `/admin/api/kotonoha/{id}/hide`

管理者が対象言の葉を非表示にする。

### GET `/admin/api/block-list`

ブロックリストを確認する。

### POST `/admin/api/block-list`

installation_idをブロックリストへ追加する。

### DELETE `/admin/api/block-list/{id}`

ブロックを解除する。

## 10. API設計上の重要事項

- クライアントから送られた距離判定結果を信用しない。
- 10m閲覧・5m投稿可否はAPI側で再計算する。
- installation_idはレスポンスに返さない。
- 管理APIは一般ユーザーAPIとアクセス制御を分離する。
- 写真は新規の言の葉作成時だけ受け付け、言葉を繋ぐAPIでは受け付けない。
- 地図更新APIでは写真やコメント本文を返さない。
