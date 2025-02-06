#!/bin/bash

# Установка цветов
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color
YELLOW='\033[1;33m'

# Функция для отображения заголовка
print_header() {
    clear
    echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║       Установщик Pipe Network Node     ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
    echo ""
}

# Главное меню
show_main_menu() {
    while true; do
        print_header
        echo -e "${YELLOW}Выберите действие:${NC}"
        echo "1. Проверка системных требований"
        echo "2. Установка зависимостей"
        echo "3. Установка ноды"
        echo "4. Управление нодой"
        echo -e "5. Обновление ноды (DevNet -> TestNet) ${RED}*${NC}"
        echo "6. Удаление ноды"
        echo "0. Выход"
        echo ""
        echo -e "${RED}* Обновление требуется только для старых нод, установленных до января 2024.${NC}"
        echo -e "${RED}  Если вы устанавливаете ноду с нуля - пропустите этот пункт.${NC}"
        echo ""
        read -p "Ваш выбор: " choice

        case $choice in
            1) check_requirements ;;
            2) install_dependencies ;;
            3) install_node ;;
            4) manage_node ;;
            5) 
                echo -e "${YELLOW}Генерация кошелька:${NC}"
                echo -e "${RED}ВНИМАНИЕ! Это действие создаст новый кошелек!${NC}"
                echo -e "${RED}Если у вас уже есть кошелек, не используйте эту опцию.${NC}"
                echo ""
                echo "При генерации вы получите:"
                echo "1. Мнемоническую фразу (seed phrase) из 12 слов"
                echo "2. Публичный ключ"
                echo "3. Приватный ключ"
                echo "4. Keypair"
                echo ""
                echo -e "${RED}ВАЖНО: Сид фразу можно увидеть ТОЛЬКО ПРИ ГЕНЕРАЦИИ!${NC}"
                echo -e "${RED}Обязательно сохраните её в надежном месте!${NC}"
                echo ""
                read -p "Продолжить генерацию? (y/n): " confirm
                if [[ $confirm == "y" ]]; then
                    /opt/dcdn/pipe-tool generate-wallet --node-registry-url="https://rpc.pipedev.network"
                fi
                read -p "Нажмите Enter для продолжения"
                ;;
            6) remove_node ;;
            0) exit 0 ;;
            *) echo -e "${RED}Неверный выбор${NC}" ;;
        esac
    done
}

# Проверка системных требований
check_requirements() {
    print_header
    echo -e "${YELLOW}Проверка системных требований:${NC}"
    echo "Минимальные требования:"
    echo "- RAM: 2 GB"
    echo "- CPU: 2 ядра"
    echo "- Диск: 60 GB SSD"
    echo ""
    echo "Текущие характеристики системы:"
    echo -e "RAM: $(free -h | awk '/^Mem:/ {print $2}')"
    echo -e "CPU: $(nproc) ядер"
    echo -e "Диск: $(df -h / | awk 'NR==2 {print $4}') свободно"
    echo ""
    read -p "Нажмите Enter для возврата в меню"
}

# Установка зависимостей
install_dependencies() {
    print_header
    echo -e "${YELLOW}Установка зависимостей...${NC}"
    sudo apt update && sudo apt upgrade -y
    sudo apt install curl iptables build-essential git wget lz4 jq make gcc nano automake \
    autoconf tmux htop nvme-cli pkg-config libssl-dev libleveldb-dev tar clang aria2 \
    bsdmainutils ncdu unzip libleveldb-dev -y
    echo -e "${GREEN}Зависимости установлены успешно!${NC}"
    read -p "Нажмите Enter для возврата в меню"
}

