# Agent Sandbox Platform

Mac mini 上の Docker Sandboxes で Claude Code と T3 Server を動かし、複数プロジェクトを権限制御された形で並列実行する PoC。

- 計画の詳細: [.claude/plan.md](.claude/plan.md)
- タスク: GitHub Issues #1〜#12(Milestone M0〜M4)

> **ステータス**: PoC 計画段階。以下の図は **目標構成** を表しており、未検証・未実装の部分を含む。
> 実証済みの範囲は [plan.md の「実証済みのベースライン」](.claude/plan.md) を参照。

## 1. ディレクトリ構成

リポジトリの **予定構成**(現時点で実在するのは `.github/` と `.claude/` のみ)。

> `treeView-beta` は Mermaid v11.14.0 以降が必要な beta 機能。表示されない環境では、Mermaid のバージョンを確認すること。

```mermaid
treeView-beta
    agent-sandbox-platform/
        README.md
        docs/
            architecture.md
            decisions/
            operations.md
            security-model.md
            test-results.md
        environments/
            poc.sbxenv.yaml
        config/
            network-policy.example.yaml
            settings.example.env
        scripts/
            create.sh
            start.sh
            stop.sh
            status.sh
            healthcheck.sh
            apply-policy.sh
            pair-mobile.sh
        tests/
            smoke.md
            network.md
            scheduled-tasks.md
            recovery.md
```

| パス | 役割 |
|---|---|
| `docs/decisions/` | ADR(選定理由・トレードオフ) |
| `environments/poc.sbxenv.yaml` | Mountless / Kit 選択 / 非秘密設定 |
| `config/network-policy.example.yaml` | PoC 独自形式のネットワークポリシー(公式 `sbxenv` の項目ではない) |
| `scripts/` | Sandbox のライフサイクル、ポリシー適用、モバイルペアリング |
| `tests/` | 手順書形式の検証記録(smoke / network / scheduled tasks / recovery) |

秘密鍵、トークン、iPhone ペアリング URL、トークン更新ログはコミットしない。

## 2. アーキテクチャ図

```mermaid
flowchart LR
    iPhone["iPhone<br/>T3 Code Mobile"]
    Desktop["T3 Code Desktop"]

    subgraph Mac["Mac mini (接続・管理ホスト)"]
        TS["Tailscale Serve<br/>Tailnet 内 HTTPS 入口"]
        SSH["SSH port forward<br/>localhost 限定"]
        Scripts["sbxenv / lifecycle scripts"]
        Token["GitHub App token 供給<br/>(秘密鍵は Sandbox に渡さない)"]
    end

    subgraph SB["Docker Sandbox: agent-platform-poc (mountless)"]
        T3["T3 Server<br/>+ Scheduled tasks"]
        CC["Claude Code"]
        subgraph WS["/home/agent/workspace"]
            Pub["public-repo"]
            Priv["private-repo"]
        end
        Tok["Installation Token<br/>短命・最小権限"]
        Policy["Egress policy"]
    end

    subgraph Ext["外部サービス"]
        Claude["Claude 関連サービス"]
        GH["GitHub"]
        Pkg["依存パッケージ配布先"]
    end

    iPhone -->|"Tailscale HTTPS"| TS
    TS --> SSH
    Desktop --> SSH
    SSH --> T3
    T3 --> CC
    CC --> WS
    Scripts -.->|"作成・起動・停止"| SB
    Token -.->|"約50分周期で更新"| Tok
    Tok --> WS
    SB --> Policy
    Policy -->|"allow"| Claude
    Policy -->|"allow"| GH
    Policy -->|"必要先のみ"| Pkg
```

**信頼境界**: Project / Thread / worktree は作業管理の単位であって、アクセス権の隔離ではない。Public / Private リポが同居する Sandbox では、互いのファイルが見える。権限や実行リスクが異なる場合は Sandbox を分ける。

## 3. 処理シーケンス図

環境構築から、日常の操作、定期実行までの流れ(目標)。

