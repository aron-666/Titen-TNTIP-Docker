#!/bin/bash

# TNTIP 多實例部署管理腳本
# 
# 功能介紹：
# - 檢查及安裝 Docker 環境
# - 批量部署 SOCKS5 代理實例
# - 啟動、停止和管理多個實例
# - 查看實例狀態和日誌
# 
# 使用方法：
#   sudo ./multi-deploy.sh                      # 顯示互動選單
#   sudo ./multi-deploy.sh deploy-socks5       # 使用預設配置部署 SOCKS5 實例
#   sudo ./multi-deploy.sh deploy-socks5 config.json  # 使用自定義配置文件
#   sudo ./multi-deploy.sh status              # 查看所有實例狀態
#   sudo ./multi-deploy.sh logs               # 查看實例日誌
#   sudo ./multi-deploy.sh stop-all           # 停止所有實例
#
# 詳細配置說明請參考: docs/Socks5_Config_Readme.md

# 顏色定義
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 檢查 root 權限
check_root_privileges() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}錯誤: 此腳本需要 root 權限才能執行${NC}"
        echo -e "${YELLOW}請使用 sudo 或以 root 用戶身份運行此腳本${NC}"
        exit 1
    fi
    echo -e "${GREEN}已確認 root 權限${NC}"
}

# 添加重試函數
retry() {
    local command="$1"
    local description="$2"
    local max_attempts=3
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        echo -e "${BLUE}嘗試 $attempt/$max_attempts: $description${NC}"
        eval $command && break
        echo -e "${YELLOW}嘗試 $attempt/$max_attempts 失敗，稍等後重試...${NC}"
        sleep 3
        attempt=$((attempt + 1))
    done
    
    if [[ $attempt -gt $max_attempts ]]; then
        echo -e "${RED}錯誤: 在 $max_attempts 次嘗試後，$description 操作失敗${NC}"
        return 1
    fi
    return 0
}

# 檢查 Docker 環境
check_docker_environment() {
    local install_option="${1:-ask}"
    
    echo -e "${BLUE}檢查 Docker 環境...${NC}"
    
    # 檢查 Docker 是否已安裝
    if ! command -v docker &> /dev/null; then
        echo -e "${RED}Docker 未安裝${NC}"
        if [[ "$install_option" == "true" || "$install_option" == "cn" ]]; then
            install_docker "$install_option"
        else
            read -p "是否現在安裝 Docker? (y/n): " confirm
            if [[ $confirm == [yY] || $confirm == [yY][eE][sS] ]]; then
                install_docker "false"
            else
                echo -e "${RED}TNTIP 服務需要 Docker，請先安裝 Docker${NC}"
                exit 1
            fi
        fi
    else
        echo -e "${GREEN}Docker 已安裝${NC}"
    fi
    
    # 檢查 Docker 服務狀態
    if ! systemctl is-active --quiet docker; then
        echo -e "${YELLOW}Docker 服務未運行，正在啟動...${NC}"
        systemctl start docker
        if [[ $? -eq 0 ]]; then
            echo -e "${GREEN}Docker 服務已啟動${NC}"
        else
            echo -e "${RED}無法啟動 Docker 服務${NC}"
            exit 1
        fi
    else
        echo -e "${GREEN}Docker 服務運行正常${NC}"
    fi
    
    # 檢查 Docker Compose 是否已可用
    if ! docker compose version &> /dev/null; then
        echo -e "${YELLOW}警告: 無法使用 Docker Compose。請確保您安裝的是最新版本的 Docker。${NC}"
        exit 1
    else
        echo -e "${GREEN}Docker Compose 已可用${NC}"
    fi
}

# 使用中國地區源安裝 Docker
install_docker_cn() {
    echo -e "${BLUE}使用中國地區源安裝 Docker...${NC}"
    
    # 檢測 Linux 發行版
    local ID=""
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        ID=$ID
    elif [ -f /etc/lsb-release ]; then
        . /etc/lsb-release
        ID=$DISTRIB_ID
    else
        echo -e "${RED}無法識別的 Linux 發行版${NC}"
        exit 1
    fi
    
    echo -e "${BLUE}檢測到 Linux 發行版: $ID${NC}"
    
    if [[ "$ID" == "ubuntu" || "$ID" == "debian" ]]; then
        # Ubuntu/Debian 下使用阿里云 Docker 源安装
        apt update -y
        apt install -y apt-transport-https ca-certificates curl gnupg lsb-release
        curl -fsSL https://mirrors.aliyun.com/docker-ce/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://mirrors.aliyun.com/docker-ce/linux/ubuntu $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list
        apt update -y
        retry "apt install -y docker-ce docker-ce-cli containerd.io" "安裝 Docker"
    elif [[ "$ID" == "centos" || "$ID" == "rhel" ]]; then
        # CentOS/RHEL 下使用阿里云 Docker 源安装
        yum install -y yum-utils device-mapper-persistent-data lvm2
        yum-config-manager --add-repo https://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo
        retry "yum install -y docker-ce docker-ce-cli containerd.io" "安裝 Docker"
        systemctl enable docker
        systemctl start docker
    elif [[ "$ID" == "fedora" ]]; then
        # Fedora 下使用 dnf 安装
        dnf install -y yum-utils device-mapper-persistent-data lvm2
        dnf config-manager --add-repo https://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo
        retry "dnf install -y docker-ce docker-ce-cli containerd.io" "安裝 Docker"
        systemctl enable docker
        systemctl start docker
    else
        echo -e "${RED}不支持的發行版: $ID${NC}"
        exit 1
    fi
    
    # 修改 Docker 源（設置鏡像加速器）
    echo -e "${BLUE}修改 Docker 源...${NC}"
    mkdir -p /etc/docker
    cat > /etc/docker/daemon.json <<EOF
{
  "registry-mirrors": ["https://docker.dadunode.com"]
}
EOF
    retry "systemctl restart docker" "重啟 Docker"
    
    # 將當前用戶加入 docker 群組
    usermod -aG docker $USER
    echo -e "${GREEN}Docker 安裝完成！${NC}"
    echo -e "${GREEN}已設置 Docker 中國鏡像加速器${NC}"
}

