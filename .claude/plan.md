# Agent Sandbox Platform PoC — 設計・検証計画 / GitHub Issues 分割案

> Status: Revised / 2026-11-21  
> Scope: Mac mini + Docker Sandboxes (Mountless) + T3 Code + Claude Code + Tailscale + GitHub App  
> Out of scope: SC（情報処理安全確保支援士）試験対策・学習コンテンツそのもの

## 1. 背景と目的

現状、Mac mini上で Docker Sandboxes に Claude Code と T3 Server を動かし、T3 Code Desktop / Mobile から操作できるところまで実証している。DHIベース構成でも動作実績があるが、PoCではDHIを必須条件にしない。iPhone側の経路は **Tailscale Serve（Mac mini）→ SSHローカル転送 → Sandbox内T3 Server**。GitHub操作には個人アカウントのPATではなく、最小権限のGitHub App Installation Tokenを使い、約50分間隔で更新する既存仕組みがある。

次の段階では「手動で動く環境」から「再現可能・複数プロジェクト対応・権限制御されたAIエージェント実行基盤」へ拡張する。既存の `t3-practice` は変更せず、別のSandboxでPoCを進める。

### ゴール

1. **Mountless / 1 Environment : n Project**：Mac側のリポジトリをマウントせず、Sandbox内でGitHubからcloneした複数Projectを並列に扱う。
2. **明示的なEgress制御**：Claude、GitHub、T3関連の必要な宛先を棚卸しし、実効ルールでAllow/Denyを確認する。
3. **Scheduled tasksによる継続実行**：T3 Codeのスケジュール機能を検証し、結果保存・重複実行・失敗時・再起動後の挙動を確かめる。
4. **宣言的・再現可能**：`sbxenv.yaml`（可能な範囲）、Mac側スクリプト、READMEで環境を再構築できる。
5. **安定運用**：GitHub Appの短命トークン更新、iPhone接続、障害後の回復を検証する。

### 実証済みのベースライン（2026-11-21時点のユーザー報告）

- Mountless SandboxでClaude CodeのOAuth認証を利用できた。
- T3 Codeで複数Projectを登録し、Public/Privateリポジトリを混在させて並行実行できた。
- 旧DHI構成ではTailscale Serve + SSH転送を通じ、iPhoneからClaude Codeを操作できた。
- GitHub App Installation Tokenの約50分周期更新は既存の`sbx`運用で約1か月の利用実績がある。ただし**新しいMountless環境での認証・更新の継続性は別途確認する**。

### 非ゴール

- SC試験教材、過去問、学習履歴の管理
- Codexやその他プロバイダの追加・比較（将来の拡張候補として保留）
- 人間の監督なしに高権限の変更を自動反映する運用
- Azure VM / ACA Sandboxesへの移植（将来の別Epic）
- 既存 `t3-practice` の破壊的移行

## 2. アーキテクチャ（検証目標）

```text
Mac mini（接続・管理ホスト）
├─ sbxenv / Sandbox lifecycle scripts
├─ Tailscale Serve（Tailnet内HTTPS入口）
├─ SSH port forward（localhost限定）
└─ GitHub App token供給機構（既存方式を再利用、秘密鍵はSandboxへ渡さない方針）
             │
             ▼
Docker Sandbox: agent-platform-poc  [mountless / Claude Code専用]
├─ T3 Server ── Scheduled tasks（検証対象）
├─ Claude Code
├─ /home/agent/workspace/
│  ├─ public-repo/       ← GitHubからclone
│  └─ private-repo/      ← GitHub App権限でclone
├─ GitHub App Installation Token（短命・必要最小権限）
└─ Egress policy（実効ルールを確認）
             │
             ├─ Claude関連サービス
             └─ GitHub / 必要な依存パッケージ配布先

iPhone + T3 Code Mobile ── Tailscale HTTPS ── Mac mini ── T3 Server
```

> **信頼境界**：Project/Thread/worktreeは作業管理の単位であり、アクセス権の隔離ではない。Public/Privateが同居できることと、任意の未信頼コードを同じSandboxに入れて安全なことは別。機密性・権限・実行リスクが異なる場合はSandboxを分ける。

## 3. 設計判断・比較ポイント

