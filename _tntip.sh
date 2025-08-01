#!/bin/bash

# TNTIP 管理腳本

# 顏色定義
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 全域變數
CMD_ACTION=""
CMD_TNT_USER=""
CMD_TNT_PASS=""
CMD_ADMIN_USER=""
CMD_ADMIN_PASS=""
CMD_DATA_DIR=""
CMD_TNTIP_PORT=""
CMD_INSTALL="false"
CMD_PROXY_ENABLE=""
CMD_PROXY_HOST=""
CMD_PROXY_USER=""
CMD_PROXY_PASS=""
CMD_SOCKS5_ENABLE=""
CMD_SOCKS5_PROXY=""
CMD_CONTAINER_NAME=""
CMD_NETWORK_MODE=""
CMD_NETWORK_NAME=""
CMD_STATIC_IP=""
CMD_COMPOSE_FILE=""

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
    local install_option="$1"
    
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
                echo -e "${RED}TNTIP 服務需要 Docker，請先安裝 Docker 或使用 -i/--install 參數自動安裝${NC}"
                exit 1
            fi
        fi
    else
        echo -e "${GREEN}Docker 已安裝${NC}"
    fi
    
    # 檢查 Docker Compose 是否已可用
    if ! docker compose version &> /dev/null; then
        echo -e "${YELLOW}警告: 無法使用 Docker Compose。請確保您安裝的是最新版本的 Docker。${NC}"
        echo -e "${YELLOW}嘗試安裝/重新安裝 Docker 以獲得 Docker Compose 功能...${NC}"
        
        if [[ "$install_option" == "true" || "$install_option" == "cn" ]]; then
            install_docker "$install_option"
        else
            read -p "是否現在安裝/重新安裝 Docker? (y/n): " confirm
            if [[ $confirm == [yY] || $confirm == [yY][eE][sS] ]]; then
                install_docker "false"
            else
                echo -e "${RED}TNTIP 服務需要 Docker Compose，無法繼續。${NC}"
                exit 1
            fi
        fi
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
        systemctl start docker
    elif [[ "$ID" == "fedora" ]]; then
        # Fedora 下使用 dnf 安装
        dnf install -y yum-utils device-mapper-persistent-data lvm2
        dnf config-manager --add-repo https://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo
        retry "dnf install -y docker-ce docker-ce-cli containerd.io" "安裝 Docker"
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
        echo -e "${GREEN}Docker 安裝完成！${NC}"
        echo -e "${GREEN}此安裝包含了 Docker Compose 功能${NC}"
        # 移除安裝腳本
        rm get-docker.sh
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        echo -e "${YELLOW}請從 https://docs.docker.com/desktop/install/mac/ 下載並安裝 Docker Desktop for Mac${NC}"
        echo -e "${YELLOW}Docker Desktop 已包含 Docker Compose 功能${NC}"
        exit 1
    elif [[ "$OSTYPE" == "msys" || "$OSTYPE" == "win32" ]]; then
        echo -e "${YELLOW}請從 https://docs.docker.com/desktop/install/windows/ 下載並安裝 Docker Desktop for Windows${NC}"
        echo -e "${YELLOW}Docker Desktop 已包含 Docker Compose 功能${NC}"
        exit 1
    else
        echo -e "${RED}無法識別的作業系統，請手動安裝 Docker${NC}"
        exit 1
    fi
}

# 檢查配置文件是否存在
check_config() {
    local config_needed=false
    
    if [[ ! -f ".env" ]]; then
        echo -e "${YELLOW}.env 檔案不存在，需要進行配置${NC}"
        config_needed=true
    fi
    
    if [[ "$config_needed" = true ]]; then
        read -p "是否現在進行配置? (y/n): " confirm
        if [[ $confirm == [yY] || $confirm == [yY][eE][sS] ]]; then
            config_tntip
        else
            echo -e "${RED}未完成配置，無法啟動服務${NC}"
            return 1
        fi
    fi
    
    return 0
}

