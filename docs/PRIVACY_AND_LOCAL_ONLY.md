# PRIVACY_AND_LOCAL_ONLY.md

- 動画、抽出音声、人物sample、Embedding、解析結果を外部サービスへ送信しない。
- 製品の主要解析はネット接続なしで動作する。
- ログへ音声内容や個人情報を必要以上に保存しない。
- traceback/logにローカルpath等が含まれる場合、外部共有はユーザーが明示的に行う場合だけ。
- 開発時の依存/モデル取得と、製品実行時の通信を区別する。
- 製品が勝手にモデルdownload、telemetry、analytics送信を行わない。