| 論点 | 採用方針 | 留意・検証事項 |
|---|---|---|
| ワークスペース | Mountless | stop/startの永続性、削除時の未pushデータ喪失 |
| Project | 1 Sandboxに関連する複数Git clone | Public/Privateは同じファイル・認証境界を共有 |
| エージェント | Claude Codeのみ | 他プロバイダ追加は今回は対象外 |
| ベースイメージ・Kit | Claude v3 Workload + T3 v3 Mixin | DHI必須ではない。動作版/digestを記録 |
| ネットワーク | deny-allを目標に必要先の許可を設計 | Kit由来許可・globalルールを含む実効制御を検証 |
| スケジュール | T3 Scheduled tasksを検証 | バージョン・提供UI・失敗時/オフライン時の挙動を実測 |
| モバイル | Mac Tailscale Serve + SSH転送 | 自動復旧・ペアリング継続性 |
| GitHub | GitHub App Installation Token | 個人PAT不使用、更新前後の継続性を確認 |

**Network制約**：グローバルpreset、Sandbox個別ルール、Kitが追加する許可を含めた**実効ポリシー**を評価する。`sbx policy init deny-all` のようなグローバル変更は既存環境への影響を確認しない限り実行しない。ポリシー管理YAMLはPoCの独自設定として扱い、公式`sbxenv`のネイティブ項目と混同しない。

**Scheduled tasks制約**：UI・設定名・スケジュール仕様はT3 Codeのバージョンごとに検証する。定期実行は安全な読み取り専用タスクから始め、GitHubへの書き込みは別途承認設計ができるまで含めない。

## 4. リポジトリ案

```text
agent-sandbox-platform/
├─ README.md
├─ docs/
│  ├─ architecture.md
│  ├─ decisions/                  # ADR: 選定理由・トレードオフ
│  ├─ operations.md               # 作成/起動/停止/復旧
│  ├─ security-model.md           # 信頼境界・権限・データ
│  └─ test-results.md             # 実行日/バージョン/検証結果
├─ environments/
│  └─ poc.sbxenv.yaml             # mountless / Kit選択 / 非秘密設定
├─ config/
│  ├─ network-policy.example.yaml # 独自形式（適用スクリプト用）
│  └─ settings.example.env        # Sandbox名やhostポート（秘密なし）
├─ scripts/
│  ├─ create.sh
│  ├─ start.sh
│  ├─ stop.sh
│  ├─ status.sh
│  ├─ healthcheck.sh
│  ├─ apply-policy.sh
│  └─ pair-mobile.sh
└─ tests/
   ├─ smoke.md
   ├─ network.md
   ├─ scheduled-tasks.md
   └─ recovery.md
```

秘密鍵、トークン、iPhoneペアリングURL、トークン更新ログはコミット対象外。`sbxenv.yaml`はSandboxの書き込み可能マウントの外に置く。

## 5. Issue分割（Epic + 実装・検証タスク）

Priority: **P0 = 土台 / P1 = 中核機能 / P2 = 運用強化**。番号は**計画上の仮ID**であり、GitHub Issueの実番号ではない。既に実証できた項目は確認結果を文書化してクローズする。

### Epic A — Mountless基盤・GitHub SSOT

#### Issue #01 [P0] 既存構成の棚卸し・ベースライン固定
- **内容**：`sbx`/Kit/T3のバージョン、既存DHI成功構成、Mountless成功構成、SSH/Tailscale経路を秘密情報なしで記録する。
- **完了条件**：再現に必要なバージョン表、構成図、実証済み/未検証の区分が文書にある。
- **依存**：なし。
- **現状**：実行実績あり／文書化待ち。

#### Issue #02 [P0] Mountless環境を宣言的に再現
- **内容**：`sbxenv.yaml`または固定CLIスクリプトでClaude + T3環境を作る。Mountlessであることを検査し、既存環境に影響させない。
- **完了条件**：別名Sandboxを作成し、OAuth認証、T3 Desktop接続、Macリポジトリ非マウントを確認。作成・破棄手順を文書化。
- **依存**：#01。
- **現状**：MountlessとOAuthの利用実績あり／再構築の自動化待ち。

#### Issue #03 [P0] 複数Project（Public/Private）並列実行の再現
- **内容**：Sandbox内でPublic/Privateの2リポジトリをcloneし、T3で別Projectとして登録。並行実行とGitHub App権限を確認する。
- **完了条件**：Macにリポがなくても複数Projectを開始でき、同時実行ログ・権限境界上の注意を記録。
- **依存**：#02。
- **現状**：ユーザー環境で実証済み／再現記録待ち。