# 安裝 Docker (根據選擇的區域)
install_docker() {
    local region="international"
    local install_option="$1"
    
    # 如果明確指定了中國區域安裝
    if [[ "$install_option" == "cn" ]]; then
        region="cn"
    else
        # 如果未指定區域，詢問用戶
        echo -e "${BLUE}請選擇 Docker 安裝源:${NC}"
        echo "1. 國際源 (默認)"
        echo "2. 中國源 (阿里雲)"
        read -p "請選擇 [1/2]: " choice
        case $choice in
            2)
                region="cn"
                ;;
            *)
                region="international"
                ;;
        esac
    fi
    
    echo -e "${BLUE}正在安裝 Docker (使用${region}源)...${NC}"
    if [[ "$region" == "cn" ]]; then
        install_docker_cn
        return $?
    fi
    
    # 檢測作業系統類型（國際版安裝）
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        # 使用官方安裝腳本
        curl -fsSL https://get.docker.com -o get-docker.sh
        sudo sh get-docker.sh
        sudo usermod -aG docker $USER
        systemctl enable docker
        systemctl start docker
        echo -e "${GREEN}Docker 安裝完成！${NC}"
        echo -e "${GREEN}此安裝包含了 Docker Compose 功能${NC}"
        # 移除安裝腳本
        rm get-docker.sh
    else
        echo -e "${RED}不支持的作業系統，請手動安裝 Docker${NC}"
        exit 1
    fi
}

# 創建 MACVLAN 網路
create_macvlan_network() {
    local network_name="${1:-tntip-macvlan}"
    local subnet="${2:-192.168.1.0/24}"
    local gateway="${3:-192.168.1.1}"
    local parent_interface="${4:-eth0}"
    
    echo -e "${BLUE}創建 MACVLAN 網路: $network_name${NC}"
    echo -e "${YELLOW}子網: $subnet${NC}"
    echo -e "${YELLOW}網關: $gateway${NC}"
    echo -e "${YELLOW}父接口: $parent_interface${NC}"
    
    if docker network ls | grep -q "$network_name"; then
        echo -e "${YELLOW}網路 $network_name 已存在${NC}"
        return 0
    fi
    
    docker network create -d macvlan \
        --subnet="$subnet" \
        --gateway="$gateway" \
        -o parent="$parent_interface" \
        "$network_name"
    
    if [[ $? -eq 0 ]]; then
        echo -e "${GREEN}MACVLAN 網路創建成功${NC}"
    else
        echo -e "${RED}MACVLAN 網路創建失敗${NC}"
        return 1
    fi
}

# 部署多個實例
deploy_multiple_instances() {
    echo -e "${BLUE}批量部署多個 TNTIP 實例${NC}"
    
    # 實例配置範例
    local instances=(
        "user1@example.com:pass1:50011:./data1:tntip-instance1:http://proxy1.example.com:8080"
        "user2@example.com:pass2:50012:./data2:tntip-instance2:http://proxy2.example.com:8080"
        "user3@example.com:pass3:50013:./data3:tntip-instance3:http://proxy3.example.com:8080"
    )
    
    echo -e "${YELLOW}注意: 請修改腳本中的實例配置以符合您的需求${NC}"
    read -p "是否繼續部署範例實例? (y/n): " confirm
    if [[ $confirm != [yY] && $confirm != [yY][eE][sS] ]]; then
        echo -e "${BLUE}部署已取消${NC}"
        return 0
    fi
    
    for instance in "${instances[@]}"; do
        IFS=':' read -r user pass port data_dir container_name proxy_host <<< "$instance"
        
        echo -e "${BLUE}部署實例: $container_name${NC}"
        
        # 創建實例目錄
        mkdir -p "$(dirname "$data_dir")"
        
        # 啟動實例
        ./tntip.sh start \
            -u "$user" \
            -p "$pass" \
            --port "$port" \
            -d "$data_dir" \
            --container-name "$container_name" \
            --proxy-enable true \
            --proxy-host "$proxy_host"
        
        if [[ $? -eq 0 ]]; then
            echo -e "${GREEN}實例 $container_name 部署成功${NC}"
        else
            echo -e "${RED}實例 $container_name 部署失敗${NC}"
        fi
        
        sleep 5
    done
}

