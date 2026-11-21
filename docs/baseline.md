# ベースライン(Issue #1)

PoC を始める時点の構成と、実証済み/未検証の区分を固定する。比較用の基準であり、以後の変更はここへ上書きせず `test-results.md` に追記する。

> **秘密情報は書かない**: トークン、秘密鍵、iPhone ペアリング URL、tailnet の内部ホスト名は記載しない。

- 採取日: 2026-11-21(`scripts/collect-baseline.sh`、Mac mini)
- 採取者: 利用者(出力は目視で確認し、ホスト名・ローカルパス・ポリシーIDは転記していない)

## 1. 区分の凡例

| 区分 | 意味 |
|---|---|
| 実証済み(報告) | 利用者が実環境で動作を確認したと報告したもの。再現手順・証跡は未整備 |
| 実証済み(実測) | 本リポジトリの手順で採取した出力や記録がある |
| 未検証 | まだ確認していない |

## 2. バージョン表

| 項目 | 値 | 採取元 | 区分 |
|---|---|---|---|
| `sbx` | v0.54.0 | `sbx --version` | 実証済み(実測) |
| Tailscale | 1.104.5 | `tailscale version` | 実証済み(実測) |
| agent イメージ(既存環境A) | DHI の claude 2.1.319、digest 固定(2026-11-11 解決) | 既存の `sbxenv.yaml`(`sandboxOptions.template`) | 実証済み(報告) |
| T3 Kit(既存環境A) | `docker.io/sbx/t3code:latest@sha256:93569f4d…8234`(2026-11-11 時点) | 既存の `sbxenv.yaml`(`kits`) | 実証済み(報告) |
| agent イメージ(PoC) | 既存環境Aと同じ版・同じ digest(`8ba2b44d…`)を `docker.io/sbx/claude:2.1.319@sha256:…` の参照で `template` に指定(既存環境Aは `dhi.io/claude` 表記)。agent Kit は固定せず latest | `environments/sbxenv.yaml` | 未作成(`sbx env plan` で受理を確認する) |

- DHI のイメージには node が入っておらず、T3 Code が素の状態では動かない(利用者報告)。ただし既存環境Aでは T3 Kit との組み合わせで動作している。
- `docker.io/sbx/claude:2.1.319` と `dhi.io/claude:2.1.319` は同じ digest(`8ba2b44d…`)を指す(2026-11-21 確認)。

**比較した代替案(2026-11-21 調査)**: `docker.io/docker/sandbox-templates:claude-code`(0.10.0、2026-10-21、index digest `30ec2b1b…`)。Ubuntu 26.04 ベースで node v22.22.1 / Claude Code 2.1.306 を同梱(digest 指定で起動して確認)。DHI より Claude Code の版が古く、`sbx env` の `template` と T3 Kit との組み合わせは未検証のため、初期構成には採用しない。