#### Issue #04 [P1] GitHub SSOT・branch/PR・トークン更新を検証
- **内容**：fetch → branch → commit/push → PR → mergeの運用を定義し、短命Installation Token更新前後のGit操作を検証。
- **完了条件**：PRを完走、未push変更の検知、Sandbox削除前チェック、秘密情報を残さない運用手順がある。
- **依存**：#03。

### Epic B — ネットワーク境界の明示化

#### Issue #05 [P0] Egress先の棚卸し
- **内容**：Claude、GitHub、T3 Kit、認証、パッケージ取得に必要なFQDN・プロトコル・用途・証拠を調べる。
- **完了条件**：必要先と任意先を区別した通信先一覧、現行の実効ポリシー、未把握先を記録。
- **依存**：#01。

#### Issue #06 [P1] Sandbox単位のネットワークポリシー適用
- **内容**：専用設定と適用スクリプト（dry-run、差分表示、復旧手順）を用意。グローバル変更を避ける。
- **完了条件**：PoCだけに適用でき、既存SandboxやTailscale Serveに影響しないことを確認。
- **依存**：#02・#05。

#### Issue #07 [P1] Allow/Deny実効テスト
- **内容**：許可先へのアクセス、禁止先への拒否、Claude推論、GitHub App更新後のGit操作をテストする。
- **完了条件**：結果と実効例外を記録。意図しない通信があれば修正・リスク受容・不採用を判断。
- **依存**：#04・#06。

### Epic C — Scheduled tasks / 自律実行

#### Issue #08 [P1] T3 Scheduled tasksの単発・定期実行を検証
- **内容**：対象バージョンのUI/設定仕様を確認し、読み取り専用タスクを1回・定期で実行。結果のスレッド、エラー、Project指定を検証。
- **完了条件**：実行履歴、出力先、次回実行時刻、手動停止・再開の操作を記録。二重実行が起こる条件を確認。
- **依存**：#03。

#### Issue #09 [P1] スケジュールの継続性・安全策を検証
- **内容**：Sandbox停止・復帰、T3 Server再起動、ネットワーク障害、GitHubトークン更新をまたぐ実行を確認。
- **完了条件**：欠落/追いつき実行、失敗再試行、重複実行、通知可否を実測し、必要な承認・停止ルールを定義。
- **依存**：#07・#08。
- **安全策**：初期段階は外部書き込みを行わず、後に明示的な承認ゲートを設計。

### Epic D — Mac側接続・復旧・公開準備

#### Issue #10 [P1] Mac側スクリプトとヘルスチェックを汎用化
- **内容**：Sandbox名、転送ポート、Tailscale Serveの設定を外部化。start/stop/status/healthcheckを実装。
- **完了条件**：冪等、ポート衝突検出、他のServe設定を上書きしない、疎通確認できる。
- **依存**：#02。

#### Issue #11 [P2] 再起動・SSH切断・iPhone再接続を検証
- **内容**：SSH切断、Sandbox stop/start、T3 Server終了、Mac再起動を試し、必要に応じて`launchd`で復旧。
- **完了条件**：iPhoneから閲覧・指示・承認が再開でき、再ペアリング要否と復旧手順を実測。
- **依存**：#10・#08。

#### Issue #12 [P2] 運用README・セキュリティレビュー・PoC判定
- **内容**：秘密情報管理、GitHub App、Public/Private混在時のリスク、Egress、定期実行、データ破棄、起動復旧を総点検。
- **完了条件**：初見の人が別名環境を再現でき、既知の制約・残リスク・導入可否を記録。
- **依存**：#04・#07・#09・#11。

## 6. 推奨実施順序 / マイルストーン

| Milestone | Issue | 到達状態 |
|---|---|---|
| **M0: Baseline** | #01 | 既存成功構成を記録 |
| **M1: Mountless基盤** | #02 → #03 → #04 | 複数リポの再現とGitHub SSOT運用 |
| **M2: Network governance** | #05 → #06 → #07 | 通信先を明示して実効確認 |
| **M3: Scheduled operations** | #08 → #09 | 定期タスクと停止・復帰の動作確認 |
| **M4: Reliability** | #10 → #11 → #12 | リモート接続・復旧と最終判定 |

並行可能：#05は#02〜#04と並行、#08は#05〜#07と並行、#10は#03〜#09と並行に着手できる。#09の安全な本格検証は#07を経てから実施する。