# 配置 TNTIP 服務函數
config_tntip() {
    echo -e "${BLUE}正在配置 TNTIP 服務...${NC}"
    
    # 配置 .env 檔案 (互動模式)
    config_env "" "" "admin" "admin" "./data" "50010" "false" "" "" "" "false" "" "" "true"
    
    echo -e "${GREEN}TNTIP 服務配置已完成${NC}"
}

# 生成或修改 .env 檔案
config_env() {
    local tnt_user=${1:-""}
    local tnt_pass=${2:-""}
    local admin_user=${3:-"admin"}
    local admin_pass=${4:-"admin"}
    local data_dir=${5:-"./data"}
    local tntip_port=${6:-"50010"}
    local proxy_enable=${7:-"false"}
    local proxy_host=${8:-""}
    local proxy_user=${9:-""}
    local proxy_pass=${10:-""}
    local socks5_enable=${11:-"false"}
    local socks5_proxy=${12:-""}
    local container_name=${13:-""}
    local interactive=${14:-"true"}
    
    # 只有在互動模式下才請求輸入
    if [[ "$interactive" == "true" ]]; then
        echo -e "${BLUE}設定 TNT_USER (您的Email): ${NC}"
        read -p "(目前: $tnt_user): " input_tnt_user
        tnt_user=${input_tnt_user:-$tnt_user}
        
        echo -e "${BLUE}設定 TNT_PASS (您的密碼): ${NC}"
        read -s -p "(目前: ****): " input_tnt_pass
        echo
        tnt_pass=${input_tnt_pass:-$tnt_pass}
        
        echo -e "${BLUE}設定 ADMIN_USER (管理員用戶名): ${NC}"
        read -p "(預設: $admin_user): " input_admin_user
        admin_user=${input_admin_user:-$admin_user}
        
        echo -e "${BLUE}設定 ADMIN_PASS (管理員密碼): ${NC}"
        read -s -p "(預設: ****): " input_admin_pass
        echo
        admin_pass=${input_admin_pass:-$admin_pass}
        
        echo -e "${BLUE}設定 DATA_DIR (數據目錄): ${NC}"
        read -p "(預設: $data_dir): " input_data_dir
        data_dir=${input_data_dir:-$data_dir}
        
        echo -e "${BLUE}設定 TNTIP_PORT (服務端口): ${NC}"
        read -p "(預設: $tntip_port): " input_tntip_port
        tntip_port=${input_tntip_port:-$tntip_port}
        
        echo -e "${BLUE}設定 CONTAINER_NAME (容器名稱, 多實例時必須唯一): ${NC}"
        read -p "(預設: $container_name): " input_container_name
        container_name=${input_container_name:-$container_name}
        
        echo -e "${BLUE}是否啟用HTTP代理? (true/false): ${NC}"
        read -p "(預設: $proxy_enable): " input_proxy_enable
        proxy_enable=${input_proxy_enable:-$proxy_enable}
        
        if [[ "$proxy_enable" == "true" ]]; then
            echo -e "${BLUE}設定代理主機 (例如: http://127.0.0.1:8080): ${NC}"
            read -p "(目前: $proxy_host): " input_proxy_host
            proxy_host=${input_proxy_host:-$proxy_host}
            
            echo -e "${BLUE}設定代理用戶名 (可選): ${NC}"
            read -p "(目前: $proxy_user): " input_proxy_user
            proxy_user=${input_proxy_user:-$proxy_user}
            
            echo -e "${BLUE}設定代理密碼 (可選): ${NC}"
            read -s -p "(目前: ****): " input_proxy_pass
            echo
            proxy_pass=${input_proxy_pass:-$proxy_pass}
        fi
        
        echo -e "${BLUE}是否啟用SOCKS5代理? (true/false): ${NC}"
        read -p "(預設: $socks5_enable): " input_socks5_enable
        socks5_enable=${input_socks5_enable:-$socks5_enable}
        
        if [[ "$socks5_enable" == "true" ]]; then
            echo -e "${BLUE}設定SOCKS5代理 (例如: socks5://user:pass@host:port): ${NC}"
            read -p "(目前: $socks5_proxy): " input_socks5_proxy
            socks5_proxy=${input_socks5_proxy:-$socks5_proxy}
        fi
    fi
    
    # 生成 .env 檔案
    cat > .env << EOF
TNT_USER="${tnt_user}"
TNT_PASS="${tnt_pass}"
ADMIN_USER="${admin_user}"
ADMIN_PASS="${admin_pass}"
DATA_DIR="${data_dir}"
TNTIP_PORT="${tntip_port}"
PROXY_ENABLE="${proxy_enable}"
PROXY_HOST="${proxy_host}"
PROXY_USER="${proxy_user}"
PROXY_PASS="${proxy_pass}"
SOCKS5_ENABLE="${socks5_enable}"
SOCKS5_PROXY="${socks5_proxy}"
CONTAINER_NAME="${container_name}"
TUN2PROXY_CONTAINER_NAME="${container_name}-tun2proxy"
STATIC_IP="${CMD_STATIC_IP}"
EOF
    echo -e "${GREEN}.env 檔案已生成${NC}"
}