**最新の公開版(2026-11-21 時点)**: `sbx/claude` は 2.1.329(2026-11-21)、`sbx/t3code` は 0.0.45(`sha256:8c79c7e2…`、2026-11-20)。既存環境Aの T3 Kit の digest(`93569f4d…`)は、現在どのタグにも付いていない旧版。レジストリから消えるリスクがあるため、`plan` / 作成時に pull できるか確認する(#2)。
- 参照は `tag@digest` の併記形式で動作している。固定は `sandboxOptions.template`(agent)と `kits`(Kit)で行う。
- Kit は Sandbox 作成時に追加のパッケージを取得しうる。Kit の digest 固定だけでは、そのバージョンまでは固定されない(#2 で確認)。
| T3 Code Desktop | (記入) | アプリのバージョン表示 | 未採取 |
| T3 Code Mobile | (記入) | アプリのバージョン表示 | 未採取 |
| T3 Server | (記入) | Sandbox 内で確認 | 未採取 |
| Claude Code | (記入) | Sandbox 内で確認 | 未採取 |

Kit は `latest` で動いた版を後から特定できないため、**tag か digest で記録する**。

## 3. Sandbox 一覧

| 名前 | 用途 | 構成 | Workspace | 備考 |
|---|---|---|---|---|
| 既存環境A | T3 を動かしている検証環境(detached で稼働中) | claude | host の workspace をマウント + `sbxenv.yaml` を read-only でマウント | **変更しない**。比較用に維持 |
| 既存環境B〜D | 別用途の環境(計3つ、停止中が多い) | claude | host の workspace をマウント | PoC と無関係。触らない |
| 本リポジトリ用(この作業を行っている環境) | 稼働中 | claude | host の workspace をマウント(Mountless ではない) | PoC の対象外 |
| `agent-platform-poc`(予定) | PoC | claude + T3 Kit | Mountless(`workspace` 省略) | **未作成**。#2 で作成 |

- 計画書にあった `t3-practice` は Sandbox 一覧に存在しない(名前が違う可能性。要確認)。
- **Mountless の Sandbox は、現時点で1つも無い**。「Mountless で実証済み」の報告は、再現できる環境が残っていない。
- 環境名はプロジェクト名を含むため、ここでは用途で記載している。

## 4. 接続経路

```text
iPhone (T3 Code Mobile)
  → Tailscale Serve (Mac mini, Tailnet 内 HTTPS)
  → SSH ローカル転送 (localhost 限定)
  → Sandbox 内 T3 Server
```

| 項目 | 値 | 区分 |
|---|---|---|
| Tailscale Serve | `/` → `http://127.0.0.1:4773` に proxy、Tailnet 限定 | 実証済み(実測) |
| SSH 転送のローカルポート | 4773(Serve の転送先と一致)。Sandbox 側の T3 Server は 127.0.0.1:3773 | 一部のみ(Serve 側のみ実測) |
| 既存 Serve 設定(上書き禁止) | 上記の1件のみ。**PoC は別ポートを使うか、パス分離を検討する** | 実証済み(実測) |

Serve の公開 URL(tailnet ホスト名)は転記しない。

## 5. ネットワークポリシー(現行)

| 項目 | 内容 | 区分 |
|---|---|---|
| global `local-policy` | network: **194 allow**、filesystem: read 全許可 / write 全許可 | 実証済み(実測) |
| global フォールバック | `default-deny-all`(どのルールも決めなければ deny) | 実証済み(実測) |
| Kit 由来の許可 | Sandbox ごとに network: 8 allow(5環境とも同数) | 実証済み(実測) |
| Sandbox 個別ルール | 既存環境Aに2件、本リポジトリ用に1件(いずれも allow) | 実証済み(実測) |
| 既存環境Aの実効 | 197 hosts を許可(Kit + 個別 + global) | 実証済み(実測) |

**含意**: global の許可が広いため、PoC 環境も何もしなければ約 190 件以上の許可を継承する。「Sandbox 個別で絞る」には、deny が allow より優先される性質を使うか、global 自体を見直す必要がある(#6)。実効の一覧は `sbx policy ls <name> --wide` で取れる(#5)。

### 5.1 新環境 `agent-platform-poc` の実測(2026-11-21)

`sbx env create ./environments --name agent-platform-poc` で作成。既存環境には影響なし。

| 項目 | 結果 |
|---|---|
| 作成 | 成功。Kit 2つ（claude / t3code）を5レイヤに合成。旧 t3code の digest も pull できた |
| Mountless | 成功。`WORKSPACE` は `-`、`no workspace bind mount` |
| Claude Code | **2.1.319**（`template` の固定どおり） |
| node | **入っていない**（`which node` が失敗）。t3code Kit は `libatomic1` を入れる処理があり、T3 は prebuilt バイナリで動く構成と推測。T3 の初回接続で要確認 |
| 空き容量 | `/` は 20G 中 69M 使用 |
| CPU / メモリ | host 既定値（10 CPU / 8 GiB）のまま。上限未設定 |
| host の skills ディレクトリ | 既定で読み取り専用マウント（0 entries）。`skills: "off"` で切る案（要再作成） |
| 起動時の処理 | 起動のたびに apt キャッシュ更新（背景）と MCP gateway 登録が走る。Egress の棚卸し対象（#5） |

**agent Kit が `latest` に解決された**: `agent: claude` と書くと create 時に `docker.io/sbx/claude:latest`（当日は 2.1.329 の digest）へ解決された。`template` で固定したのは土台のイメージだけで、Claude Code 本体の版は変わらなかったが、**agent Kit は固定されていない**。Kit のインストールコマンドは root で実行される。`agent` に Kit 参照を直接書く案は `sbx env plan` で拒否された（"is a kit reference, but `agent:` takes an agent name"）。`agent: claude` のまま `template` を `docker.io/sbx/claude:2.1.319@sha256:8ba2…` にした環境で `sbx env create` が通った（2026-11-21）。

**決定: agent Kit は latest のまま許容する**: `Image:` は `template` の 2.1.319 のままだが、agent Kit は `docker.io/sbx/claude@sha256:3733d394…`（latest）に解決される。`template` は土台イメージ、agent Kit は install コマンドと Egress ルールを持つ別レイヤ。Kit ルール8件とレイヤ構成（5レイヤ）は固定した場合と同じだった。`kits:` に同じ参照を並べて固定する案は、二重にならないかを未検証のまま採用しない。固定が必要になったら再検討する。

### 5.2 新環境の実効ネットワークポリシー（`sbx policy ls <name> --wide`）

global `local-policy` の既定ルール群（`created via: default`）が、そのまま効いている。ポリシー ID・ルール ID は転記しない。

| ルール群 | 内容（代表） | PoC での扱い |
|---|---|---|
| default-ai-services | `api.anthropic.com`、`claude.com` のほか、OpenAI / Cursor / Gemini / Perplexity 系 | Claude 以外は不要。過剰 |
| default-package-managers | npm、PyPI、crates.io、Maven、Go、RubyGems、nuget など約60件 | 必要な言語だけに絞りたい |
| default-code-and-containers | `**.github.com`、`**.githubusercontent.com`、`**.docker.io`、`ghcr.io`、`gitlab.com`、`quay.io` など | GitHub は必須。他は要検討 |
| default-cloud-infrastructure | `**.amazonaws.com`、`**.googleapis.com`、`**.blob.core.windows.net`、`supabase.com`、`vercel.com` など | **外部への持ち出し経路になりうる** |
| default-os-packages | Debian / Ubuntu / Alpine など | apt 更新に必要 |
| default-cert-validation | OCSP / CRL の各社 | 必要 |
| filesystem read / write | どちらも全許可（`**`） | 意味は未確認。公式の記述を確認する |
| フォールバック | `default-deny-all`（tcp, udp を deny） | — |

**この環境にだけ付いた Kit ルール（8件）**: `api.anthropic.com`、`bridge.claudeusercontent.com`、`claude.com`、`deb.debian.org:80`、`dhi.io:80`、`downloads.claude.ai`、`mcp-proxy.anthropic.com`、`platform.claude.com`。**t3code Kit は Egress ルールを持たない**（T3 の初回インストール元は未確認）。

**絞り込みの難しさ**: 「どれかの allow で許可、deny は出所を問わず優先」のため、Sandbox 個別の allow では global の広い許可を狭められない。個別に `deny **` を置くと Kit の許可も潰れる。global を `deny-all` にすると既存環境に影響する。方針は #6 で決める。

## 6. 実証済み / 未検証

### 実証済み(報告)

出典: 利用者報告(2026-11-21 時点)。

- Mountless Sandbox で Claude Code の OAuth 認証を利用できた
- T3 Code で複数 Project を登録し、Public / Private を混在させて並行実行できた
- 旧 DHI 構成で、Tailscale Serve + SSH 転送を通じ iPhone から Claude Code を操作できた
- GitHub App Installation Token の約 50 分周期更新が、既存の `sbx` 運用で約 1 か月の利用実績がある

### 未検証

- **新しい Mountless 環境**での GitHub App 認証・トークン更新の継続性(#4)
- 新しい Mountless 環境への iPhone 接続
- Sandbox 停止・再起動後のプロジェクト・認証・設定の保持
- 実効ネットワークポリシー(Kit 由来の許可を含む)(#5・#7)
- T3 Scheduled tasks の挙動(#8・#9)
- `sbx env` による宣言的な再構築(#2)。experimental で形式が変わりうる

## 7. 採取手順(Mac mini で実施)

読み取り専用。何も作成・変更・削除しない。

```bash
scripts/collect-baseline.sh <既存環境A> <新Mountless環境名> > baseline-$(date +%F).baseline.txt
```

出力は `.gitignore` 対象。内容を確認し、秘密情報を除いたうえで上の表へ転記する。

**実施しないこと**: `sbx policy init`、既存 Sandbox の削除、Tailscale Serve の上書き。
