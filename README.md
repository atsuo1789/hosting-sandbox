# ホスティング基盤 ミニチュア版ハンズオン（Step 1〜3）

「申し込み → GitOpsでHelm自動デプロイ」を手元のPCで再現し、体感するためのハンズオンです。

```
[申し込みスクリプト] --commit--> [GitHubリポジトリ: gitops/apps/<環境名>/values.yaml]
                                          ↓ 監視
                                 [Argo CD (ApplicationSet)]
                                          ↓ helm（charts/relay-app ＋ values）
                                 [ローカルKubernetes (kind)]
```

## 構成

```
hosting-sandbox/
├── app/                      … 検証用の中継AP（Spring Boot + Spring Integration）
├── charts/relay-app/         … 中継AP向け「FW標準」Helmチャート
├── gitops/apps/<環境名>/     … 申し込み内容（values.yaml）。1ディレクトリ＝1環境
├── argocd/applicationset.yaml… gitops/apps/* を監視して環境を自動生成
└── scripts/apply.sh          … 「申し込み」を模したスクリプト
```

---

## Step 0：準備

| ツール | 用途 | インストール例（Mac） | Windows |
|---|---|---|---|
| Docker互換環境 | コンテナ実行 | Rancher Desktop または Docker Desktop | 同左 |
| kind | ローカルK8s | `brew install kind` | `winget install Kubernetes.kind` |
| kubectl | K8s操作 | `brew install kubectl` | `winget install Kubernetes.kubectl` |
| helm | Helm操作 | `brew install helm` | `winget install Helm.Helm` |
| git / GitHubアカウント | GitOpsリポジトリ | — | — |

- Docker Desktopは大企業での業務利用に有償契約が必要なため、社用PCでは **Rancher Desktop**（設定で dockerd(moby) を選択）が無難です。
- メモリは Docker側に 6〜8GB 以上割り当てておくと快適です。
- 社内プロキシ環境では、Mavenやイメージ取得にプロキシ設定が必要な場合があります。

---

## Step 1：Kubernetes と Helm の基本を体感する

```bash
# クラスタ作成
kind create cluster --name hosting-sandbox
kubectl get nodes

# Helm標準の雛形チャートでお試し（中身は nginx）
cd /tmp
helm create demo
helm install demo ./demo
kubectl get pods

# アクセス確認（別ターミナルで curl localhost:8081）
kubectl port-forward svc/demo 8081:80
```

### 試してみること
```bash
helm template demo ./demo | less          # values がどう YAML に展開されるか見る
helm upgrade demo ./demo --set replicaCount=2
kubectl get pods                          # Podが2つに
helm history demo                         # リビジョン履歴
helm rollback demo 1                      # 1つ前に戻す
helm uninstall demo
```

**体感ポイント**：「テンプレート（チャート）＋差分（values）」でデプロイする感覚。ただしこの段階では**誰がいつ何を変えたかは手元のコマンド履歴にしか残らない**ことにも注目。

---

## Step 2：中継AP用の「FW標準チャート」でデプロイする

### 2-1. アプリのイメージを作って kind に読み込む
```bash
cd hosting-sandbox/app
docker build -t relay-app:0.1.0 .
kind load docker-image relay-app:0.1.0 --name hosting-sandbox
cd ..
```
※ レジストリを使わず、kindのノードに直接イメージを読み込んでいます。

### 2-2. チャートを確認してデプロイ
```bash
helm lint charts/relay-app
helm template trial charts/relay-app -f gitops/apps/team-a-dev/values.yaml

helm install trial charts/relay-app \
  -n trial --create-namespace \
  -f gitops/apps/team-a-dev/values.yaml

kubectl -n trial get pods -w     # READY 1/1 になるまで待つ（Ctrl+Cで抜ける）
```

### 2-3. 動作確認
```bash
kubectl -n trial port-forward svc/trial 8082:80
# 別ターミナルで
curl -X POST -H 'Content-Type: text/plain' -d 'hello' localhost:8082/relay
# → [team-a-dev] HELLO
```

確認できたら片付け：
```bash
helm uninstall trial -n trial
```

**体感ポイント**：`charts/relay-app/values.yaml` と `templates/deployment.yaml` を見比べてください。
- **templatesで固定**：ポート、ヘルスチェック（Actuator）、ラベル、JVMオプション
- **valuesで開放**：レプリカ数、イメージ、リソース、環境変数

この「どこを固定し、どこを利用者に開放するか」が、FWチームがチャートを提供する際の設計論点になります。