# Установка ноды
install_node() {
    print_header
    echo -e "${YELLOW}Установка ноды:${NC}"
    
    echo -e "${GREEN}1. Создание директории...${NC}"
    sudo mkdir -p /opt/dcdn
    
    echo -e "${GREEN}2. Настройка переменных...${NC}"
    echo -e "${YELLOW}Для получения ссылок:${NC}"
    echo "1. Найдите в почте письмо 'Welcome to Pipe Network'"
    echo "2. Нажмите на ссылку 'Download here' возле DCDND"
    echo "3. Скопируйте полученный URL"
    echo "4. То же самое для Pipe-Tool"
    echo ""
    read -p "Введите DCDND_URL (ссылка на скачивание dcdnd): " dcdnd_url
    read -p "Введите PIPE_URL (ссылка на скачивание pipe-tool): " pipe_url
    export DCDND_URL="$dcdnd_url"
    export PIPE_URL="$pipe_url"
    
    echo -e "${GREEN}3. Загрузка бинарных файлов...${NC}"
    sudo curl -L "$PIPE_URL" -o /opt/dcdn/pipe-tool
    sudo curl -L "$DCDND_URL" -o /opt/dcdn/dcdnd
    
    echo -e "${GREEN}4. Настройка прав доступа...${NC}"
    sudo chmod +x /opt/dcdn/pipe-tool
    sudo chmod +x /opt/dcdn/dcdnd
    
    echo -e "${GREEN}5. Создание systemd файла...${NC}"
    sudo tee /etc/systemd/system/dcdnd.service << 'EOF'
[Unit]
Description=DCDN Node Service
After=network.target
Wants=network-online.target

[Service]
ExecStart=/opt/dcdn/dcdnd \
                --grpc-server-url=0.0.0.0:8002 \
                --http-server-url=0.0.0.0:8003 \
                --node-registry-url="https://rpc.pipedev.network" \
                --cache-max-capacity-mb=1024 \
                --credentials-dir=/root/.permissionless \
                --allow-origin=*
Restart=always
RestartSec=5
LimitNOFILE=65536
LimitNPROC=4096
StandardOutput=journal
StandardError=journal
SyslogIdentifier=dcdn-node
WorkingDirectory=/opt/dcdn

[Install]
WantedBy=multi-user.target
EOF
    
    echo -e "${GREEN}6. Открытие портов...${NC}"
    sudo ufw allow 8002/tcp
    sudo ufw allow 8003/tcp
    
    echo -e "${GREEN}7. Вход и генерация токена...${NC}"
    /opt/dcdn/pipe-tool login --node-registry-url="https://rpc.pipedev.network"
    /opt/dcdn/pipe-tool generate-registration-token --node-registry-url="https://rpc.pipedev.network"
    
    echo -e "${GREEN}Установка завершена!${NC}"
    read -p "Нажмите Enter для возврата в меню"
}