# 部署 MACVLAN 實例
deploy_macvlan_instances() {
    echo -e "${BLUE}部署 MACVLAN 多實例${NC}"
    
    # 檢查是否已創建 MACVLAN 網路
    if ! docker network ls | grep -q "tntip-macvlan"; then
        echo -e "${YELLOW}需要先創建 MACVLAN 網路${NC}"
        read -p "請輸入子網 (預設: 192.168.1.0/24): " subnet
        read -p "請輸入網關 (預設: 192.168.1.1): " gateway
        read -p "請輸入父接口 (預設: eth0): " parent_interface
        
        create_macvlan_network "tntip-macvlan" "${subnet:-192.168.1.0/24}" "${gateway:-192.168.1.1}" "${parent_interface:-eth0}"
        if [[ $? -ne 0 ]]; then
            echo -e "${RED}MACVLAN 網路創建失敗，無法繼續${NC}"
            return 1
        fi
    fi
    
    # MACVLAN 實例配置
    local macvlan_instances=(
        "user1@example.com:pass1:./data1:tntip-macvlan1:192.168.1.10"
        "user2@example.com:pass2:./data2:tntip-macvlan2:192.168.1.11"
        "user3@example.com:pass3:./data3:tntip-macvlan3:192.168.1.12"
    )
    
    echo -e "${YELLOW}注意: 請修改腳本中的 IP 配置以符合您的網路環境${NC}"
    read -p "是否繼續部署 MACVLAN 實例? (y/n): " confirm
    if [[ $confirm != [yY] && $confirm != [yY][eE][sS] ]]; then
        echo -e "${BLUE}部署已取消${NC}"
        return 0
    fi
    
    for instance in "${macvlan_instances[@]}"; do
        IFS=':' read -r user pass data_dir container_name static_ip <<< "$instance"
        
        echo -e "${BLUE}部署 MACVLAN 實例: $container_name (IP: $static_ip)${NC}"
        
        # 創建實例目錄
        mkdir -p "$(dirname "$data_dir")"
        
        # 啟動 MACVLAN 實例
        ./tntip.sh start \
            -u "$user" \
            -p "$pass" \
            -d "$data_dir" \
            --container-name "$container_name" \
            --network-mode macvlan \
            --network-name tntip-macvlan \
            --static-ip "$static_ip"
        
        if [[ $? -eq 0 ]]; then
            echo -e "${GREEN}MACVLAN 實例 $container_name 部署成功${NC}"
        else
            echo -e "${RED}MACVLAN 實例 $container_name 部署失敗${NC}"
        fi
        
        sleep 5
    done
}

