# SOCKS5 代理批量部署配置說明

這個配置文件用於批量部署多個 SOCKS5 代理服務。每個物件代表一個要建立的 SOCKS5 代理服務容器。

## 配置文件格式

配置文件應為 JSON 格式的陣列，每個元素包含以下欄位：

- `container_name`: (字串) 要建立的容器名稱
- `username`: (字串) SOCKS5 代理的認證使用者名稱  
- `password`: (字串) SOCKS5 代理的認證密碼
- `port`: (數字) 為此代理服務分配的對外連接埠
- `socks5_connection`: (字串) SOCKS5 的連線資訊 URL

## 使用方法

1. 編輯 `config.json` 文件，配置您的代理服務資訊
2. 執行部署腳本：
   ```bash
   sudo ./multi-deploy.sh deploy-socks5
   ```
   
   或指定自定義配置文件：
   ```bash
   sudo ./multi-deploy.sh deploy-socks5 my-config.json
   ```

## 範例配置

```json
[
  {
    "container_name": "socks_proxy_01",
    "username": "user1",
    "password": "password123",
    "port": 1080,
    "socks5_connection": "socks5://user1:pass1@proxy1.example.com:1080"
  },
  {
    "container_name": "socks_proxy_02", 
    "username": "user2",
    "password": "password456",
    "port": 1081,
    "socks5_connection": "socks5://user2:pass2@proxy2.example.com:1080"
  }
]
```

## multi-deploy.sh 用法及參數

### 基本用法

```bash
sudo ./multi-deploy.sh [指令] [選項]
```

**注意**: 所有操作都需要 root 權限，請使用 sudo 執行。

### 部署指令

| 指令 | 參數 | 說明 |
|------|------|------|
| `check-docker` | `[auto\|cn]` | 檢查 Docker 環境 (auto=自動安裝, cn=中國源) |
| `install-docker` | `[cn]` | 安裝 Docker (cn=使用中國源) |
| `create-macvlan` | `[子網] [網關] [接口] [網路名稱]` | 創建 MACVLAN 網路 |
| `deploy-http` | - | 部署 HTTP 代理多實例 |
| `deploy-macvlan` | - | 部署 MACVLAN 多實例 |
| `deploy-socks5` | `[配置文件]` | 部署 SOCKS5 多實例 (預設: config.json) |

### 實例管理指令

| 指令 | 參數 | 說明 |
|------|------|------|
| `status` | - | 查看所有實例狀態 |
| `logs` | - | 查看實例日誌 |
| `start-all` | - | 啟動所有已停止的實例 |
| `start` | `<實例名稱>` | 啟動指定實例 |
| `restart-all` | - | 重啟所有運行中的實例 |
| `restart` | `<實例名稱>` | 重啟指定實例 |
| `stop-all` | - | 停止所有實例 |
| `stop` | `<實例名稱>` | 停止指定實例 |
| `help` | - | 顯示幫助信息 |

### 使用範例

#### 環境檢查與安裝
```bash
# 檢查 Docker 環境並自動安裝（使用中國源）
sudo ./multi-deploy.sh check-docker cn

# 手動安裝 Docker
sudo ./multi-deploy.sh install-docker cn
```

#### SOCKS5 部署
```bash
# 使用預設配置文件部署 SOCKS5 實例（會自動啟動）
sudo ./multi-deploy.sh deploy-socks5

# 使用自定義配置文件部署 SOCKS5 實例
sudo ./multi-deploy.sh deploy-socks5 my-config.json
```

#### 實例管理
```bash
# 查看所有實例狀態
sudo ./multi-deploy.sh status

# 啟動指定的已停止實例
sudo ./multi-deploy.sh start socks_proxy_01

# 啟動所有已停止的實例
sudo ./multi-deploy.sh start-all

# 重啟指定實例
sudo ./multi-deploy.sh restart socks_proxy_01

# 重啟所有運行中的實例
sudo ./multi-deploy.sh restart-all

# 停止指定實例
sudo ./multi-deploy.sh stop socks_proxy_01

# 停止所有實例
sudo ./multi-deploy.sh stop-all

# 查看實例日誌
sudo ./multi-deploy.sh logs
```

#### 互動選單模式
```bash
# 不帶任何參數運行，顯示互動選單
sudo ./multi-deploy.sh
```

### 重要注意事項

- **首次使用前建議執行 `check-docker` 檢查環境**
- **SOCKS5 部署需要有效的 config.json 配置文件**
- **部署操作會創建並自動啟動新實例**
- **啟動/停止操作管理已部署的實例，不會重新創建容器**
- **重啟操作會保持實例配置不變**

## 配置文件注意事項

- 確保每個容器名稱都是唯一的
- 確保每個端口都是唯一的，避免衝突
- SOCKS5 連線 URL 格式：`socks5://[username:password@]host:port`
- 請確保您的 SOCKS5 代理服務器可以正常訪問

## 實例管理

### 部署 vs 啟動/停止

**部署 (Deploy)**：
- 創建新的容器並自動啟動
- 部署完成後，實例會自動運行
- 用於首次創建實例

**啟動/停止 (Start/Stop)**：
- 管理已部署的實例
- 不會重新創建容器，只是啟動或停止現有容器
- 用於日常實例管理

### 實例管理指令

```bash
# 查看所有實例狀態
sudo ./multi-deploy.sh status

# 啟動指定實例
sudo ./multi-deploy.sh start socks_proxy_01

# 啟動所有已停止的實例
sudo ./multi-deploy.sh start-all

# 停止指定實例
sudo ./multi-deploy.sh stop socks_proxy_01

# 停止所有實例
sudo ./multi-deploy.sh stop-all

# 重啟指定實例
sudo ./multi-deploy.sh restart socks_proxy_01

# 重啟所有運行中的實例
sudo ./multi-deploy.sh restart-all

# 查看實例日誌
sudo ./multi-deploy.sh logs
```

### 常見使用流程

1. **首次部署**：
   ```bash
   sudo ./multi-deploy.sh deploy-socks5
   ```
   部署完成後，實例會自動啟動並運行。

2. **日常管理**：
   - 如果需要停止實例：`sudo ./multi-deploy.sh stop-all`
   - 如果需要重新啟動：`sudo ./multi-deploy.sh start-all`
   - 查看運行狀態：`sudo ./multi-deploy.sh status`

3. **故障排除**：
   - 查看日誌：`sudo ./multi-deploy.sh logs`
   - 重啟問題實例：`sudo ./multi-deploy.sh restart <實例名稱>`