# Управление нодой
manage_node() {
    while true; do
        print_header
        echo -e "${YELLOW}Управление нодой:${NC}"
        echo "1. Запустить ноду"
        echo "2. Остановить ноду"
        echo "3. Перезапустить ноду"
        echo "4. Проверить статус"
        echo "5. Сгенерировать кошелек"
        echo "6. Привязать кошелек"
        echo "7. Открыть эксплорер в браузере"
        echo "8. Показать данные кошелька"
        echo "0. Назад"
        
        read -p "Выберите действие: " action
        case $action in
            1)
                sudo systemctl daemon-reload
                sudo systemctl enable dcdnd
                sudo systemctl start dcdnd
                read -p "Нажмите Enter для продолжения"
                ;;
            2) 
                sudo systemctl stop dcdnd
                read -p "Нажмите Enter для продолжения"
                ;;
            3) 
                sudo systemctl restart dcdnd
                read -p "Нажмите Enter для продолжения"
                ;;
            4) 
                echo -e "${YELLOW}Проверка статуса ноды:${NC}"
                echo -e "${GREEN}1. Статус systemd сервиса:${NC}"
                sudo systemctl status dcdnd
                echo ""
                echo -e "${GREEN}2. Проверка регистрации ноды:${NC}"
                /opt/dcdn/pipe-tool list-nodes --node-registry-url="https://rpc.pipedev.network/"
                echo ""
                echo -e "${GREEN}3. Проверка портов:${NC}"
                sudo lsof -i :8002,8003
                read -p "Нажмите Enter для продолжения"
                ;;
            5) 
                echo -e "${YELLOW}Генерация кошелька:${NC}"
                echo -e "${RED}ВНИМАНИЕ! Это действие создаст новый кошелек!${NC}"
                echo -e "${RED}Если у вас уже есть кошелек, не используйте эту опцию.${NC}"
                echo ""
                echo "При генерации вы получите:"
                echo "1. Мнемоническую фразу (seed phrase) из 12 слов"
                echo "2. Публичный ключ"
                echo "3. Приватный ключ"
                echo "4. Keypair"
                echo ""
                echo -e "${RED}ВАЖНО: Сид фразу можно увидеть ТОЛЬКО ПРИ ГЕНЕРАЦИИ!${NC}"
                echo -e "${RED}Обязательно сохраните её в надежном месте!${NC}"
                echo ""
                read -p "Продолжить генерацию? (y/n): " confirm
                if [[ $confirm == "y" ]]; then
                    /opt/dcdn/pipe-tool generate-wallet --node-registry-url="https://rpc.pipedev.network"
                fi
                read -p "Нажмите Enter для продолжения"
                ;;
            6) 
                /opt/dcdn/pipe-tool link-wallet --node-registry-url="https://rpc.pipedev.network"
                read -p "Нажмите Enter для продолжения"
                ;;
            7)
                echo -e "${YELLOW}Открываю эксплорер в браузере...${NC}"
                xdg-open "https://explorer.pipedev.network/" 2>/dev/null || \
                echo -e "${RED}Не могу открыть браузер. Посетите вручную:${NC}"
                echo -e "${GREEN}https://explorer.pipedev.network/${NC}"
                read -p "Нажмите Enter для продолжения"
                ;;
            8)
                echo -e "${YELLOW}Данные кошелька:${NC}"
                echo -e "${GREEN}1. Публичный ключ (для проверки баланса):${NC}"
                /opt/dcdn/pipe-tool show-public-key
                echo ""
                echo -e "${GREEN}2. Приватный ключ и Keypair (секретные данные):${NC}"
                echo -e "${YELLOW}Keypair - это адрес для получения наград, его можно использовать в эксплорере${NC}"
                echo -e "${RED}ВНИМАНИЕ: Сохраните все данные в надежном месте!${NC}"
                echo "Нажмите Enter для просмотра секретных данных..."
                read
                /opt/dcdn/pipe-tool show-private-key
                echo ""
                echo -e "${RED}ВАЖНО: ${NC}"
                echo "1. Сохраните все данные в надежном месте"
                echo "2. Keypair используется для проверки наград в эксплорере"
                echo "3. Приватный ключ никому не показывайте"
                read -p "Нажмите Enter для продолжения"
                ;;
            0) return ;;
            *) 
                echo -e "${RED}Неверный выбор${NC}"
                read -p "Нажмите Enter для продолжения"
                ;;
        esac
    done
}

# Обновление ноды
update_node() {
    print_header
    echo -e "${YELLOW}Обновление ноды (DevNet -> TestNet):${NC}"
    echo "1. Перелогиниться"
    echo "2. Сгенерировать новый токен регистрации"
    echo "3. Перезапустить сервис"
    echo "4. Проверить регистрацию ноды"
    echo "0. Назад"
    
    read -p "Выберите шаг: " step
    case $step in
        1) /opt/dcdn/pipe-tool login --node-registry-url="https://rpc.pipedev.network" ;;
        2) /opt/dcdn/pipe-tool generate-registration-token --node-registry-url="https://rpc.pipedev.network" ;;
        3) systemctl restart dcdnd ;;
        4) /opt/dcdn/pipe-tool list-nodes --node-registry-url="https://rpc.pipedev.network" ;;
        0) return ;;
    esac
    read -p "Нажмите Enter для продолжения"
}

# Удаление ноды
remove_node() {
    print_header
    echo -e "${RED}Внимание! Вы собираетесь удалить ноду!${NC}"
    read -p "Вы уверены? (y/n): " confirm
    if [[ $confirm == "y" ]]; then
        sudo systemctl stop dcdnd.service
        sudo systemctl disable dcdnd.service
        sudo rm /etc/systemd/system/dcdnd.service
        sudo systemctl daemon-reload
        rm -r /opt/dcdn
        echo -e "${GREEN}Нода успешно удалена${NC}"
    fi
    read -p "Нажмите Enter для возврата в меню"
}

# Запуск главного меню
show_main_menu 
