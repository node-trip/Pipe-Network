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

# Путь к файлу логов
LOG_FILE="/var/log/pipe_install.log"

# Функция для логирования
log_message() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $message" >> "$LOG_FILE"
    echo -e "$message"
}

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
    echo "6. Показать логи установки"
    echo "0. Выход"
    echo
}

# Функция для просмотра логов
show_logs() {
    if [ -f "$LOG_FILE" ]; then
        echo -e "${BLUE}=== Логи установки ===${NC}"
        cat "$LOG_FILE"
        echo
        echo -e "${BLUE}Логи сохранены в файле: $LOG_FILE${NC}"
    else
        echo -e "${RED}Файл логов не найден${NC}"
    fi
    read -n 1 -s -r -p "Нажмите любую клавишу для возврата в меню..."
}

# Функция установки ноды
install_node() {
    # Очищаем старые логи перед новой установкой
    [ -f "$LOG_FILE" ] && mv "$LOG_FILE" "${LOG_FILE}.old"
    
    # Проверяем rate limit перед установкой
    if curl -s "https://api.pipecdn.app/api/v1/node/check-ip" | grep -q "can only register once per hour"; then
        log_message "${RED}Этот IP уже использовался для регистрации в последний час.${NC}"
        log_message "${RED}Пожалуйста, подождите 1 час перед новой установкой.${NC}"
        read -n 1 -s -r -p "Нажмите любую клавишу для возврата в меню..."
        return 1
    fi

    log_message "${RED}ВАЖНО: Для установки ноды требуется:${NC}"
    log_message "${RED}1. Быть в вайтлисте DevNet 2${NC}"
    log_message "${RED}2. Иметь персональную ссылку для скачивания из email${NC}"
    echo
    log_message "${BLUE}Выберите тип установки:${NC}"
    echo "1. Новая установка (создать новую ноду)"
    echo "2. Перенос существующей ноды (использовать существующие Node ID и Token)"
    read -r install_type
    
    if [ "$install_type" = "2" ]; then
        log_message "${BLUE}Введите существующий Node ID:${NC}"
        read -r node_id
        log_message "Введен Node ID: $node_id"
        
        log_message "${BLUE}Введите существующий Token:${NC}"
        read -r token
        log_message "Введен Token: $token"

        # Проверяем введенные данные
        if [ -z "$node_id" ] || [ -z "$token" ]; then
            log_message "${RED}Ошибка: Node ID или Token не могут быть пустыми${NC}"
            read -n 1 -s -r -p "Нажмите любую клавишу для возврата в меню..."
            return 1
        fi

        log_message "${BLUE}Начинаем процесс переноса ноды...${NC}"
        
        # Создаем директорию с логированием
        log_message "${BLUE}Создаем директорию /var/lib/pop${NC}"
        if ! mkdir -p /var/lib/pop 2>/tmp/mkdir.error; then
            log_message "${RED}Ошибка при создании директории: $(cat /tmp/mkdir.error)${NC}"
            read -n 1 -s -r -p "Нажмите любую клавишу для возврата в меню..."
            return 1
        fi

        # Проверяем права на запись
        log_message "${BLUE}Проверяем права на запись в директорию${NC}"
        if ! touch /var/lib/pop/test_write 2>/tmp/touch.error; then
            log_message "${RED}Ошибка прав доступа: $(cat /tmp/touch.error)${NC}"
            read -n 1 -s -r -p "Нажмите любую клавишу для возврата в меню..."
            return 1
        fi
        rm -f /var/lib/pop/test_write

        # Создаем node_info.json с логированием
        log_message "${BLUE}Создаем файл node_info.json${NC}"
        if ! cat > /var/lib/pop/node_info.json.tmp << EOF
{
  "node_id": "${node_id}",
  "registered": true,
  "token": "${token}"
}
EOF
        then
            log_message "${RED}Ошибка при создании временного файла node_info.json${NC}"
            read -n 1 -s -r -p "Нажмите любую клавишу для возврата в меню..."
            return 1
        fi

        # Проверяем JSON перед перемещением
        log_message "${BLUE}Проверяем корректность JSON${NC}"
        if ! jq empty /var/lib/pop/node_info.json.tmp 2>/tmp/jq.error; then
            log_message "${RED}Ошибка в JSON: $(cat /tmp/jq.error)${NC}"
            rm -f /var/lib/pop/node_info.json.tmp
            read -n 1 -s -r -p "Нажмите любую клавишу для возврата в меню..."
            return 1
        fi

        # Перемещаем файл
        log_message "${BLUE}Перемещаем файл в финальное расположение${NC}"
        if ! mv /var/lib/pop/node_info.json.tmp /var/lib/pop/node_info.json 2>/tmp/mv.error; then
            log_message "${RED}Ошибка при перемещении файла: $(cat /tmp/mv.error)${NC}"
            rm -f /var/lib/pop/node_info.json.tmp
            read -n 1 -s -r -p "Нажмите любую клавишу для возврата в меню..."
            return 1
        fi

        # Проверяем финальный файл
        log_message "${BLUE}Проверяем финальный файл${NC}"
        if [ ! -f "/var/lib/pop/node_info.json" ]; then
            log_message "${RED}Ошибка: Финальный файл не существует${NC}"
            read -n 1 -s -r -p "Нажмите любую клавишу для возврата в меню..."
            return 1
        fi

        # Проверяем содержимое
        log_message "${BLUE}Проверяем содержимое файла${NC}"
        saved_node_id=$(jq -r .node_id /var/lib/pop/node_info.json 2>/tmp/jq_read.error)
        if [ $? -ne 0 ]; then
            log_message "${RED}Ошибка при чтении Node ID: $(cat /tmp/jq_read.error)${NC}"
            read -n 1 -s -r -p "Нажмите любую клавишу для возврата в меню..."
            return 1
        fi

        saved_token=$(jq -r .token /var/lib/pop/node_info.json 2>/tmp/jq_read.error)
        if [ $? -ne 0 ]; then
            log_message "${RED}Ошибка при чтении Token: $(cat /tmp/jq_read.error)${NC}"
            read -n 1 -s -r -p "Нажмите любую клавишу для возврата в меню..."
            return 1
        fi

        if [ "$saved_node_id" != "$node_id" ] || [ "$saved_token" != "$token" ]; then
            log_message "${RED}Ошибка: Сохраненные данные не совпадают с введенными${NC}"
            log_message "${RED}Ожидалось: Node ID='$node_id', Token='$token'${NC}"
            log_message "${RED}Получено: Node ID='$saved_node_id', Token='$saved_token'${NC}"
            read -n 1 -s -r -p "Нажмите любую клавишу для возврата в меню..."
            return 1
        fi

        log_message "${GREEN}Файл node_info.json успешно создан и проверен${NC}"
        download_url="https://dl.pipecdn.app/v0.2.8/pop"
    else
        log_message "${BLUE}Введите ссылку для скачивания из письма:${NC}"
        read -r download_url
    fi

    log_message "${GREEN}Начинаем установку ноды...${NC}"
    
    # Проверка системных требований
    mem_gb=$(free -g | awk '/^Mem:/{print $2}')
    
    if [ $mem_gb -lt 4 ]; then
        log_message "${RED}Ошибка: Требуется минимум 4GB RAM. У вас: ${mem_gb}GB${NC}"
        return 1
    fi

    # Создание пользователя
    useradd -r -s /bin/false dcdn-svc-user

    # Создание необходимых директорий
    mkdir -p /opt/dcdn
    mkdir -p /var/lib/pop
    mkdir -p /var/cache/pop/download_cache
    
    # Скачивание и установка бинарного файла
    log_message "${BLUE}Скачиваем ноду...${NC}"
    curl -L -o pop "$download_url"
    chmod +x pop
    mv pop /opt/dcdn/
    
    # Настройка прав доступа
    chown -R dcdn-svc-user:dcdn-svc-user /var/lib/pop
    chown -R dcdn-svc-user:dcdn-svc-user /var/cache/pop
    chown -R dcdn-svc-user:dcdn-svc-user /opt/dcdn

    # Запрос адреса кошелька Solana
    log_message "${BLUE}Введите адрес вашего кошелька Solana (SOL) для получения вознаграждений:${NC}"
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
        log_message "${RED}Ошибка: IP уже использовался для регистрации. Нужно подождать 1 час.${NC}"
        systemctl stop pop
        return 1
    fi

    # Проверяем тип установки после запуска
    if [ "$install_type" = "2" ]; then
        log_message "${GREEN}Нода перенесена с существующим ID: $node_id${NC}"
    else
        # Ждем регистрации только для новой установки
        log_message "${BLUE}Ожидаем регистрации ноды...${NC}"
        for i in {1..24}; do
            sleep 5
            if [ -f "/var/lib/pop/node_info.json" ]; then
                node_id=$(jq -r .node_id /var/lib/pop/node_info.json)
                if [ ! -z "$node_id" ] && [ "$node_id" != "null" ] && [ ${#node_id} -gt 10 ]; then
                    log_message "${GREEN}Нода успешно зарегистрирована с ID: $node_id${NC}"
                    break
                fi
            fi
            log_message "${BLUE}Ожидаем регистрацию... Попытка $i из 24${NC}"
        done
    fi

    log_message "${GREEN}Установка завершена! Нода запущена.${NC}"
    echo
    log_message "${BLUE}Остались вопросы? Присоединяйтесь к нашему Telegram каналу:${NC}"
    log_message "${GREEN}https://t.me/nodetrip${NC}"
    log_message "${BLUE}Там вы найдете:${NC}"
    log_message "${GREEN}• Гайды по установке и настройке нод${NC}"
    log_message "${GREEN}• Новости и обновления${NC}"
    log_message "${GREEN}• Помощь от сообщества${NC}"
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
        6) show_logs ;;
        0) exit 0 ;;
        *) echo -e "${RED}Неверный выбор${NC}" ;;
    esac
done