# 啟動 TNTIP 服務函數
start_tntip() {
    if ! check_config; then
        echo -e "${RED}配置檢查失敗，無法啟動 TNTIP 服務${NC}"
        return 1
    fi
    
    echo -e "${GREEN}正在啟動 TNTIP 服務...${NC}"
    
    # 決定使用哪個 compose 文件
    local compose_file="docker-compose.yml"
    if [[ -n "$CMD_COMPOSE_FILE" ]]; then
        compose_file="$CMD_COMPOSE_FILE"
    elif [[ "$CMD_NETWORK_MODE" == "macvlan" ]]; then
        compose_file="docker-compose-macvlan.yml"
        # 檢查 MACVLAN 網路是否存在
        if [[ -n "$CMD_NETWORK_NAME" ]]; then
            if ! docker network ls | grep -q "$CMD_NETWORK_NAME"; then
                echo -e "${RED}錯誤: MACVLAN 網路 '$CMD_NETWORK_NAME' 不存在${NC}"
                echo -e "${YELLOW}請先創建 MACVLAN 網路，參考多實例部署指南${NC}"
                return 1
            fi
        fi
    elif [[ "$CMD_SOCKS5_ENABLE" == "true" || -n "$CMD_SOCKS5_PROXY" ]]; then
        compose_file="docker-compose-socks5.yml"
    fi
    
    echo -e "${BLUE}使用 Docker Compose 文件: $compose_file${NC}"
    
    # 檢查服務是否已經運行
    if docker compose -f "$compose_file" ps | grep -q "Up"; then
        echo -e "${YELLOW}TNTIP 服務已經在運行中${NC}"
        read -p "是否重新啟動? (y/n): " restart
        if [[ $restart != [yY] && $restart != [yY][eE][sS] ]]; then
            echo -e "${BLUE}操作已取消${NC}"
            return 0
        fi
    fi
    
    # 停止現有的容器
    echo -e "${BLUE}停止現有容器...${NC}"
    docker compose -f "$compose_file" down &> /dev/null
    
    # 如果是 MACVLAN 模式，檢查靜態 IP
    if [[ "$compose_file" == "docker-compose-macvlan.yml" && -z "$CMD_STATIC_IP" ]]; then
        echo -e "${RED}錯誤: MACVLAN 模式需要指定靜態 IP (--static-ip)${NC}"
        return 1
    fi
    
    # 拉取最新映像
    echo -e "${BLUE}拉取最新映像...${NC}"
    retry "docker compose -f $compose_file pull" "拉取 Docker 映像"
    if [[ $? -ne 0 ]]; then
        echo -e "${RED}無法拉取最新映像，啟動失敗${NC}"
        return 1
    fi
    
    # 創建數據目錄
    local data_dir_to_create="${CMD_DATA_DIR:-./data}"
    mkdir -p "$data_dir_to_create"
    
    # 啟動服務
    echo -e "${BLUE}啟動 TNTIP 服務...${NC}"
    retry "docker compose -f $compose_file up -d --remove-orphans" "啟動 Docker 容器"
    if [[ $? -ne 0 ]]; then
        echo -e "${RED}啟動 TNTIP 服務失敗${NC}"
        return 1
    fi
    
    echo -e "${GREEN}TNTIP 服務已成功啟動！${NC}"
    
    # 顯示服務信息
    if [[ "$compose_file" == "docker-compose-macvlan.yml" ]]; then
        echo -e "${BLUE}服務將在 http://${CMD_STATIC_IP}:50010 上運行${NC}"
    elif [[ "$compose_file" == "docker-compose-socks5.yml" ]]; then
        echo -e "${BLUE}服務使用 SOCKS5 代理運行${NC}"
    else
        echo -e "${BLUE}服務將在 http://localhost:${CMD_TNTIP_PORT:-50010} 上運行${NC}"
    fi
    
    # 顯示運行中的容器
    echo -e "${BLUE}目前運行中的服務:${NC}"
    docker compose -f "$compose_file" ps
    return 0
}