# 部署 SOCKS5 實例 (從 JSON 配置文件讀取)
deploy_socks5_instances() {
    echo -e "${BLUE}部署 SOCKS5 多實例${NC}"
    
    # 首先檢查 Docker 環境
    check_docker_environment "ask"
    if [[ $? -ne 0 ]]; then
        echo -e "${RED}Docker 環境檢查失敗，無法繼續部署${NC}"
        return 1
    fi
    
    local config_file="${1:-config.json}"
    
    # 檢查配置文件是否存在
    if [[ ! -f "$config_file" ]]; then
        echo -e "${RED}錯誤: 配置文件 $config_file 不存在${NC}"
        echo -e "${YELLOW}請先創建配置文件，範例：${NC}"
        cat << 'EOF'
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
EOF
        echo -e "${YELLOW}詳細配置說明請參考: docs/Socks5_Config_Readme.md${NC}"
        return 1
    fi
    
    # 檢查 jq 是否可用
    if ! command -v jq &> /dev/null; then
        echo -e "${RED}錯誤: 需要安裝 jq 來解析 JSON 配置文件${NC}"
        echo -e "${YELLOW}正在安裝 jq...${NC}"
        
        # 嘗試自動安裝 jq
        if command -v apt &> /dev/null; then
            apt update && apt install -y jq
        elif command -v yum &> /dev/null; then
            yum install -y jq
        elif command -v dnf &> /dev/null; then
            dnf install -y jq
        else
            echo -e "${RED}無法自動安裝 jq，請手動安裝後再試${NC}"
            return 1
        fi
        
        # 再次檢查 jq 是否可用
        if ! command -v jq &> /dev/null; then
            echo -e "${RED}jq 安裝失敗${NC}"
            return 1
        fi
        echo -e "${GREEN}jq 安裝成功${NC}"
    fi
    
    # 驗證 JSON 格式
    if ! jq empty "$config_file" 2>/dev/null; then
        echo -e "${RED}錯誤: 配置文件 $config_file 不是有效的 JSON 格式${NC}"
        echo -e "${YELLOW}請檢查配置文件語法，詳細說明請參考: docs/Socks5_Config_Readme.md${NC}"
        return 1
    fi
    
    # 獲取實例數量
    local instance_count=$(jq '. | length' "$config_file")
    echo -e "${BLUE}從 $config_file 讀取到 $instance_count 個 SOCKS5 代理配置${NC}"
    
    if [[ $instance_count -eq 0 ]]; then
        echo -e "${YELLOW}配置文件中沒有找到任何實例配置${NC}"
        return 1
    fi
    
    # 顯示將要部署的配置
    echo -e "${YELLOW}將要部署的實例:${NC}"
    jq -r '.[] | "  - 容器名稱: \(.container_name), 用戶: \(.username), 端口: \(.port)"' "$config_file"
    
    read -p "是否繼續部署這些 SOCKS5 實例? (y/n): " confirm
    if [[ $confirm != [yY] && $confirm != [yY][eE][sS] ]]; then
        echo -e "${BLUE}部署已取消${NC}"
        return 0
    fi
    
    # 逐一處理每個實例
    local success_count=0
    local failed_count=0
    
    for i in $(seq 0 $((instance_count - 1))); do
        # 從 JSON 提取實例配置
        local container_name=$(jq -r ".[$i].container_name" "$config_file")
        local username=$(jq -r ".[$i].username" "$config_file")
        local password=$(jq -r ".[$i].password" "$config_file")
        local port=$(jq -r ".[$i].port" "$config_file")
        local socks5_connection=$(jq -r ".[$i].socks5_connection" "$config_file")
        
        echo -e "${BLUE}部署 SOCKS5 實例 $((i + 1))/$instance_count: $container_name${NC}"
        
        # 檢查容器名稱是否已存在
        if docker ps -a --format "{{.Names}}" | grep -q "^${container_name}$"; then
            echo -e "${YELLOW}容器 $container_name 已存在，停止並移除舊容器...${NC}"
            docker stop "$container_name" >/dev/null 2>&1
            docker rm "$container_name" >/dev/null 2>&1
        fi
        
        # 檢查端口是否被佔用
        if netstat -tuln 2>/dev/null | grep -q ":$port "; then
            echo -e "${YELLOW}警告: 端口 $port 可能已被佔用${NC}"
        fi
        
        # 創建實例專用的數據目錄
        local data_dir="./data_${container_name}"
        mkdir -p "$data_dir"
        
        # 啟動 SOCKS5 實例
        echo -e "${BLUE}啟動容器 $container_name (端口: $port)...${NC}"
        if ./tntip.sh start \
            -u "$username@example.com" \
            -p "$password" \
            -d "$data_dir" \
            --container-name "$container_name" \
            --port "$port" \
            --socks5-enable true \
            --socks5-proxy "$socks5_connection" >/dev/null 2>&1; then
            echo -e "${GREEN}✓ SOCKS5 實例 $container_name 部署成功${NC}"
            ((success_count++))
        else
            echo -e "${RED}✗ SOCKS5 實例 $container_name 部署失敗${NC}"
            ((failed_count++))
        fi
        
        # 等待容器啟動
        sleep 3
        
        # 驗證容器是否正在運行
        if docker ps --format "{{.Names}}" | grep -q "^${container_name}$"; then
            echo -e "${GREEN}  容器 $container_name 運行正常${NC}"
        else
            echo -e "${RED}  容器 $container_name 未正常啟動，請檢查日誌${NC}"
            ((failed_count++))
            ((success_count--))
        fi
        
        echo
    done
    
    # 顯示部署結果摘要
    echo -e "${BLUE}======== 部署結果摘要 ========${NC}"
    echo -e "${GREEN}成功部署並啟動: $success_count 個實例${NC}"
    if [[ $failed_count -gt 0 ]]; then
        echo -e "${RED}部署失敗: $failed_count 個實例${NC}"
    fi
    echo -e "${BLUE}=============================${NC}"
    
    if [[ $success_count -gt 0 ]]; then
        echo -e "${GREEN}部署完成！已成功創建並啟動 $success_count 個 SOCKS5 代理實例。${NC}"
        echo -e "${YELLOW}實例現在正在運行中，您可以使用以下命令管理它們:${NC}"
        echo -e "${YELLOW}  查看狀態: $0 status${NC}"
        echo -e "${YELLOW}  查看日誌: $0 logs${NC}"
        echo -e "${YELLOW}  停止實例: $0 stop <實例名稱>${NC}"
        echo -e "${YELLOW}  停止所有: $0 stop-all${NC}"
        echo -e "${YELLOW}  啟動實例: $0 start <實例名稱>${NC}"
        echo -e "${YELLOW}  啟動所有: $0 start-all${NC}"
        echo
        echo -e "${BLUE}注意: 如果您停止了實例，可以使用 start 命令重新啟動，無需重新部署。${NC}"
    else
        echo -e "${RED}部署失敗！沒有成功創建任何實例。請檢查配置文件和日誌。${NC}"
    fi
}

# 查看所有實例狀態
show_all_instances() {
    echo -e "${BLUE}查看所有 TNTIP 實例狀態${NC}"
    
    # 檢查是否有運行中的 TNTIP 容器
    local tntip_containers=$(docker ps -f name=tntip --format "{{.Names}}")
    local tun2proxy_containers=$(docker ps -f name=tun2proxy --format "{{.Names}}")
    local socks_containers=$(docker ps -f name=socks --format "{{.Names}}")
    
    if [[ -z "$tntip_containers" && -z "$tun2proxy_containers" && -z "$socks_containers" ]]; then
        echo -e "${YELLOW}沒有發現運行中的 TNTIP 相關容器${NC}"
        echo -e "${BLUE}檢查所有已停止的容器...${NC}"
        docker ps -a -f name=tntip --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
        docker ps -a -f name=tun2proxy --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
        docker ps -a -f name=socks --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
        return 0
    fi
    
    # 顯示詳細的容器信息
    echo -e "${YELLOW}正在運行的 TNTIP 容器:${NC}"
    if [[ -n "$tntip_containers" ]]; then
        docker ps -f name=tntip --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}\t{{.CreatedAt}}"
    else
        echo "  無運行中的 TNTIP 容器"
    fi
    
    echo
    echo -e "${YELLOW}正在運行的 tun2proxy 容器:${NC}"
    if [[ -n "$tun2proxy_containers" ]]; then
        docker ps -f name=tun2proxy --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}\t{{.CreatedAt}}"
    else
        echo "  無運行中的 tun2proxy 容器"
    fi
    
    echo
    echo -e "${YELLOW}正在運行的 SOCKS5 容器:${NC}"
    if [[ -n "$socks_containers" ]]; then
        docker ps -f name=socks --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}\t{{.CreatedAt}}"
    else
        echo "  無運行中的 SOCKS5 容器"
    fi
    
    # 顯示系統資源使用情況
    echo
    echo -e "${BLUE}系統資源使用情況:${NC}"
    docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}" $(docker ps -f name=tntip -f name=tun2proxy -f name=socks -q) 2>/dev/null || echo "  無法獲取資源統計信息"
}