## 7. PoCの受入テスト（最小セット）

- [x] Mountless SandboxでClaude CodeをOAuth認証して利用できる（ユーザー実証）
- [x] 1 EnvironmentでPublic/Private複数Projectを同時並行実行できる（ユーザー実証）
- [ ] 宣言ファイルまたは固定CLIから環境を再現でき、ホストGitリポをマウントしていない
- [ ] GitHub App Installation Tokenの更新後も**新しいMountless Sandbox**からGit操作を継続できる
- [ ] Claudeで編集・commit・push・PRの一連を完走できる
- [ ] 許可先への通信成功、拒否先への通信失敗を確認し、例外を文書化できる
- [ ] T3 Scheduled tasksで単発・定期実行し、履歴と結果を確認できる
- [ ] スケジュール実行の停止・復帰・重複・失敗時挙動を実測できる
- [ ] Tailscale ServeはTailnet限定、Mac側転送はlocalhost限定を維持できる
- [ ] 新しいMountless SandboxにiPhoneから接続し、指示・承認ができる
- [ ] Sandbox停止・再起動後もプロジェクトと認証・設定が必要な範囲で保持される
- [ ] 削除前に未pushの差分を検知でき、READMEから再構築できる

## 8. 実装時の注意・既知の不確実性

1. **`sbx env`はExperimental**。対象`sbx`版で`env plan`を検証し、宣言形式で表現できない要件は固定CLI + READMEに分離する。
2. **DHIは必須ではない**。PoCではClaude v3 WorkloadとT3 v3 Mixinの組合せを使用し、バージョン/digestを記録。過去のDHI成功環境は比較用に維持。
3. **Kit由来の許可に注意**。allowlistの記述だけで全Egressが遮断されたと判断しない。実効許可・拒否を実測する。
4. **Mountlessの永続性**。stop/startと削除は別。GitHubは共有済み履歴のSSOTだが、未pushのWIPはSandboxにしか存在しない。
5. **GitHub App認証**。既存の50分更新方式は新Sandboxでも実行時に見えるか確認する。秘密鍵・生トークンをログやGitに保存しない。
6. **Public/Private混在**。同一Sandbox内のProjectは相互にアクセス可能。GitHubリポ単位の権限とSandbox内のファイル可視性を混同しない。
7. **Scheduled tasksの提供仕様**。T3の実バージョンで機能の有無、スケジュール粒度、オフライン時の処理、再試行を確認。推測だけで復旧を保証しない。
8. **ホスト共通設備**。443番、SSH転送ポート、Tailscale Serve設定は他Sandboxと競合し得る。追加前に現状を確認する。
9. **Codexは今回の対象外**。将来追加しやすいように境界と拡張点だけ記録するが、インストール・API許可・検証のIssueには含めない。

## 9. 最初の一歩（破壊的変更なし）

```bash
# Mac mini上で現状を記録
sbx --version
sbx ls
sbx policy ls
sbx policy ls t3-practice
tailscale serve status

# 新しいMountless環境の実際の名前・Kit・認証を記録
sbx ls

# 新規検証に向けて、公式ヘルプとプランを確認
sbx env --help
sbx env plan --help
```

**この時点では `sbx policy init`、既存Sandboxの削除、Tailscale Serveの上書きは行わない。**

## 10. 公式参考資料

- [Docker — Sandbox environment files](https://docs.docker.com/ai/sandboxes/configuration/environment-files/)
- [Docker — Use kits](https://docs.docker.com/ai/sandboxes/customize/use-kits/)
- [Docker — Compose a kit set](https://docs.docker.com/ai/sandboxes/customize/author/kit-sets/)
- [Docker — Manage local network rules](https://docs.docker.com/ai/governance/local/network-rules/)
- [Docker — Local policy](https://docs.docker.com/ai/sandboxes/security/policy/)
- [Docker — Connect T3 Code to a sandbox](https://docs.docker.com/ai/sandboxes/integrations/t3-code/)
- [T3 Code — Remote access](https://github.com/pingdotgg/t3code/blob/main/docs/user/remote-access.md)

---

**暫定の設計原則**：Environmentは権限・情報・実行リスクの境界、ProjectはGitリポジトリ、Thread/worktreeは個別タスク。PoCはClaude Codeに集中し、次の検証軸はネットワーク制御・スケジュール実行・継続運用とする。