# 停止 TNTIP 服務函數
stop_tntip() {
    echo -e "${RED}正在停止 TNTIP 服務...${NC}"
    
    # 決定使用哪個 compose 文件
    local compose_file="docker-compose.yml"
    if [[ -n "$CMD_COMPOSE_FILE" ]]; then
        compose_file="$CMD_COMPOSE_FILE"
    elif [[ "$CMD_NETWORK_MODE" == "macvlan" ]]; then
        compose_file="docker-compose-macvlan.yml"
    elif [[ "$CMD_SOCKS5_ENABLE" == "true" || -n "$CMD_SOCKS5_PROXY" ]]; then
        compose_file="docker-compose-socks5.yml"
    fi
    
    # 檢查服務是否正在運行
    if ! docker compose -f "$compose_file" ps | grep -q "Up"; then
        echo -e "${YELLOW}沒有運行中的 TNTIP 服務${NC}"
        return 0
    fi
    
    # 停止服務
    echo -e "${BLUE}停止 Docker 容器...${NC}"
    retry "docker compose -f $compose_file down" "停止 Docker 容器"
    if [[ $? -ne 0 ]]; then
        echo -e "${RED}停止 TNTIP 服務失敗${NC}"
        return 1
    fi
    
    echo -e "${GREEN}TNTIP 服務已成功停止${NC}"
    return 0
}

# 更新 TNTIP 服務函數
update_tntip() {
    echo -e "${BLUE}正在更新 TNTIP 服務...${NC}"
    
    # 決定使用哪個 compose 文件
    local compose_file="docker-compose.yml"
    if [[ -n "$CMD_COMPOSE_FILE" ]]; then
        compose_file="$CMD_COMPOSE_FILE"
    elif [[ "$CMD_NETWORK_MODE" == "macvlan" ]]; then
        compose_file="docker-compose-macvlan.yml"
    elif [[ "$CMD_SOCKS5_ENABLE" == "true" || -n "$CMD_SOCKS5_PROXY" ]]; then
        compose_file="docker-compose-socks5.yml"
    fi
    
    # 停止服務
    echo -e "${BLUE}停止現有服務...${NC}"
    docker compose -f "$compose_file" down &> /dev/null
    
    # 拉取最新映像
    echo -e "${BLUE}拉取最新映像...${NC}"
    retry "docker compose -f $compose_file pull" "拉取最新 Docker 映像"
    if [[ $? -ne 0 ]]; then
        echo -e "${RED}無法拉取最新映像，更新失敗${NC}"
        return 1
    fi
    
    # 重新啟動服務
    echo -e "${BLUE}重新啟動服務...${NC}"
    retry "docker compose -f $compose_file up -d --remove-orphans" "啟動 Docker 容器"
    if [[ $? -ne 0 ]]; then
        echo -e "${RED}重新啟動 TNTIP 服務失敗${NC}"
        return 1
    fi
    
    echo -e "${GREEN}TNTIP 服務已成功更新並重新啟動！${NC}"
    
    # 顯示運行中的容器
    echo -e "${BLUE}目前運行中的服務:${NC}"
    docker compose ps
    return 0
}