# 查看實例日誌
show_logs() {
    echo -e "${BLUE}查看 TNTIP 實例日誌${NC}"
    
    # 獲取所有運行中的相關容器
    local containers=$(docker ps -f name=tntip -f name=tun2proxy -f name=socks --format "{{.Names}}")
    
    if [[ -z "$containers" ]]; then
        echo -e "${YELLOW}沒有發現運行中的 TNTIP 相關容器${NC}"
        echo -e "${BLUE}嘗試查看最近停止的容器日誌...${NC}"
        containers=$(docker ps -a -f name=tntip -f name=tun2proxy -f name=socks --format "{{.Names}}" | head -5)
    fi
    
    if [[ -z "$containers" ]]; then
        echo -e "${RED}沒有找到任何 TNTIP 相關容器${NC}"
        return 1
    fi
    
    # 如果有多個容器，讓用戶選擇
    local container_array=($containers)
    if [[ ${#container_array[@]} -gt 1 ]]; then
        echo -e "${YELLOW}發現多個容器，請選擇要查看日誌的容器:${NC}"
        for i in "${!container_array[@]}"; do
            echo "$((i+1)). ${container_array[$i]}"
        done
        echo "$((${#container_array[@]}+1)). 查看所有容器日誌"
        
        read -p "請選擇 [1-$((${#container_array[@]}+1))]: " choice
        
        if [[ "$choice" -eq $((${#container_array[@]}+1)) ]]; then
            # 查看所有容器日誌
            echo -e "${BLUE}顯示所有容器的最新日誌 (按 Ctrl+C 停止)...${NC}"
            for container in "${container_array[@]}"; do
                echo -e "${YELLOW}=== $container 的日誌 ===${NC}"
                docker logs --tail 20 "$container" 2>/dev/null || echo "無法獲取 $container 的日誌"
                echo
            done
        elif [[ "$choice" -ge 1 && "$choice" -le ${#container_array[@]} ]]; then
            # 查看選定容器的日誌
            local selected_container="${container_array[$((choice-1))]}"
            echo -e "${BLUE}顯示 $selected_container 的實時日誌 (按 Ctrl+C 停止)...${NC}"
            docker logs --tail 50 --follow "$selected_container" 2>/dev/null || echo "無法獲取 $selected_container 的日誌"
        else
            echo -e "${RED}無效的選擇${NC}"
            return 1
        fi
    else
        # 只有一個容器，直接顯示日誌
        local container="${container_array[0]}"
        echo -e "${BLUE}顯示 $container 的實時日誌 (按 Ctrl+C 停止)...${NC}"
        docker logs --tail 50 --follow "$container" 2>/dev/null || echo "無法獲取 $container 的日誌"
    fi
}

# 停止所有實例
stop_all_instances() {
    echo -e "${RED}停止所有 TNTIP 實例${NC}"
    
    # 檢查是否有運行中的容器
    local running_containers=$(docker ps -f name=tntip -f name=tun2proxy -f name=socks --format "{{.Names}}")
    
    if [[ -z "$running_containers" ]]; then
        echo -e "${YELLOW}沒有發現運行中的 TNTIP 相關容器${NC}"
        return 0
    fi
    
    echo -e "${YELLOW}發現以下運行中的容器:${NC}"
    echo "$running_containers"
    echo
    
    read -p "確定要停止所有 TNTIP 實例嗎? (y/n): " confirm
    if [[ $confirm != [yY] && $confirm != [yY][eE][sS] ]]; then
        echo -e "${BLUE}操作已取消${NC}"
        return 0
    fi
    
    # 優雅停止所有容器
    echo -e "${BLUE}正在優雅停止容器...${NC}"
    local container_array=($running_containers)
    local failed_containers=()
    
    for container in "${container_array[@]}"; do
        echo -e "${BLUE}停止容器: $container${NC}"
        if docker stop "$container" --time 30 >/dev/null 2>&1; then
            echo -e "${GREEN}✓ $container 已停止${NC}"
        else
            echo -e "${YELLOW}⚠ $container 停止失敗，嘗試強制停止...${NC}"
            if docker kill "$container" >/dev/null 2>&1; then
                echo -e "${GREEN}✓ $container 已強制停止${NC}"
            else
                echo -e "${RED}✗ $container 無法停止${NC}"
                failed_containers+=("$container")
            fi
        fi
    done
    
    if [[ ${#failed_containers[@]} -eq 0 ]]; then
        echo -e "${GREEN}所有實例已成功停止${NC}"
    else
        echo -e "${YELLOW}以下容器停止失敗:${NC}"
        printf '%s\n' "${failed_containers[@]}"
        echo -e "${BLUE}您可以嘗試手動停止: docker stop 容器名${NC}"
    fi
    
    # 清理已停止的容器 (可選)
    read -p "是否要清理已停止的容器? (y/n): " cleanup
    if [[ $cleanup == [yY] || $cleanup == [yY][eE][sS] ]]; then
        echo -e "${BLUE}清理已停止的容器...${NC}"
        docker container prune -f
        echo -e "${GREEN}清理完成${NC}"
    fi
}

# 啟動指定實例
start_instance() {
    local instance_name="$1"
    
    if [[ -z "$instance_name" ]]; then
        echo -e "${RED}錯誤: 請指定要啟動的實例名稱${NC}"
        echo -e "${YELLOW}用法: $0 start <實例名稱>${NC}"
        return 1
    fi
    
    echo -e "${BLUE}啟動實例: $instance_name${NC}"
    
    # 檢查容器是否存在
    if ! docker ps -a --format "{{.Names}}" | grep -q "^${instance_name}$"; then
        echo -e "${RED}錯誤: 容器 $instance_name 不存在${NC}"
        echo -e "${YELLOW}請先使用 deploy-socks5 命令部署實例${NC}"
        return 1
    fi
    
    # 檢查容器是否已經在運行
    if docker ps --format "{{.Names}}" | grep -q "^${instance_name}$"; then
        echo -e "${YELLOW}容器 $instance_name 已經在運行${NC}"
        return 0
    fi
    
    # 啟動容器
    if docker start "$instance_name" >/dev/null 2>&1; then
        echo -e "${GREEN}實例 $instance_name 已啟動${NC}"
        
        # 等待容器啟動並檢查狀態
        sleep 3
        if docker ps --format "{{.Names}}" | grep -q "^${instance_name}$"; then
            echo -e "${GREEN}✓ 容器 $instance_name 運行正常${NC}"
        else
            echo -e "${RED}✗ 容器 $instance_name 啟動失敗，請檢查日誌${NC}"
            return 1
        fi
    else
        echo -e "${RED}無法啟動實例 $instance_name${NC}"
        return 1
    fi
}

# 啟動所有已停止的實例
start_all_instances() {
    echo -e "${BLUE}啟動所有已停止的 TNTIP 實例${NC}"
    
    # 獲取所有已停止的 TNTIP 相關容器
    local stopped_containers=$(docker ps -a -f status=exited -f name=tntip --format "{{.Names}}")
    local stopped_tun2proxy=$(docker ps -a -f status=exited -f name=tun2proxy --format "{{.Names}}")
    local stopped_socks=$(docker ps -a -f status=exited -f name=socks --format "{{.Names}}")
    
    # 合併所有停止的容器
    local all_stopped="$stopped_containers $stopped_tun2proxy $stopped_socks"
    all_stopped=$(echo "$all_stopped" | tr ' ' '\n' | grep -v '^$' | sort -u)
    
    if [[ -z "$all_stopped" ]]; then
        echo -e "${YELLOW}沒有發現已停止的 TNTIP 相關容器${NC}"
        return 0
    fi
    
    echo -e "${YELLOW}發現以下已停止的容器:${NC}"
    echo "$all_stopped"
    echo
    
    read -p "確定要啟動所有已停止的實例嗎? (y/n): " confirm
    if [[ $confirm != [yY] && $confirm != [yY][eE][sS] ]]; then
        echo -e "${BLUE}操作已取消${NC}"
        return 0
    fi
    
    local success_count=0
    local failed_count=0
    
    # 啟動所有停止的容器
    echo -e "${BLUE}正在啟動容器...${NC}"
    for container in $all_stopped; do
        echo -e "${BLUE}啟動容器: $container${NC}"
        if docker start "$container" >/dev/null 2>&1; then
            echo -e "${GREEN}✓ $container 已啟動${NC}"
            ((success_count++))
        else
            echo -e "${RED}✗ $container 啟動失敗${NC}"
            ((failed_count++))
        fi
    done
    
    echo
    echo -e "${BLUE}======== 啟動結果摘要 ========${NC}"
    echo -e "${GREEN}成功啟動: $success_count 個實例${NC}"
    if [[ $failed_count -gt 0 ]]; then
        echo -e "${RED}啟動失敗: $failed_count 個實例${NC}"
    fi
    echo -e "${BLUE}=============================${NC}"
    
    if [[ $success_count -gt 0 ]]; then
        echo -e "${GREEN}您可以使用以下命令查看實例狀態:${NC}"
        echo -e "${YELLOW}  $0 status${NC}"
    fi
}

# 重啟指定實例
restart_instance() {
    local instance_name="$1"
    
    if [[ -z "$instance_name" ]]; then
        echo -e "${RED}錯誤: 請指定要重啟的實例名稱${NC}"
        echo -e "${YELLOW}用法: $0 restart <實例名稱>${NC}"
        return 1
    fi
    
    echo -e "${BLUE}重啟實例: $instance_name${NC}"
    
    # 檢查容器是否存在
    if ! docker ps -a --format "{{.Names}}" | grep -q "^${instance_name}$"; then
        echo -e "${RED}錯誤: 容器 $instance_name 不存在${NC}"
        return 1
    fi
    
    # 重啟容器
    if docker restart "$instance_name" >/dev/null 2>&1; then
        echo -e "${GREEN}實例 $instance_name 已重啟${NC}"
        
        # 等待容器啟動並檢查狀態
        sleep 3
        if docker ps --format "{{.Names}}" | grep -q "^${instance_name}$"; then
            echo -e "${GREEN}✓ 容器 $instance_name 運行正常${NC}"
        else
            echo -e "${RED}✗ 容器 $instance_name 重啟後未正常運行，請檢查日誌${NC}"
            return 1
        fi
    else
        echo -e "${RED}無法重啟實例 $instance_name${NC}"
        return 1
    fi
}

# 重啟所有運行中的實例
restart_all_instances() {
    echo -e "${BLUE}重啟所有運行中的 TNTIP 實例${NC}"
    
    # 獲取所有運行中的 TNTIP 相關容器
    local running_containers=$(docker ps -f name=tntip -f name=tun2proxy -f name=socks --format "{{.Names}}")
    
    if [[ -z "$running_containers" ]]; then
        echo -e "${YELLOW}沒有發現運行中的 TNTIP 相關容器${NC}"
        return 0
    fi
    
    echo -e "${YELLOW}發現以下運行中的容器:${NC}"
    echo "$running_containers"
    echo
    
    read -p "確定要重啟所有運行中的實例嗎? (y/n): " confirm
    if [[ $confirm != [yY] && $confirm != [yY][eE][sS] ]]; then
        echo -e "${BLUE}操作已取消${NC}"
        return 0
    fi
    
    local success_count=0
    local failed_count=0
    
    # 重啟所有運行的容器
    echo -e "${BLUE}正在重啟容器...${NC}"
    local container_array=($running_containers)
    for container in "${container_array[@]}"; do
        echo -e "${BLUE}重啟容器: $container${NC}"
        if docker restart "$container" >/dev/null 2>&1; then
            echo -e "${GREEN}✓ $container 已重啟${NC}"
            ((success_count++))
        else
            echo -e "${RED}✗ $container 重啟失敗${NC}"
            ((failed_count++))
        fi
    done
    
    echo
    echo -e "${BLUE}======== 重啟結果摘要 ========${NC}"
    echo -e "${GREEN}成功重啟: $success_count 個實例${NC}"
    if [[ $failed_count -gt 0 ]]; then
        echo -e "${RED}重啟失敗: $failed_count 個實例${NC}"
    fi
    echo -e "${BLUE}=============================${NC}"
}

# 停止指定實例
stop_instance() {
    local instance_name="$1"
    
    if [[ -z "$instance_name" ]]; then
        echo -e "${RED}錯誤: 請指定要停止的實例名稱${NC}"
        echo -e "${YELLOW}用法: $0 stop <實例名稱>${NC}"
        return 1
    fi
    
    echo -e "${BLUE}停止實例: $instance_name${NC}"
    
    # 檢查容器是否存在且正在運行
    if ! docker ps --format "{{.Names}}" | grep -q "^${instance_name}$"; then
        echo -e "${YELLOW}容器 $instance_name 未運行或不存在${NC}"
        return 1
    fi
    
    # 停止容器
    if docker stop "$instance_name" --time 30 >/dev/null 2>&1; then
        echo -e "${GREEN}實例 $instance_name 已停止${NC}"
    else
        echo -e "${YELLOW}優雅停止失敗，嘗試強制停止...${NC}"
        if docker kill "$instance_name" >/dev/null 2>&1; then
            echo -e "${GREEN}實例 $instance_name 已強制停止${NC}"
        else
            echo -e "${RED}無法停止實例 $instance_name${NC}"
            return 1
        fi
    fi
}

# 顯示選單
show_menu() {
    clear
    echo "========================================"
    echo "        TNTIP 多實例部署管理選單        "
    echo "========================================"
    echo "1. 檢查 Docker 環境"
    echo "2. 創建 MACVLAN 網路"
    echo "3. 部署 HTTP 代理多實例"
    echo "4. 部署 MACVLAN 多實例"
    echo "5. 部署 SOCKS5 多實例 (從 config.json)"
    echo "6. 查看所有實例狀態"
    echo "7. 查看實例日誌"
    echo "8. 啟動所有已停止的實例"
    echo "9. 啟動指定實例"
    echo "10. 重啟所有運行中的實例"
    echo "11. 重啟指定實例"
    echo "12. 停止所有實例"
    echo "13. 停止指定實例"
    echo "0. 退出"
    echo "========================================"
    echo -e "${BLUE}提示: 詳細配置說明請參考 docs/Socks5_Config_Readme.md${NC}"
    echo -e "${YELLOW}部署完成後，實例會自動啟動。您可以使用啟動/停止功能管理已部署的實例。${NC}"
    echo "========================================"
}

# 處理選單選擇
handle_menu_choice() {
    case "$1" in
        1)
            check_docker_environment "ask"
            ;;
        2)
            create_macvlan_network
            ;;
        3)
            deploy_multiple_instances
            ;;
        4)
            deploy_macvlan_instances
            ;;
        5)
            deploy_socks5_instances
            ;;
        6)
            show_all_instances
            ;;
        7)
            show_logs
            ;;
        8)
            start_all_instances
            ;;
        9)
            read -p "請輸入要啟動的實例名稱: " instance_name
            start_instance "$instance_name"
            ;;
        10)
            restart_all_instances
            ;;
        11)
            read -p "請輸入要重啟的實例名稱: " instance_name
            restart_instance "$instance_name"
            ;;
        12)
            stop_all_instances
            ;;
        13)
            read -p "請輸入要停止的實例名稱: " instance_name
            stop_instance "$instance_name"
            ;;
        0)
            echo "感謝使用！再見！"
            exit 0
            ;;
        *)
            echo -e "${RED}錯誤：無效的選擇，請重新輸入${NC}"
            ;;
    esac
    
    # 顯示「按任意鍵返回選單」提示（除非選擇了退出選項）
    if [[ "$1" != "0" ]]; then
        echo
        read -n 1 -s -r -p "按任意鍵返回選單..."
        echo
        show_menu
        read -p "請選擇操作 [0-13]: " choice
        handle_menu_choice "$choice"
    fi
}