---

## Step 3：Argo CD で GitOps 化する

### 3-1. GitHubにリポジトリを作って push
GitHubに **public** リポジトリ `hosting-sandbox` を作成します（サンプルのみで秘密情報は含みません。privateにする場合はArgo CDへのリポジトリ認証登録が別途必要）。

```bash
cd hosting-sandbox
# ApplicationSet の repoURL を自分のものに書き換え
sed -i.bak 's/YOUR_GITHUB_USER/<あなたのGitHubユーザー名>/g' argocd/applicationset.yaml && rm argocd/applicationset.yaml.bak

git init -b main
git add .
git commit -m "initial"
git remote add origin https://github.com/<あなたのGitHubユーザー名>/hosting-sandbox.git
git push -u origin main
```

### 3-2. Argo CD をインストール
```bash
kubectl create namespace argocd
kubectl apply -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

kubectl -n argocd rollout status deploy/argocd-server

# 初期パスワード（ユーザー名は admin）
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d; echo

# 管理画面（別ターミナル）→ https://localhost:8080 （証明書警告は無視でOK）
kubectl -n argocd port-forward svc/argocd-server 8080:443
```

### 3-3. ApplicationSet を登録
```bash
kubectl apply -f argocd/applicationset.yaml
```
Argo CDの画面に `team-a-dev` が現れ、自動でSyncされます。

```bash
kubectl -n team-a-dev get pods
kubectl -n team-a-dev port-forward svc/team-a-dev 8083:80
curl -X POST -H 'Content-Type: text/plain' -d 'hello' localhost:8083/relay
# → [team-a-dev] HELLO
```

---

## Step 3 の体験メニュー（ここが本題）

Argo CDはデフォルトで約3分ごとにGitを確認します。待てない場合は画面の **Refresh** を押してください。

### ① 申し込みで環境が増える
```bash
./scripts/apply.sh team-b-dev 2
```
→ `team-b-dev` 環境がPod 2つで自動作成される。**利用者はkubectlもhelmも触っていない**。

### ② 設定変更はGitへのcommitで
`gitops/apps/team-a-dev/values.yaml` の `replicaCount` を 3 に変えて commit / push。
→ 自動でスケール。変更履歴＝Gitログ（誰が・いつ・なぜ）。

### ③ 手動変更は自己修復される
```bash
kubectl -n team-a-dev scale deploy team-a-dev --replicas=5
kubectl -n team-a-dev get pods -w
```
→ Argo CDがGitの状態（3）に戻す（selfHeal）。**「本番を直接いじる」が構造的にできない**。

### ④ ロールバックは git revert
```bash
git revert HEAD && git push
```

### ⑤ 環境の削除
```bash
git rm -r gitops/apps/team-b-dev && git commit -m "廃止: team-b-dev" && git push
```
→ リソースが削除される（prune）。※ Namespace自体は残ります。

### ⑥ FW標準チャートを更新する（FWチーム視点で一番大事）
`charts/relay-app/values.yaml` の `resources.requests.memory` を変える、またはテンプレートにラベルを追加して push。
→ **全環境に一斉反映される**。便利な反面、

- 案件ごとにチャートのバージョンを固定（ピン留め）すべきでは？
- FW側の変更をどう検証してから展開する？（→ Step 4の試験・チェックにつながる）

といった、FWを基盤に載せる際の運用論点が見えてきます。

---

## 後片付け
```bash
kind delete cluster --name hosting-sandbox
```

## トラブルシュート

| 症状 | 確認ポイント |
|---|---|
| Pod が `ImagePullBackOff` | `kind load docker-image` 忘れ、またはタグ不一致（values の `image.tag`） |
| Pod が起動後に再起動を繰り返す | `kubectl -n <ns> logs <pod>`。メモリ不足ならlimitsを増やす |
| ApplicationSet から環境が生成されない | repoURLの書き換え漏れ、リポジトリがprivate、`kubectl -n argocd logs deploy/argocd-applicationset-controller` |
| Sync が `values.yaml not found` | ディレクトリ名と values.yaml のパス、push済みか |

## 次のステップ（Step 4以降の予告）
- GitHub Actions / GitLab CI で「テスト → SAST（Semgrep, SpotBugs+find-sec-bugs） → イメージスキャン（Trivy） → GitOpsリポジトリのタグ更新」を自動化
- チャートのバージョン管理（Helmリポジトリ化）と環境ごとのピン留め