# 查看 Docker 日誌
view_docker_logs() {
    echo -e "${BLUE}查看 Docker 日誌...${NC}"
    
    # 決定使用哪個 compose 文件
    local compose_file="docker-compose.yml"
    if [[ -n "$CMD_COMPOSE_FILE" ]]; then
        compose_file="$CMD_COMPOSE_FILE"
    elif [[ "$CMD_NETWORK_MODE" == "macvlan" ]]; then
        compose_file="docker-compose-macvlan.yml"
    elif [[ "$CMD_SOCKS5_ENABLE" == "true" || -n "$CMD_SOCKS5_PROXY" ]]; then
        compose_file="docker-compose-socks5.yml"
    fi
    
    # 檢查 Docker 服務是否運行中
    if ! docker compose -f "$compose_file" ps | grep -q "Up"; then
        echo -e "${YELLOW}警告: 沒有運行中的 Docker 容器${NC}"
        read -p "是否仍要查看最近的日誌? (y/n): " confirm
        if [[ $confirm != [yY] && $confirm != [yY][eE][sS] ]]; then
            return 0
        fi
    fi
    
    # 提供有用的提示
    echo -e "${YELLOW}正在顯示最新的 100 條日誌記錄，按 Ctrl+C 退出...${NC}"
    echo -e "${YELLOW}日誌顯示會實時更新，直到您按下 Ctrl+C${NC}"
    
    # 確定要查看哪個容器的日誌
    local container_name="tntip"
    if [[ "$compose_file" == "docker-compose-socks5.yml" ]]; then
        # SOCKS5 模式下顯示所有容器的日誌
        echo -e "${BLUE}SOCKS5 模式 - 顯示所有容器日誌:${NC}"
        timeout --foreground 30s docker compose -f "$compose_file" logs --tail 100 --follow || true
    else
        # 單容器模式
        timeout --foreground 30s docker compose -f "$compose_file" logs --tail 100 --follow tntip || true
    fi
    echo -e "${GREEN}日誌查看已結束${NC}"
}

# 顯示選單函數
show_menu() {
    clear
    echo "===================================="
    echo "        TNTIP 服務管理選單         "
    echo "===================================="
    echo "1. 啟動 TNTIP 服務"
    echo "2. 停止 TNTIP 服務"
    echo "3. 更新 TNTIP 服務"
    echo "4. 配置 TNTIP 服務"
    echo "5. 查看 Docker 日誌"
    echo "0. 退出"
    echo "===================================="
}