```mermaid
sequenceDiagram
    autonumber
    actor User as 利用者
    participant Mac as Mac mini scripts
    participant SB as Sandbox
    participant T3 as T3 Server
    participant CC as Claude Code
    participant GH as GitHub

    rect rgb(240, 245, 255)
    Note over User,GH: 構築 (Epic A)
    User->>Mac: create.sh
    Mac->>SB: Mountless Sandbox を作成
    Mac->>SB: Claude v3 Workload と T3 v3 Mixin を適用
    User->>CC: OAuth 認証
    Mac->>SB: Installation Token を配布
    SB->>GH: Public / Private リポを clone
    User->>T3: 各リポを Project として登録
    end

    rect rgb(240, 255, 245)
    Note over User,GH: 日常操作
    User->>T3: タスクを指示 (Desktop / iPhone)
    T3->>CC: Thread / worktree で実行
    CC->>GH: branch 作成、commit、push
    CC->>GH: Pull Request 作成
    User->>GH: レビューして merge
    end

    rect rgb(255, 248, 235)
    Note over Mac,GH: トークン更新 (約50分周期)
    Mac->>GH: Installation Token を再取得
    Mac->>SB: 新しいトークンへ差し替え
    end

    rect rgb(250, 240, 255)
    Note over User,GH: 定期実行 (Epic C 検証対象)
    User->>T3: Scheduled task を登録 (読み取り専用)
    T3->>CC: 時刻到来で実行
    CC->>GH: 読み取りのみ
    T3-->>User: 結果を Thread に保存
    end
```

## 4. 通信フロー図

### 4.1 クライアントから Sandbox へ(インバウンド)

```mermaid
sequenceDiagram
    autonumber
    participant iPhone as iPhone (T3 Code Mobile)
    participant TS as Tailscale Serve (Mac mini)
    participant SSH as SSH ローカル転送 (localhost)
    participant T3 as T3 Server (Sandbox)

    iPhone->>TS: HTTPS (Tailnet 内のみ)
    TS->>SSH: localhost へ転送
    SSH->>T3: SSH トンネル経由
    T3-->>SSH: 応答
    SSH-->>TS: 応答
    TS-->>iPhone: 応答
```

Tailscale Serve は Tailnet 限定、Mac 側の転送は localhost 限定を維持する。

### 4.2 Sandbox から外部へ(Egress)

```mermaid
sequenceDiagram
    autonumber
    participant CC as Claude Code / Git (Sandbox)
    participant P as Sandbox proxy (Egress policy)
    participant Claude as Claude 関連サービス
    participant GH as GitHub
    participant Other as 許可リスト外

    CC->>P: Claude 推論リクエスト
    P->>Claude: allow
    Claude-->>CC: 応答

    CC->>P: git fetch / push (HTTPS)
    Note over P,GH: proxy が認証情報を注入
    P->>GH: allow
    GH-->>CC: 応答

    CC->>P: 許可リスト外へのアクセス
    P--xCC: 403 Blocked
    Note over CC,Other: Other には到達しない
```

宛先の FQDN・プロトコルの棚卸しは Issue #5、実効ポリシーの Allow / Deny テストは Issue #7 で実施する。Kit 由来の許可を含む **実効ポリシー** は実測で確認すること。

## 参考資料

- [Docker — Sandbox environment files](https://docs.docker.com/ai/sandboxes/configuration/environment-files/)
- [Docker — Use kits](https://docs.docker.com/ai/sandboxes/customize/use-kits/)
- [Docker — Manage local network rules](https://docs.docker.com/ai/governance/local/network-rules/)
- [Docker — Connect T3 Code to a sandbox](https://docs.docker.com/ai/sandboxes/integrations/t3-code/)
- [T3 Code — Remote access](https://github.com/pingdotgg/t3code/blob/main/docs/user/remote-access.md)
- [Mermaid — Tree View](https://mermaid.ai/open-source/syntax/treeView.html)
