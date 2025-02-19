#!/bin/bash

# Проверяем, запущен ли скрипт от имени root
if [ "$EUID" -ne 0 ]; then 
    echo "Пожалуйста, запустите скрипт с правами root (используйте sudo)"
    exit 1
fi

# Проверяем наличие jq
if ! command -v jq &> /dev/null; then
    echo -e "${BLUE}Устанавливаем jq...${NC}"
    apt-get update
    apt-get install -y jq
fi

# Назначаем права на выполнение текущему скрипту
chmod 755 "$0"

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

# Функция для отображения меню
show_menu() {
    clear
    echo -e "${BLUE}=== Pipe Network DevNet 2 - Управление нодой ===${NC}"
    echo -e "${GREEN}Присоединяйтесь к нашему Telegram каналу: ${BLUE}@nodetrip${NC}"
    echo -e "${GREEN}Гайды по нодам, новости, обновления и помощь${NC}"
    echo "------------------------------------------------"
    echo "1. Установить новую ноду"
    echo "2. Мониторинг ноды"
    echo "3. Удалить ноду"
    echo "4. Обновить ноду (быстрое обновление одной командой)"
    echo "5. Показать данные ноды"
    echo "0. Выход"
    echo
}

# Функция установки ноды
install_node() {
    # Проверяем rate limit перед установкой
    if curl -s "https://api.pipecdn.app/api/v1/node/check-ip" | grep -q "can only register once per hour"; then
        echo -e "${RED}Этот IP уже использовался для регистрации в последний час.${NC}"
        echo -e "${RED}Пожалуйста, подождите 1 час перед новой установкой.${NC}"
        read -n 1 -s -r -p "Нажмите любую клавишу для возврата в меню..."
        return 1
    fi

    echo -e "${RED}ВАЖНО: Для установки ноды требуется:${NC}"
    echo -e "${RED}1. Быть в вайтлисте DevNet 2${NC}"
    echo -e "${RED}2. Иметь персональную ссылку для скачивания из email${NC}"
    echo
    echo -e "${BLUE}Выберите тип установки:${NC}"
    echo "1. Новая установка (создать новую ноду)"
    echo "2. Перенос существующей ноды (использовать существующие Node ID и Token)"
    read -r install_type
    
    if [ "$install_type" = "2" ]; then
        echo -e "${BLUE}Введите существующий Node ID:${NC}"
        read -r node_id
        echo -e "${BLUE}Введите существующий Token:${NC}"
        read -r token

        # Создаем node_info.json до установки сервиса
        mkdir -p /var/lib/pop
        cat > /var/lib/pop/node_info.json << EOF
{
  "node_id": "${node_id}",
  "registered": true,
  "token": "${token}"
}
EOF

        download_url="https://dl.pipecdn.app/v0.2.8/pop"
    else
        echo -e "${BLUE}Введите ссылку для скачивания из письма:${NC}"
        read -r download_url
    fi

    echo -e "${GREEN}Начинаем установку ноды...${NC}"
    
    # Проверка системных требований
    mem_gb=$(free -g | awk '/^Mem:/{print $2}')
    disk_gb=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')
    
    if [ $mem_gb -lt 4 ]; then
        echo -e "${RED}Ошибка: Требуется минимум 4GB RAM. У вас: ${mem_gb}GB${NC}"
        return 1
    fi
    
    if [ $disk_gb -lt 100 ]; then
        echo -e "${RED}Ошибка: Требуется минимум 100GB свободного места. У вас: ${disk_gb}GB${NC}"
        return 1
    fi

    # Создание пользователя
    useradd -r -s /bin/false dcdn-svc-user

    # Создание необходимых директорий
    mkdir -p /opt/dcdn
    mkdir -p /var/lib/pop
    mkdir -p /var/cache/pop/download_cache
    
    # Скачивание и установка бинарного файла
    echo -e "${BLUE}Скачиваем ноду...${NC}"
    curl -L -o pop "$download_url"
    chmod +x pop
    mv pop /opt/dcdn/
    
    # Настройка прав доступа
    chown -R dcdn-svc-user:dcdn-svc-user /var/lib/pop
    chown -R dcdn-svc-user:dcdn-svc-user /var/cache/pop
    chown -R dcdn-svc-user:dcdn-svc-user /opt/dcdn

    # Запрос адреса кошелька Solana
    echo -e "${BLUE}Введите адрес вашего кошелька Solana (SOL) для получения вознаграждений:${NC}"
    read -r solana_address

    # Создание сервиса systemd
    cat > /etc/systemd/system/pop.service << EOF
[Unit]
Description=Pipe POP Node Service
After=network.target

[Service]
Type=simple
User=dcdn-svc-user
WorkingDirectory=/var/lib/pop
ExecStart=/opt/dcdn/pop --ram=8 --pubKey ${solana_address} --max-disk 200 --cache-dir /var/cache/pop/download_cache
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    # Запускаем сервис
    systemctl daemon-reload
    systemctl enable pop
    systemctl start pop

    # Проверяем логи на наличие rate limit
    sleep 5
    if journalctl -u pop -n 50 | grep -q "Rate limit"; then
        echo -e "${RED}Ошибка: IP уже использовался для регистрации. Нужно подождать 1 час.${NC}"
        systemctl stop pop
        return 1
    fi

    # Проверяем тип установки после запуска
    if [ "$install_type" = "2" ]; then
        echo -e "${GREEN}Нода перенесена с существующим ID: $node_id${NC}"
    else
        # Ждем регистрации только для новой установки
        echo -e "${BLUE}Ожидаем регистрации ноды...${NC}"
        for i in {1..24}; do
            sleep 5
            if [ -f "/var/lib/pop/node_info.json" ]; then
                node_id=$(jq -r .node_id /var/lib/pop/node_info.json)
                if [ ! -z "$node_id" ] && [ "$node_id" != "null" ] && [ ${#node_id} -gt 10 ]; then
                    echo -e "${GREEN}Нода успешно зарегистрирована с ID: $node_id${NC}"
                    break
                fi
            fi
            echo -e "${BLUE}Ожидаем регистрацию... Попытка $i из 24${NC}"
        done
    fi

    echo -e "${GREEN}Установка завершена! Нода запущена.${NC}"
    echo
    echo -e "${BLUE}Остались вопросы? Присоединяйтесь к нашему Telegram каналу:${NC}"
    echo -e "${GREEN}https://t.me/nodetrip${NC}"
    echo -e "${BLUE}Там вы найдете:${NC}"
    echo -e "${GREEN}• Гайды по установке и настройке нод${NC}"
    echo -e "${GREEN}• Новости и обновления${NC}"
    echo -e "${GREEN}• Помощь от сообщества${NC}"
    read -n 1 -s -r -p "Нажмите любую клавишу для возврата в меню..."
}

# Функция мониторинга
monitor_node() {
    while true; do
        clear
        echo -e "${BLUE}=== Мониторинг ноды ===${NC}"
        echo "1. Статус сервиса"
        echo "2. Просмотр метрик"
        echo "3. Проверить поинты"
        echo "0. Вернуться в главное меню"
        echo
        read -r subchoice

        case $subchoice in
            1)
                echo -e "${BLUE}Статус сервиса:${NC}"
                systemctl status pop
                read -n 1 -s -r -p "Нажмите любую клавишу для продолжения..."
                ;;
            2)
                echo -e "${BLUE}Метрики ноды:${NC}"
                cd /var/lib/pop && /opt/dcdn/pop --status
                read -n 1 -s -r -p "Нажмите любую клавишу для продолжения..."
                ;;
            3)
                echo -e "${BLUE}Информация о поинтах:${NC}"
                cd /var/lib/pop && /opt/dcdn/pop --points
                read -n 1 -s -r -p "Нажмите любую клавишу для продолжения..."
                ;;
            0)
                return
                ;;
            *)
                echo -e "${RED}Неверный выбор${NC}"
                read -n 1 -s -r -p "Нажмите любую клавишу для продолжения..."
                ;;
        esac
    done
}