# 統一解析命令行參數
parse_command_args() {
    # 重置全局變數
    CMD_ACTION=""
    CMD_TNT_USER=""
    CMD_TNT_PASS=""
    CMD_ADMIN_USER=""
    CMD_ADMIN_PASS=""
    CMD_DATA_DIR=""
    CMD_TNTIP_PORT=""
    CMD_INSTALL="false"
    CMD_PROXY_ENABLE=""
    CMD_PROXY_HOST=""
    CMD_PROXY_USER=""
    CMD_PROXY_PASS=""
    CMD_SOCKS5_ENABLE=""
    CMD_SOCKS5_PROXY=""
    CMD_CONTAINER_NAME=""
    CMD_NETWORK_MODE=""
    CMD_NETWORK_NAME=""
    CMD_STATIC_IP=""
    CMD_COMPOSE_FILE=""
    
    # 如果沒有參數，直接返回
    if [[ $# -eq 0 ]]; then
        return 0
    fi
    
    # 第一個參數通常是命令
    CMD_ACTION="$1"
    shift
    
    # 處理剩餘參數
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -u|--tnt-user)
                if [[ $# -gt 1 ]]; then
                    CMD_TNT_USER="$2"
                    echo -e "${BLUE}設置 TNT 用戶: $CMD_TNT_USER${NC}"
                    shift 2
                else
                    echo -e "${RED}錯誤: -u/--tnt-user 需要一個參數${NC}"
                    return 1
                fi
                ;;
            -p|--tnt-pass)
                if [[ $# -gt 1 ]]; then
                    CMD_TNT_PASS="$2"
                    echo -e "${BLUE}設置 TNT 密碼: ****${NC}"
                    shift 2
                else
                    echo -e "${RED}錯誤: -p/--tnt-pass 需要一個參數${NC}"
                    return 1
                fi
                ;;
            --admin-user)
                if [[ $# -gt 1 ]]; then
                    CMD_ADMIN_USER="$2"
                    echo -e "${BLUE}設置管理員用戶: $CMD_ADMIN_USER${NC}"
                    shift 2
                else
                    echo -e "${RED}錯誤: --admin-user 需要一個參數${NC}"
                    return 1
                fi
                ;;
            --admin-pass)
                if [[ $# -gt 1 ]]; then
                    CMD_ADMIN_PASS="$2"
                    echo -e "${BLUE}設置管理員密碼: ****${NC}"
                    shift 2
                else
                    echo -e "${RED}錯誤: --admin-pass 需要一個參數${NC}"
                    return 1
                fi
                ;;
            -d|--data-dir)
                if [[ $# -gt 1 ]]; then
                    CMD_DATA_DIR="$2"
                    echo -e "${BLUE}設置數據目錄: $CMD_DATA_DIR${NC}"
                    shift 2
                else
                    echo -e "${RED}錯誤: -d/--data-dir 需要一個參數${NC}"
                    return 1
                fi
                ;;
            --port)
                if [[ $# -gt 1 ]]; then
                    CMD_TNTIP_PORT="$2"
                    echo -e "${BLUE}設置服務端口: $CMD_TNTIP_PORT${NC}"
                    shift 2
                else
                    echo -e "${RED}錯誤: --port 需要一個參數${NC}"
                    return 1
                fi
                ;;
            -i|--install)
                if [[ $# -gt 1 && "$2" != -* ]]; then
                    # 如果下一個參數不是以 - 開頭，就認為是此參數的值
                    CMD_INSTALL="$2"
                    echo -e "${BLUE}設置安裝選項: $CMD_INSTALL${NC}"
                    shift 2
                else
                    CMD_INSTALL="true"
                    echo -e "${BLUE}設置安裝選項: true${NC}"
                    shift
                fi
                ;;
            --proxy-enable)
                if [[ $# -gt 1 ]]; then
                    CMD_PROXY_ENABLE="$2"
                    echo -e "${BLUE}設置代理啟用: $CMD_PROXY_ENABLE${NC}"
                    shift 2
                else
                    echo -e "${RED}錯誤: --proxy-enable 需要一個參數 (true/false)${NC}"
                    return 1
                fi
                ;;
            --proxy-host)
                if [[ $# -gt 1 ]]; then
                    CMD_PROXY_HOST="$2"
                    echo -e "${BLUE}設置代理主機: $CMD_PROXY_HOST${NC}"
                    shift 2
                else
                    echo -e "${RED}錯誤: --proxy-host 需要一個參數${NC}"
                    return 1
                fi
                ;;
            --proxy-user)
                if [[ $# -gt 1 ]]; then
                    CMD_PROXY_USER="$2"
                    echo -e "${BLUE}設置代理用戶: $CMD_PROXY_USER${NC}"
                    shift 2
                else
                    echo -e "${RED}錯誤: --proxy-user 需要一個參數${NC}"
                    return 1
                fi
                ;;
            --proxy-pass)
                if [[ $# -gt 1 ]]; then
                    CMD_PROXY_PASS="$2"
                    echo -e "${BLUE}設置代理密碼: ****${NC}"
                    shift 2
                else
                    echo -e "${RED}錯誤: --proxy-pass 需要一個參數${NC}"
                    return 1
                fi
                ;;
            --socks5-enable)
                if [[ $# -gt 1 ]]; then
                    CMD_SOCKS5_ENABLE="$2"
                    echo -e "${BLUE}設置 SOCKS5 代理啟用: $CMD_SOCKS5_ENABLE${NC}"
                    shift 2
                else
                    echo -e "${RED}錯誤: --socks5-enable 需要一個參數 (true/false)${NC}"
                    return 1
                fi
                ;;
            --socks5-proxy)
                if [[ $# -gt 1 ]]; then
                    CMD_SOCKS5_PROXY="$2"
                    echo -e "${BLUE}設置 SOCKS5 代理: $CMD_SOCKS5_PROXY${NC}"
                    shift 2
                else
                    echo -e "${RED}錯誤: --socks5-proxy 需要一個參數${NC}"
                    return 1
                fi
                ;;
            --container-name)
                if [[ $# -gt 1 ]]; then
                    CMD_CONTAINER_NAME="$2"
                    echo -e "${BLUE}設置容器名稱: $CMD_CONTAINER_NAME${NC}"
                    shift 2
                else
                    echo -e "${RED}錯誤: --container-name 需要一個參數${NC}"
                    return 1
                fi
                ;;
            --network-mode)
                if [[ $# -gt 1 ]]; then
                    CMD_NETWORK_MODE="$2"
                    echo -e "${BLUE}設置網路模式: $CMD_NETWORK_MODE${NC}"
                    shift 2
                else
                    echo -e "${RED}錯誤: --network-mode 需要一個參數${NC}"
                    return 1
                fi
                ;;
            --network-name)
                if [[ $# -gt 1 ]]; then
                    CMD_NETWORK_NAME="$2"
                    echo -e "${BLUE}設置網路名稱: $CMD_NETWORK_NAME${NC}"
                    shift 2
                else
                    echo -e "${RED}錯誤: --network-name 需要一個參數${NC}"
                    return 1
                fi
                ;;
            --static-ip)
                if [[ $# -gt 1 ]]; then
                    CMD_STATIC_IP="$2"
                    echo -e "${BLUE}設置靜態 IP: $CMD_STATIC_IP${NC}"
                    shift 2
                else
                    echo -e "${RED}錯誤: --static-ip 需要一個參數${NC}"
                    return 1
                fi
                ;;
            --compose-file)
                if [[ $# -gt 1 ]]; then
                    CMD_COMPOSE_FILE="$2"
                    echo -e "${BLUE}設置 Docker Compose 文件: $CMD_COMPOSE_FILE${NC}"
                    shift 2
                else
                    echo -e "${RED}錯誤: --compose-file 需要一個參數${NC}"
                    return 1
                fi
                ;;
            *)
                echo -e "${RED}錯誤: 未知參數 $1${NC}"
                return 1
                ;;
        esac
    done
    
    return 0
}

# 執行指定命令
execute_command() {
    local command="$1"
    local tnt_user="$2"
    local tnt_pass="$3"
    local admin_user="$4"
    local admin_pass="$5"
    local data_dir="$6"
    local tntip_port="$7"
    local proxy_enable="$8"
    local proxy_host="$9"
    local proxy_user="${10}"
    local proxy_pass="${11}"
    local socks5_enable="${12}"
    local socks5_proxy="${13}"
    local container_name="${14}"
    
    case "$command" in
        start)
            # 如果提供了參數，先進行配置
            if [[ -n "$tnt_user" || -n "$tnt_pass" || -n "$admin_user" || -n "$admin_pass" || -n "$data_dir" || -n "$tntip_port" || -n "$proxy_enable" || -n "$proxy_host" || -n "$proxy_user" || -n "$proxy_pass" || -n "$socks5_enable" || -n "$socks5_proxy" || -n "$container_name" ]]; then
                # 使用提供的參數或預設值
                config_env "${tnt_user:-your_email@example.com}" "${tnt_pass:-your_password}" "${admin_user:-admin}" "${admin_pass:-admin}" "${data_dir:-./data}" "${tntip_port:-50010}" "${proxy_enable:-false}" "${proxy_host:-}" "${proxy_user:-}" "${proxy_pass:-}" "${socks5_enable:-false}" "${socks5_proxy:-}" "${container_name:-}" "false"
            fi
            start_tntip
            return $?
            ;;
        stop)
            stop_tntip
            return $?
            ;;
        update)
            update_tntip
            return $?
            ;;
        config)
            # 如果提供了參數，使用非互動模式
            if [[ -n "$tnt_user" || -n "$tnt_pass" || -n "$admin_user" || -n "$admin_pass" || -n "$data_dir" || -n "$tntip_port" || -n "$proxy_enable" || -n "$proxy_host" || -n "$proxy_user" || -n "$proxy_pass" || -n "$socks5_enable" || -n "$socks5_proxy" || -n "$container_name" ]]; then
                config_env "${tnt_user:-your_email@example.com}" "${tnt_pass:-your_password}" "${admin_user:-admin}" "${admin_pass:-admin}" "${data_dir:-./data}" "${tntip_port:-50010}" "${proxy_enable:-false}" "${proxy_host:-}" "${proxy_user:-}" "${proxy_pass:-}" "${socks5_enable:-false}" "${socks5_proxy:-}" "${container_name:-}" "false"
            else
                config_tntip
            fi
            return $?
            ;;
        logs)
            view_docker_logs
            return $?
            ;;
        *)
            show_menu
            read -p "請選擇操作 [0-5]: " choice
            handle_menu_choice "$choice"
            return $?
            ;;
    esac
}

# 處理選單選擇
handle_menu_choice() {
    case "$1" in
        1)
            start_tntip
            ;;
        2)
            stop_tntip
            ;;
        3)
            update_tntip
            ;;
        4)
            config_tntip
            ;;
        5)
            view_docker_logs
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
        read -p "請選擇操作 [0-5]: " choice
        handle_menu_choice "$choice"
    fi
}

# 初始化函數，處理所有啟動前的檢查和設置
init() {
    # 解析命令行參數
    parse_command_args "$@"
    
    # 檢查 root 權限
    check_root_privileges
    
    # 檢查 Docker 環境
    check_docker_environment "$CMD_INSTALL"
}

# 主程序函數
main() {
    # 初始化
    init "$@"
    
    if [[ -n "$CMD_ACTION" ]]; then
        # 執行指定的命令
        execute_command "$CMD_ACTION" "$CMD_TNT_USER" "$CMD_TNT_PASS" "$CMD_ADMIN_USER" "$CMD_ADMIN_PASS" "$CMD_DATA_DIR" "$CMD_TNTIP_PORT" "$CMD_PROXY_ENABLE" "$CMD_PROXY_HOST" "$CMD_PROXY_USER" "$CMD_PROXY_PASS" "$CMD_SOCKS5_ENABLE" "$CMD_SOCKS5_PROXY" "$CMD_CONTAINER_NAME"
    else
        show_menu
        read -p "請選擇操作 [0-5]: " choice
        handle_menu_choice "$choice"
    fi
}

# 執行主程序
main "$@"