# 主程序
main() {
    # 先檢查 root 權限
    check_root_privileges
    
    if [[ $# -eq 0 ]]; then
        # 無參數時顯示選單
        show_menu
        read -p "請選擇操作 [0-13]: " choice
        handle_menu_choice "$choice"
    else
        case "$1" in
            check-docker)
                check_docker_environment "${2:-ask}"
                ;;
            install-docker)
                install_docker "${2:-false}"
                ;;
            create-macvlan)
                create_macvlan_network "$2" "$3" "$4" "$5"
                ;;
            deploy-http)
                deploy_multiple_instances
                ;;
            deploy-macvlan)
                deploy_macvlan_instances
                ;;
            deploy-socks5)
                deploy_socks5_instances "$2"
                ;;
            status)
                show_all_instances
                ;;
            logs)
                show_logs
                ;;
            start-all)
                start_all_instances
                ;;
            start)
                if [[ -z "$2" ]]; then
                    echo -e "${RED}錯誤: 請指定要啟動的實例名稱${NC}"
                    echo -e "${YELLOW}用法: $0 start <實例名稱>${NC}"
                    exit 1
                fi
                start_instance "$2"
                ;;
            restart-all)
                restart_all_instances
                ;;
            restart)
                if [[ -z "$2" ]]; then
                    echo -e "${RED}錯誤: 請指定要重啟的實例名稱${NC}"
                    echo -e "${YELLOW}用法: $0 restart <實例名稱>${NC}"
                    exit 1
                fi
                restart_instance "$2"
                ;;
            stop-all)
                stop_all_instances
                ;;
            stop)
                if [[ -z "$2" ]]; then
                    echo -e "${RED}錯誤: 請指定要停止的實例名稱${NC}"
                    echo -e "${YELLOW}用法: $0 stop <實例名稱>${NC}"
                    exit 1
                fi
                stop_instance "$2"
                ;;
            help|--help|-h)
                show_help
                ;;
            *)
                echo -e "${RED}錯誤: 未知的指令 '$1'${NC}"
                echo
                show_help
                exit 1
                ;;
        esac
    fi
}