# Функция удаления ноды
remove_node() {
    echo -e "${RED}Вы уверены, что хотите удалить ноду? (y/n)${NC}"
    read -r confirm
    if [ "$confirm" = "y" ]; then
        systemctl stop pop
        systemctl disable pop
        rm /etc/systemd/system/pop.service
        systemctl daemon-reload
        rm -rf /opt/dcdn
        rm -rf /var/lib/pop
        rm -rf /var/cache/pop
        userdel dcdn-svc-user
        echo -e "${GREEN}Нода успешно удалена${NC}"
    fi
    read -n 1 -s -r -p "Нажмите любую клавишу для возврата в меню..."
}

# Функция обновления ноды
update_node() {
    echo -e "${GREEN}Начинаем обновление ноды...${NC}"
    
    # Останавливаем сервис
    systemctl stop pop
    
    # Скачиваем новую версию
    curl -L -o pop "https://dl.pipecdn.app/v0.2.8/pop"
    chmod +x pop
    mv pop /opt/dcdn/
    
    # Обновляем права доступа
    chown dcdn-svc-user:dcdn-svc-user /opt/dcdn/pop
    
    # Проверяем версию после обновления
    new_version=$(/opt/dcdn/pop --version | grep -oP 'Pipe PoP Cache Node \K[\d.]+')
    if [ "$new_version" = "0.2.8" ]; then
        echo -e "${GREEN}Успешно обновлено до версии 0.2.8${NC}"
    else
        echo -e "${RED}Ошибка обновления. Текущая версия: $new_version${NC}"
    fi
    
    # Перезапускаем сервис
    systemctl start pop
    
    echo -e "${GREEN}Обновление завершено! Нода перезапущена.${NC}"
    read -n 1 -s -r -p "Нажмите любую клавишу для возврата в меню..."
}

# Функция просмотра данных ноды
show_node_info() {
    if [ -f "/var/lib/pop/node_info.json" ]; then
        echo -e "${BLUE}Данные ноды:${NC}"
        echo -e "${GREEN}Node ID:${NC} $(jq -r .node_id /var/lib/pop/node_info.json)"
        echo -e "${GREEN}Token:${NC} $(jq -r .token /var/lib/pop/node_info.json)"
    else
        echo -e "${RED}Файл node_info.json не найден!${NC}"
    fi
    read -n 1 -s -r -p "Нажмите любую клавишу для возврата в меню..."
}

update() {
    systemctl stop pop && \
    wget https://dl.pipecdn.app/v0.2.8/pop -O pop && \
    chmod +x pop && \
    mv pop /opt/dcdn/pop && \
    systemctl start pop && \
    systemctl status pop
}

# Основной цикл меню
while true; do
    show_menu
    read -r choice
    case $choice in
        1) install_node ;;
        2) monitor_node ;;
        3) remove_node ;;
        4) update_node ;;
        5) show_node_info ;;
        0) exit 0 ;;
        *) echo -e "${RED}Неверный выбор${NC}" ;;
    esac
done