# 顯示幫助信息
show_help() {
    echo "用法: $0 [指令] [選項]"
    echo
    echo "功能說明："
    echo "  本腳本用於管理 TNTIP 多實例部署，支援 Docker 環境檢查、SOCKS5 代理批量部署等功能。"
    echo
    echo "部署指令："
    echo "  check-docker [auto|cn]              檢查 Docker 環境 (auto=自動安裝, cn=中國源)"
    echo "  install-docker [cn]                 安裝 Docker (cn=使用中國源)"
    echo "  create-macvlan [子網] [網關] [接口] [網路名稱]"
    echo "                                      創建 MACVLAN 網路"
    echo "  deploy-http                         部署 HTTP 代理多實例"
    echo "  deploy-macvlan                      部署 MACVLAN 多實例"
    echo "  deploy-socks5 [配置文件]            部署 SOCKS5 多實例 (預設: config.json)"
    echo
    echo "實例管理指令："
    echo "  status                              查看所有實例狀態"
    echo "  logs                                查看實例日誌"
    echo "  start-all                           啟動所有已停止的實例"
    echo "  start <實例名稱>                    啟動指定實例"
    echo "  restart-all                         重啟所有運行中的實例"
    echo "  restart <實例名稱>                  重啟指定實例"
    echo "  stop-all                            停止所有實例"
    echo "  stop <實例名稱>                     停止指定實例"
    echo "  help                                顯示此幫助信息"
    echo
    echo "範例："
    echo "  # 檢查 Docker 環境並自動安裝（使用中國源）"
    echo "  $0 check-docker cn"
    echo
    echo "  # 使用預設配置文件部署 SOCKS5 實例（會自動啟動）"
    echo "  $0 deploy-socks5"
    echo
    echo "  # 使用自定義配置文件部署 SOCKS5 實例"
    echo "  $0 deploy-socks5 my-config.json"
    echo
    echo "  # 查看所有實例狀態"
    echo "  $0 status"
    echo
    echo "  # 啟動指定的已停止實例"
    echo "  $0 start socks_proxy_01"
    echo
    echo "  # 啟動所有已停止的實例"
    echo "  $0 start-all"
    echo
    echo "  # 重啟指定實例"
    echo "  $0 restart socks_proxy_01"
    echo
    echo "  # 重啟所有運行中的實例"
    echo "  $0 restart-all"
    echo
    echo "  # 停止指定實例"
    echo "  $0 stop socks_proxy_01"
    echo
    echo "  # 停止所有實例"
    echo "  $0 stop-all"
    echo
    echo "  # 查看實例日誌"
    echo "  $0 logs"
    echo
    echo "配置文件："
    echo "  詳細的 SOCKS5 配置說明請參考: docs/Socks5_Config_Readme.md"
    echo
    echo "注意事項："
    echo "  - 所有操作都需要 root 權限，請使用 sudo 執行"
    echo "  - 首次使用前建議執行 'check-docker' 檢查環境"
    echo "  - SOCKS5 部署需要有效的 config.json 配置文件"
    echo "  - 部署操作會創建並自動啟動新實例"
    echo "  - 啟動/停止操作管理已部署的實例，不會重新創建容器"
    echo "  - 重啟操作會保持實例配置不變"
}

# 執行主程序
main "$@"